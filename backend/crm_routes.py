"""Authenticated CRM endpoints; all database requests use the caller's JWT."""
from __future__ import annotations

from collections import defaultdict, deque
from datetime import date, datetime, timedelta, timezone
from threading import Lock
from time import monotonic
from typing import Annotated, Literal
from uuid import UUID

import requests
from fastapi import APIRouter, Depends, Header, HTTPException, Query
from fastapi.responses import JSONResponse
from pydantic import AwareDatetime, BaseModel, ConfigDict, Field

from . import config, crm_ai
from . import crm_sales as sales

router = APIRouter(prefix="/api/crm/sales", tags=["CRM Sales"])
_calls = defaultdict(deque)
_lock = Lock()


class Gateway:
    def __init__(self, token):
        self.headers = {"apikey": config.SUPABASE_KEY, "Authorization": "Bearer " + token,
                        "Content-Type": "application/json", "Prefer": "return=representation"}
        self.uid = None

    def request(self, path, method="GET", data=None, params=None):
        try:
            response = requests.request(method, config.SUPABASE_URL.rstrip("/") + path,
                                        headers=self.headers, json=data, params=params, timeout=20)
        except requests.RequestException:
            raise HTTPException(503, "CRM temporarily unavailable") from None
        if response.status_code in (401, 403):
            raise HTTPException(response.status_code, "CRM access denied")
        if not response.ok:
            raise HTTPException(503, "CRM request failed; verify migrations and retry")
        try:
            return response.json() if response.content else None
        except ValueError:
            raise HTTPException(503, "CRM returned an invalid response; retry shortly") from None

    def rows(self, table, **params):
        limit = params.get("limit", 0)
        if limit <= 500:
            return self.request("/rest/v1/" + table, params=params)
        # PostgREST commonly caps individual responses at 1,000 rows. Page below
        # that cap instead of treating a truncated response as the whole dataset.
        result = []
        start = params.get("offset", 0)
        for offset in range(0, limit, 500):
            size = min(500, limit - offset)
            page = self.request("/rest/v1/" + table, params={**params, "limit": size, "offset": start + offset})
            result.extend(page)
            if len(page) < size:
                break
        return result

    def owned_lead(self, lead_id):
        rows = self.rows("clients", id="eq." + str(lead_id), owner_id="eq." + self.uid, select="*")
        if not rows:
            raise HTTPException(404, "Client not found")
        rows[0]["stage"] = sales.normalize_stage(rows[0].get("stage"))
        return rows[0]

    def rpc(self, name, data):
        return self.request("/rest/v1/rpc/" + name, "POST", data)


def authenticated(authorization: str = Header(default="")):
    if not authorization.startswith("Bearer ") or len(authorization) > 12000:
        raise HTTPException(401, "Sign in required")
    gateway = Gateway(authorization[7:])
    user = gateway.request("/auth/v1/user")
    if not isinstance(user, dict) or not user.get("id"):
        raise HTTPException(401, "Sign in required")
    gateway.uid = str(UUID(user["id"]))
    # Per-worker protection; production shared limiting belongs at the gateway.
    now = monotonic()
    with _lock:
        for uid in list(_calls):
            if not _calls[uid] or _calls[uid][-1] < now - 60:
                del _calls[uid]
        recent = _calls[gateway.uid]
        while recent and recent[0] < now - 60:
            recent.popleft()
        if len(recent) >= 30:
            raise HTTPException(429, "Please wait before trying again", headers={"Retry-After": "60"})
        recent.append(now)
    return gateway


UserGateway = Annotated[Gateway, Depends(authenticated)]


def legacy_lead_analysis(token, lead_id):
    """Keep the existing AI panel while validating its legacy body-token request."""
    if not isinstance(token, str) or not token:
        raise HTTPException(401, "Sign in required")
    try:
        lead_id = UUID(str(lead_id))
    except ValueError:
        raise HTTPException(422, "Invalid client id") from None
    gateway = authenticated("Bearer " + token)
    gateway.owned_lead(lead_id)
    return crm_ai.analyze_lead(token, str(lead_id))


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid", str_max_length=4000, str_strip_whitespace=True, allow_inf_nan=False)


