"""Paymob (Accept) payment gateway — Unified Intention API.

Flow: the browser asks /api/pay/create → we compute the amount SERVER-SIDE,
create a pay_intent (server-authoritative), create a Paymob intention with the
Secret Key, and return the hosted checkout URL. After payment Paymob POSTs to
/api/pay/webhook; we verify the HMAC and settle the intent (confirm booking /
activate subscription / top up wallet) idempotently.

All secrets come from the Vercel env (config). If unset, payments are simply
off and the trial/mock paths keep working.
"""
from __future__ import annotations

import hashlib
import hmac as _hmac
from typing import Any

from . import config, notify

TOKEN = "ELsEiHprVIZCwcsJz0j5Hk_PGuZ7Zx9q"  # shared secret for the settle RPCs

# Order Paymob concatenates transaction fields in, to compute the callback HMAC.
_HMAC_ORDER = [
    "amount_cents", "created_at", "currency", "error_occured",
    "has_parent_transaction", "id", "integration_id", "is_3d_secure",
    "is_auth", "is_capture", "is_refunded", "is_standalone_payment",
    "is_voided", "order", "owner", "pending", "source_data.pan",
    "source_data.sub_type", "source_data.type", "success",
]


def enabled() -> bool:
    p = config.PAYMENT_PROVIDER
    if p == "kashier":
        return bool(config.KASHIER_MID and config.KASHIER_API_KEY)
    if p == "paymob":
        return bool(config.PAYMOB_SECRET_KEY and config.PAYMOB_PUBLIC_KEY
                    and config.PAYMOB_INTEGRATION_IDS)
    return False


def _hs256(key: str, msg: str) -> str:
    return _hmac.new(key.encode(), msg.encode(), hashlib.sha256).hexdigest()


def _kashier_checkout(intent_id: str, amount: float, currency: str) -> str:
    """Build the Kashier Hosted Payment Page URL (signed)."""
    from urllib.parse import quote
    mid = config.KASHIER_MID
    amt = f"{amount:.2f}"
    path = f"/?payment={mid}.{intent_id}.{amt}.{currency}"
    h = _hs256(config.KASHIER_API_KEY, path)
    params = {
        "merchantId": mid, "orderId": intent_id, "amount": amt, "currency": currency,
        "hash": h, "mode": config.KASHIER_MODE,
        "merchantRedirect": config.PUBLIC_SITE.rstrip("/") + "/pay/return",
        "serverWebhook": config.API_SITE.rstrip("/") + "/api/pay/webhook",
        "allowedMethods": "card,wallet", "display": "ar", "redirectMethod": "get",
    }
    qs = "&".join(f"{k}={quote(str(v))}" for k, v in params.items())
    return config.KASHIER_CHECKOUT.rstrip("/") + "/?" + qs


def handle_kashier_webhook(payload: dict) -> dict[str, Any]:
    """Validate the Kashier webhook signature (over its own signatureKeys) and settle."""
    data = (payload or {}).get("data") or {}
    keys = data.get("signatureKeys") or []
    if not keys:
        return {"ok": False, "error": "no_signature_keys"}
    qs = "&".join(f"{k}={data.get(k)}" for k in keys)
    sig = _hs256(config.KASHIER_API_KEY, qs)
    if not _hmac.compare_digest(sig, str(data.get("signature") or "")):
        return {"ok": False, "error": "bad_signature"}
    status = str(data.get("status") or "").upper()
    if status not in ("SUCCESS", "PAID", "APPROVED"):
        return {"ok": True, "ignored": status}
    ref = data.get("merchantOrderId") or data.get("orderId")
    if not ref:
        return {"ok": False, "error": "no_reference"}
    txn = data.get("transactionId") or data.get("kashierOrderId") or data.get("orderReference") or ""
    try:
        res = _rpc("pay_settle", {"p_key": TOKEN, "p_intent": str(ref), "p_provider_ref": str(txn)})
        return {"ok": True, "settle": res}
    except Exception as exc:  # pragma: no cover
        return {"ok": False, "error": "settle_failed", "detail": str(exc)}