class Extraction(Input):
    text: str = Field(min_length=3, max_length=4000)


class Profile(Input):
    requirements: sales.Requirements
    email: str = Field(default="", max_length=254)
    whatsapp: str = Field(default="", max_length=30)
    expected_updated_at: datetime


class Message(Input):
    language: Literal["ar", "en"] = "ar"
    channel: Literal["whatsapp", "email", "phone"] = "whatsapp"
    occasion: Literal["initial", "followup", "property", "meeting", "post_meeting", "offer", "reengagement"] = "followup"
    tone: Literal["professional", "friendly", "short", "persuasive"] = "professional"


class Offer(Input):
    listing_ids: list[UUID] = Field(min_length=1, max_length=8)
    language: Literal["ar", "en"] = "ar"


class Followup(Input):
    kind: Literal["call", "whatsapp", "meeting", "email", "offer_followup", "other"]
    title: str = Field(min_length=1, max_length=1000)
    due_at: AwareDatetime
    priority: Literal["low", "medium", "high"] = "medium"
    reminder_minutes: Literal[0, 15, 60, 1440] = 0
    local_day: date


@router.post("/extract")
def extract(body: Extraction, gateway: UserGateway):
    return sales.extract_client_requirements(body.text)


@router.put("/clients/{lead_id}/profile")
def profile(lead_id: UUID, body: Profile, gateway: UserGateway):
    gateway.owned_lead(lead_id)
    result = gateway.rpc("crm_save_sales_profile", {"p_lead": str(lead_id),
        "p_requirements": body.requirements.model_dump(exclude_none=True), "p_email": body.email,
        "p_whatsapp": body.whatsapp, "p_expected": body.expected_updated_at.isoformat()})
    if result.get("conflict"):
        raise HTTPException(409, "Client changed. Reopen the profile before saving.")
    return result


def context(gateway, lead_id):
    lead = gateway.owned_lead(lead_id)
    activities = gateway.rows("crm_lead_activities", lead_id="eq." + str(lead_id),
                              select="*", order="created_at.desc", limit=10000)
    req = sales.profile_requirements(lead)
    # Fetch the complete visible inventory in bounded pages; never silently rank a random subset.
    inventory = []
    for offset in range(0, 10000, 500):
        page = gateway.rows("listings", status="eq.active", select="*,listing_media(url,sort)",
                            order="id", limit=500, offset=offset)
        inventory.extend(page)
        if len(page) < 500:
            break
    return lead, req, activities, sales.find_property_matches(req, inventory), len(inventory) >= 10000