def _headers() -> dict[str, str]:
    return {"apikey": config.SUPABASE_KEY,
            "Authorization": "Bearer " + config.SUPABASE_KEY,
            "Content-Type": "application/json"}


def _rpc(fn: str, args: dict) -> Any:
    import requests
    r = requests.post(config.SUPABASE_URL.rstrip("/") + "/rest/v1/rpc/" + fn,
                      headers=_headers(), json=args, timeout=20)
    r.raise_for_status()
    t = r.text
    return __import__("json").loads(t) if t else None


def _integration_ids() -> list[int]:
    out = []
    for x in (config.PAYMOB_INTEGRATION_IDS or "").split(","):
        x = x.strip()
        if x.isdigit():
            out.append(int(x))
    return out


def _amount_for(kind: str, ref: dict, user: dict, token: str) -> tuple[float, str, str]:
    """Return (amount, currency, human_name) computed server-side, or raise."""
    import requests
    hdr = {"apikey": config.SUPABASE_KEY, "Authorization": "Bearer " + token}
    base = config.SUPABASE_URL.rstrip("/") + "/rest/v1"
    if kind == "booking":
        bid = ref.get("booking_id")
        r = requests.get(base + "/stay_bookings",
                         params={"id": "eq." + str(bid),
                                 "select": "total_amount,currency,status,guest_id"},
                         headers=hdr, timeout=15)
        rows = r.json() if r.ok else []
        if not rows:
            raise ValueError("booking_not_found")
        b = rows[0]
        if b.get("guest_id") != user.get("id"):
            raise ValueError("not_your_booking")
        if b.get("status") != "payment_pending":
            raise ValueError("not_payable")
        return float(b["total_amount"]), b.get("currency") or "EGP", "حجز Homzy Stays"
    if kind == "subscription":
        plan = ref.get("plan"); cycle = ref.get("cycle") or "monthly"
        if plan not in ("pro", "business"):
            raise ValueError("bad_plan")
        r = requests.get(base + "/plan_limits",
                         params={"plan": "eq." + plan, "select": "price_monthly,price_yearly,name_ar"},
                         headers=hdr, timeout=15)
        rows = r.json() if r.ok else []
        if not rows:
            raise ValueError("plan_not_found")
        p = rows[0]
        amt = float(p["price_yearly"] if cycle == "yearly" else p["price_monthly"])
        return amt, "EGP", f"اشتراك Homzy {p.get('name_ar') or plan}"
    if kind == "wallet":
        amt = float(ref.get("amount") or 0)
        if amt < 50 or amt > 100000:
            raise ValueError("bad_amount")
        return amt, "EGP", "شحن محفظة Homzy"
    raise ValueError("bad_kind")