@router.get("/clients/{lead_id}/copilot")
def copilot(lead_id: UUID, gateway: UserGateway, language: Literal["ar", "en"] = "ar"):
    lead, req, activities, matches, limited = context(gateway, lead_id)
    lead["last_contact"] = next((a.get("created_at") for a in activities if a.get("kind") in ("call", "whatsapp", "email")), None)
    broker_profile = gateway.rows("profiles", id="eq." + gateway.uid, select="full_name,company,phone")
    tasks = gateway.rows("crm_tasks", lead_id="eq." + str(lead_id), owner_id="eq." + gateway.uid,
                         select="*", order="created_at.desc", limit=100)
    behavior = gateway.rows("crm_behavior_events", lead_id="eq." + str(lead_id), owner_id="eq." + gateway.uid,
                            select="kind,body,meta,listing_id,created_at", order="created_at.desc", limit=10000)
    combined = activities + [{**event, "source": "marketplace"} for event in behavior]
    timeline = list(combined)
    for match in matches:
        match["interest_count"] = sum(event.get("listing_id") == match["property"]["id"] and event["kind"] in ("viewed", "saved", "inquiry") for event in behavior)
    matches.sort(key=lambda item: (-item["score"], -item["interest_count"], -item["coverage"]))
    if lead.get("created_at"):
        timeline.append({"kind": "lead_created", "body": lead.get("name"), "created_at": lead["created_at"]})
    for task in tasks:
        timeline.append({"kind": "followup_scheduled", "body": task.get("title"),
                         "created_at": task.get("created_at"), "due_at": task.get("due_at")})
        if task.get("completed_at"):
            timeline.append({"kind": "followup_completed", "body": task.get("title"), "created_at": task["completed_at"]})
    timeline = sorted(timeline, key=lambda a: a.get("created_at") or "", reverse=True)[:200]
    return {"client": lead, "broker": broker_profile[0] if broker_profile else {}, "requirements": req, "activities": timeline,
            "lead_score": sales.calculate_lead_score(req, combined), "matches": matches[:20],
            **sales.generate_advice(lead, req, combined, matches, language),
            "inventory_limited": limited, "activity_limit": 200,
            "score_limited": max(len(activities),len(behavior)) >= 10000}


@router.post("/clients/{lead_id}/behavior-invite")
def behavior_invite(lead_id: UUID, gateway: UserGateway):
    gateway.owned_lead(lead_id)
    return {"invite": gateway.rpc("crm_invite_behavior", {"p_lead": str(lead_id)})}


@router.post("/clients/{lead_id}/followups")
def schedule_followup(lead_id: UUID, body: Followup, gateway: UserGateway):
    gateway.owned_lead(lead_id)
    return gateway.rpc("crm_sales_schedule_followup", {"p_lead": str(lead_id), "p_kind": body.kind,
        "p_title": body.title, "p_due": body.due_at.isoformat(), "p_priority": body.priority,
        "p_reminder_minutes": body.reminder_minutes, "p_local_day": body.local_day.isoformat()})


@router.post("/clients/{lead_id}/message")
def message(lead_id: UUID, body: Message, gateway: UserGateway):
    lead = gateway.owned_lead(lead_id)
    return sales.generate_sales_message(lead, sales.profile_requirements(lead), **body.model_dump())


@router.post("/clients/{lead_id}/offers")
def offer(lead_id: UUID, body: Offer, gateway: UserGateway):
    gateway.owned_lead(lead_id)
    # RPC snapshots the real inventory and writes the timeline in one transaction.
    return gateway.rpc("crm_create_sales_offer", {"p_lead": str(lead_id),
        "p_listings": [str(i) for i in dict.fromkeys(body.listing_ids)], "p_language": body.language})


@router.get("/clients/{lead_id}/offers")
def offers(lead_id: UUID, gateway: UserGateway):
    gateway.owned_lead(lead_id)
    return gateway.rows("crm_offers", lead_id="eq." + str(lead_id), owner_id="eq." + gateway.uid,
                        select="*", order="created_at.desc", limit=100)


@router.get("/search")
def search(gateway: UserGateway, q: str = Query(min_length=2, max_length=100)):
    return gateway.rpc("crm_sales_search", {"p_query": q})


def score_rows(leads, activities):
    grouped = defaultdict(list)
    for activity in activities:
        grouped[activity.get("lead_id")].append(activity)
    result = {}
    for lead in leads:
        try:
            requirements = sales.profile_requirements(lead)
        except ValueError:
            requirements = {}
        result[lead["id"]] = sales.calculate_lead_score(requirements, grouped[lead["id"]])
    return result