def create_payment(token: str, kind: str, ref: dict) -> dict[str, Any]:
    """Verify the user, compute the amount, create the intent + Paymob intention,
    return the hosted checkout URL."""
    if not enabled():
        return {"ok": False, "error": "payments_not_configured"}
    user = notify.verify_user(token)
    if not user or not user.get("id"):
        return {"ok": False, "error": "not_authenticated"}
    try:
        amount, currency, name = _amount_for(kind, ref, user, token)
    except ValueError as e:
        return {"ok": False, "error": str(e)}
    if amount <= 0:
        return {"ok": False, "error": "zero_amount"}

    prof = notify.get_profile(user["id"], token)
    full = (prof.get("full_name") or "Homzy User").strip()
    parts = full.split(" ", 1)
    first, last = parts[0], (parts[1] if len(parts) > 1 else "-")
    email = (prof.get("email") or user.get("email") or "customer@homzy-ai.com")
    phone = (prof.get("phone") or "+201000000000")

    intent_id = _rpc("pay_create_intent", {"p_key": TOKEN, "p_uid": user["id"],
                                           "p_kind": kind, "p_ref": ref, "p_amount": amount})

    if config.PAYMENT_PROVIDER == "kashier":
        return {"ok": True, "checkout_url": _kashier_checkout(str(intent_id), amount, currency),
                "intent_id": str(intent_id)}

    cents = int(round(amount * 100))
    billing = {"first_name": first, "last_name": last, "email": email,
               "phone_number": phone, "country": "EG", "city": "Cairo",
               "state": "Cairo", "street": "NA", "building": "NA",
               "floor": "NA", "apartment": "NA", "postal_code": "NA"}
    body = {
        "amount": cents, "currency": currency,
        "payment_methods": _integration_ids(),
        "items": [{"name": name[:50], "amount": cents, "description": name, "quantity": 1}],
        "billing_data": billing,
        "customer": {"first_name": first, "last_name": last, "email": email},
        "special_reference": str(intent_id),
        "extras": {"intent_id": str(intent_id)},
        "notification_url": config.API_SITE.rstrip("/") + "/api/pay/webhook",
        "redirection_url": config.PUBLIC_SITE.rstrip("/") + "/pay/return",
    }
    import requests
    try:
        r = requests.post(config.PAYMOB_BASE.rstrip("/") + "/v1/intention/",
                          headers={"Authorization": "Token " + config.PAYMOB_SECRET_KEY,
                                   "Content-Type": "application/json"},
                          json=body, timeout=25)
        data = r.json() if r.content else {}
        if r.status_code >= 300 or not data.get("client_secret"):
            return {"ok": False, "error": "paymob_error", "detail": data or r.text[:300]}
    except Exception as exc:  # pragma: no cover
        return {"ok": False, "error": "paymob_unreachable", "detail": str(exc)}

    try:
        oid = data.get("id") or (data.get("intention_order_id"))
        if oid:
            _rpc("pay_set_order", {"p_key": TOKEN, "p_intent": str(intent_id), "p_order": str(oid)})
    except Exception:
        pass

    url = (config.PAYMOB_BASE.rstrip("/") + "/unifiedcheckout/?publicKey="
           + config.PAYMOB_PUBLIC_KEY + "&clientSecret=" + data["client_secret"])
    return {"ok": True, "checkout_url": url, "intent_id": str(intent_id)}


def _flat(obj: dict, path: str) -> str:
    cur: Any = obj
    for part in path.split("."):
        if isinstance(cur, dict):
            cur = cur.get(part)
        else:
            cur = None
    if isinstance(cur, bool):
        return "true" if cur else "false"
    if cur is None:
        return ""
    return str(cur)


def verify_hmac(obj: dict, received: str) -> bool:
    if not config.PAYMOB_HMAC or not received:
        return False
    concat = "".join(_flat(obj, k) for k in _HMAC_ORDER)
    digest = _hmac.new(config.PAYMOB_HMAC.encode(), concat.encode(), hashlib.sha512).hexdigest()
    return _hmac.compare_digest(digest, received)


def handle_webhook(payload: dict, received_hmac: str) -> dict[str, Any]:
    """Verify the provider signature and settle the matching intent. Idempotent."""
    if config.PAYMENT_PROVIDER == "kashier":
        return handle_kashier_webhook(payload)
    # --- Paymob ---
    obj = payload.get("obj") if isinstance(payload, dict) else None
    if not isinstance(obj, dict):
        obj = payload if isinstance(payload, dict) else {}
    if not verify_hmac(obj, received_hmac):
        return {"ok": False, "error": "bad_hmac"}
    if not obj.get("success"):
        return {"ok": True, "ignored": "not_successful"}
    order = obj.get("order") or {}
    ref = (order.get("merchant_order_id") or obj.get("special_reference")
           or (payload.get("extras") or {}).get("intent_id"))
    if not ref:
        return {"ok": False, "error": "no_reference"}
    try:
        res = _rpc("pay_settle", {"p_key": TOKEN, "p_intent": str(ref),
                                  "p_provider_ref": str(obj.get("id") or "")})
        return {"ok": True, "settle": res}
    except Exception as exc:  # pragma: no cover
        return {"ok": False, "error": "settle_failed", "detail": str(exc)}