@router.get("/scores")
def scores(gateway: UserGateway):
    leads = gateway.rows("clients", owner_id="eq." + gateway.uid, select="*", order="id", limit=1000)
    since = "gte." + (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    activities = gateway.rows("crm_lead_activities", created_at=since,
                              select="lead_id,kind,created_at,clients!inner(owner_id)",
                              order="created_at.desc", limit=10000, **{"clients.owner_id": "eq." + gateway.uid})
    behavior = gateway.rows("crm_behavior_events", owner_id="eq." + gateway.uid, created_at=since,
                            select="lead_id,kind,listing_id,created_at", order="created_at.desc", limit=10000)
    return {"scores": score_rows(leads, activities + behavior),
            "limited": len(leads) >= 1000 or len(activities) >= 10000 or len(behavior) >= 10000}


@router.post("/offers/{offer_id}/share")
def share_offer(offer_id: UUID, gateway: UserGateway):
    return gateway.rpc("crm_share_sales_offer", {"p_offer": str(offer_id)})


@router.delete("/offers/{offer_id}/share")
def revoke_offer(offer_id: UUID, gateway: UserGateway):
    gateway.rpc("crm_revoke_sales_offer", {"p_offer": str(offer_id)})
    return {"ok": True}


@router.get("/public-offers/{token}")
def public_offer(token: UUID):
    # Opaque, expiring capability link. The RPC exposes only the offer snapshot.
    gateway = Gateway("")
    gateway.headers.pop("Authorization")
    result = gateway.rpc("crm_read_sales_offer", {"p_token": str(token)})
    if not result:
        raise HTTPException(404, "Offer expired or unavailable")
    return JSONResponse(result, headers={"Cache-Control": "no-store", "Referrer-Policy": "no-referrer"})


@router.get("/overview")
def overview(gateway: UserGateway, offset: int = Query(default=0, ge=-840, le=840),
             language: Literal["ar", "en"] = "ar"):
    leads = gateway.rows("clients", owner_id="eq." + gateway.uid, select="*", order="id", limit=1000)
    deals = gateway.rows("crm_deals", owner_id="eq." + gateway.uid, select="*", order="id", limit=1000)
    tasks = gateway.rows("crm_tasks", owner_id="eq." + gateway.uid, select="*", order="id", limit=1000)
    views = gateway.rows("crm_viewings", owner_id="eq." + gateway.uid, select="*", order="id", limit=1000)
    activities = gateway.rows("crm_lead_activities",
                              select="lead_id,kind,body,created_at,meta,clients!inner(owner_id)",
                              order="created_at.desc", limit=10000, **{"clients.owner_id": "eq." + gateway.uid})
    behavior = gateway.rows("crm_behavior_events", owner_id="eq." + gateway.uid,
                            select="lead_id,kind,listing_id,created_at", order="created_at.desc", limit=10000)
    fresh_scores = score_rows(leads, activities + behavior)
    for lead in leads:
        lead["stage"] = sales.normalize_stage(lead.get("stage"))
        lead.update(lead_score=fresh_scores[lead["id"]]["score"], temperature=fresh_scores[lead["id"]]["temperature"])
    performance = sales.calculate_performance(leads, deals, tasks, activities, views)
    local_tz = timezone(timedelta(minutes=-offset))
    now = datetime.now(local_tz)
    today = now.date().isoformat()
    def day(value):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(local_tz).date().isoformat()
        except (ValueError, TypeError, AttributeError):
            return None
    active = [d for d in deals if d.get("status") not in ("won", "lost")]
    won = [d for d in deals if d.get("status") == "won"]
    pending = [t for t in tasks if t.get("status") not in ("done", "cancelled")]
    def overdue(value):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")) < now
        except (ValueError, TypeError, AttributeError):
            return False
    late = [t for t in pending if overdue(t.get("due_at"))]
    active_leads = [l for l in leads if l.get("stage") not in ("closed", "lost")]
    late_leads = [l for l in active_leads if l.get("next_followup") and l["next_followup"][:10] < today]
    attention = [d for d in active if d.get("expected_close") and d["expected_close"][:10] <= today]
    notifications = []
    # Stable IDs let the browser dismiss one item without hiding future reminders.
    for item in late:
        notifications.append({"id": f"task:{item['id']}:{today}", "priority": "high", "type": "overdue", "title": item.get("title"), "lead_id": item.get("lead_id")})
    for item in attention:
        notifications.append({"id": f"deal:{item['id']}:{today}", "priority": "high", "type": "deal_attention", "title": item.get("property_title"), "lead_id": item.get("lead_id")})
    for item in pending:
        meta = item.get("meta") if isinstance(item.get("meta"), dict) else {}
        if (day(item.get("due_at")) == today or overdue(meta.get("reminder_at"))) and not overdue(item.get("due_at")):
            notifications.append({"id": f"task:{item['id']}:{today}", "priority": "medium", "type": "followup_due", "title": item.get("title"), "lead_id": item.get("lead_id")})
    for item in views:
        if day(item.get("scheduled_at")) == today and item.get("status") in ("scheduled", "confirmed"):
            notifications.append({"id": f"meeting:{item['id']}:{today}", "priority": "medium", "type": "meeting_today", "title": item.get("property_title"), "lead_id": item.get("lead_id")})
    for item in active_leads:
        if item.get("next_followup", "") == today:
            notifications.append({"id": f"followup:{item['id']}:{today}", "priority": "medium", "type": "followup_due", "title": item.get("name"), "lead_id": item["id"]})
        if item.get("temperature") == "hot":
            notifications.append({"id": f"hot:{item['id']}", "priority": "high", "type": "hot_lead", "title": item.get("name"), "lead_id": item["id"]})
        if item.get("stage") == "new" and day(item.get("created_at")) == today:
            notifications.append({"id": f"new:{item['id']}", "priority": "medium", "type": "new_lead", "title": item.get("name"), "lead_id": item["id"]})
    notifications.sort(key=lambda n: 0 if n["priority"] == "high" else 1)
    insights = [{"key": "overdue_followups", "count": len(late)},
                {"key": "missing_next_followup", "count": sum(not l.get("next_followup") for l in active_leads)}]
    advice, engine = sales._ai_json("Give one concise broker performance insight and an actionable recommendation. "
        "Use only the supplied aggregate counts. Do not invent conversion statistics. Use requested language.",
        {"language": language, "leads": len(leads), "open_deals": len(active), "won_deals": len(won), "followups": insights, "performance": performance}, sales.MessageDraft)
    return {"leads": leads, "deals": deals, "tasks": tasks, "notifications": notifications[:50], "recent_activity": activities[:12],
            "ai_insight": advice.message if advice else None, "engine": engine,
            "performance": performance,
            "limited": max(len(leads), len(deals), len(tasks), len(views)) >= 1000 or max(len(activities),len(behavior)) >= 10000,
            "kpis": {"total_leads": len(leads), "new_leads": sum(l.get("stage") == "new" for l in leads),
                     "hot_leads": sum(l.get("temperature") in ("hot", "very_hot") for l in leads),
                     "active_deals": len(active), "closed_deals": len(won),
                     "followups_today": sum(l.get("next_followup") == today for l in active_leads),
                     "overdue_followups": len(late_leads),
                     "meetings_today": sum(day(v.get("scheduled_at")) == today and v.get("status") in ("scheduled", "confirmed") for v in views),
                     "offers_sent": sum(l.get("stage") == "offer_sent" for l in leads),
                     "lost_deals": sum(d.get("status") == "lost" for d in deals),
                     "pipeline_value": sum(float(d.get("value") or 0) for d in active),
                     "weighted_pipeline_value": sum(float(d.get("value") or 0) * float(d.get("probability") or 0) / 100 for d in active),
                     "conversion_rate": round(100 * len({d.get('lead_id') for d in won if d.get('lead_id')}) / len(leads), 1) if leads else 0,
                     "overdue_tasks": len(late), "followup_completion": round(100 * sum(t.get("status") == "done" for t in tasks) / len(tasks), 1) if tasks else 0},
            "insights": insights}
