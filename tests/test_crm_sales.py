import asyncio
import json
import unittest
from datetime import datetime, timezone
from unittest.mock import Mock, patch
from uuid import UUID

from fastapi import HTTPException
from pydantic import ValidationError

from backend import crm_routes
from backend import crm_sales as sales
from backend.app import app


class TestClient:
    """Exercise the ASGI app without a network or a second HTTP client dependency."""
    def __init__(self, application):
        self.app = application

    def request(self, method, path, body=None):
        async def call():
            events = []
            async def receive():
                return {"type": "http.request", "body": json.dumps(body).encode() if body is not None else b"", "more_body": False}
            async def send(event):
                events.append(event)
            await self.app({"type": "http", "asgi": {"version": "3.0"}, "http_version": "1.1",
                "method": method, "scheme": "http", "path": path, "raw_path": path.encode(),
                "query_string": b"", "root_path": "", "headers": [(b"content-type", b"application/json")],
                "client": ("127.0.0.1", 123), "server": ("test", 80)}, receive, send)
            return next(e["status"] for e in events if e["type"] == "http.response.start")
        return Mock(status_code=asyncio.run(call()))

    def get(self, path):
        return self.request("GET", path)

    def post(self, path, json):
        return self.request("POST", path, json)


class SalesTests(unittest.TestCase):
    def setUp(self):
        self.provider = patch.object(sales.llm, "get_client", return_value=None)
        self.provider.start()
        self.addCleanup(self.provider.stop)
        self.property = {"id": "one", "status": "active", "currency": "EGP", "purpose": "sale",
                         "area": "New Cairo", "price": 10000000, "bedrooms": 3, "type": "apartment"}

    def test_arabic_requirements_and_distinct_deposit(self):
        data = sales.extract_client_requirements("العميل عايز شقة في مستقبل سيتي أو التجمع، الميزانية لحد 20 مليون وعنده مقدم 9 مليون ويفضل 3 غرف")["requirements"]
        self.assertEqual(data["budget_max"], 20000000)
        self.assertEqual(data["down_payment"], 9000000)
        self.assertEqual(data["bedrooms"], 3)
        self.assertEqual(set(data["locations"]), {"Mostakbal City", "New Cairo"})

    def test_deposit_not_budget(self):
        data = sales.extract_client_requirements("down payment 2 million")["requirements"]
        self.assertNotIn("budget_max", data)
        self.assertEqual(data["down_payment"], 2000000)

    def test_arabic_digits(self):
        self.assertEqual(sales.extract_client_requirements("الميزانية ٢٠ مليون ومقدم ٩ مليون")["requirements"]["budget_max"], 20000000)

    def test_invalid_range_and_infinity_rejected(self):
        for data in ({"budget_min": 30, "budget_max": 20}, {"budget_max": float("inf")}, {"bedrooms": -1}, {"budget_max": True}, {"owner_id": "x"}):
            with self.assertRaises(ValidationError):
                sales.Requirements.model_validate(data)

    def test_perfect_match(self):
        result = sales.find_property_matches({"locations": ["التجمع"], "budget_max": 12000000, "bedrooms": 3, "type": "شقة"}, [self.property])[0]
        self.assertEqual(result["score"], 100)
        self.assertEqual(result["coverage"], 100)

    def test_missing_price_does_not_get_perfect_match(self):
        result = sales.find_property_matches({"locations": ["New Cairo"], "budget_max": 12000000}, [{**self.property, "price": None}])[0]
        self.assertEqual(result["score"], 50)
        self.assertEqual(result["coverage"], 50)
        self.assertEqual(result["evidence"][1]["status"], "unknown")

    def test_wrong_intent_currency_and_inactive_excluded(self):
        for changes in ({"purpose": "rent"}, {"currency": "USD"}, {"status": "sold"}):
            self.assertEqual(sales.find_property_matches({"purpose": "sale"}, [{**self.property, **changes}]), [])

    def test_financing_is_scored_numerically(self):
        result = sales.find_property_matches({"down_payment": 2000000, "installment_years": 8}, [{**self.property, "down_payment_amount": 3000000, "installment_years": 10}])[0]
        self.assertLess(result["score"], 50)
        self.assertEqual(result["evidence"][0]["status"], "mismatch")

    def test_no_requirements_not_perfect(self):
        self.assertEqual(sales.find_property_matches({}, [self.property])[0]["score"], 0)

    def test_outbound_messages_do_not_warm_lead(self):
        now = datetime(2026, 9, 9, tzinfo=timezone.utc)
        activity = [{"kind": "property_sent", "created_at": now.isoformat()}] * 100
        self.assertEqual(sales.calculate_lead_score({}, activity, now)["score"], 0)

    def test_old_and_future_activity_ignored(self):
        now = datetime(2026, 9, 9, tzinfo=timezone.utc)
        activity = [{"kind": "viewed", "created_at": d} for d in ["2020-01-01T00:00:00Z", "2030-01-01T00:00:00Z", "bad"]]
        self.assertEqual(sales.calculate_lead_score({}, activity, now)["score"], 0)

    def test_behavior_capped(self):
        now = datetime(2026, 9, 9, tzinfo=timezone.utc)
        activity = [{"kind": "viewed", "created_at": now.isoformat()}] * 10000
        self.assertEqual(sales.calculate_lead_score({}, activity, now)["score"], 20)

    def test_bad_model_output_falls_back(self):
        with patch.object(sales.llm, "get_client", return_value=Mock(chat=Mock(return_value='{"message": {"unsafe":"shape"}}'))):
            result = sales.generate_sales_message({"name": "Ali"}, {}, "en", "email", "meeting", "professional")
            self.assertEqual(result["engine"], "template")
            self.assertIn("confirm", result["message"])

    def test_timeout_falls_back(self):
        with patch.object(sales.llm, "get_client", side_effect=TimeoutError):
            self.assertEqual(sales.generate_advice({}, {}, [], [], "en")["engine"], "rules")

    def test_schema_accepts_valid_model_draft(self):
        provider = Mock(name="test", chat=Mock(return_value='{"message":"Hello Ali"}'))
        provider.name = "test"
        with patch.object(sales.llm, "get_client", return_value=provider):
            self.assertEqual(sales.generate_sales_message({}, {}, "en", "whatsapp", "initial", "friendly")["message"], "Hello Ali")

    def test_cross_tenant_lead_is_not_found(self):
        gateway = crm_routes.Gateway("jwt")
        gateway.uid = "owner"
        gateway.rows = Mock(return_value=[])
        with self.assertRaises(HTTPException) as err:
            gateway.owned_lead("lead")
        self.assertEqual(err.exception.status_code, 404)
        self.assertEqual(gateway.rows.call_args.kwargs["owner_id"], "eq.owner")

    def test_unauthenticated_endpoints(self):
        client = TestClient(app)
        self.assertEqual(client.get("/api/crm/sales/overview").status_code, 401)
        self.assertEqual(client.get("/api/crm/sales/scores").status_code, 401)
        self.assertEqual(client.post("/api/crm/sales/extract", json={"text": "hello"}).status_code, 401)

    def test_uuid_and_request_limits(self):
        app.dependency_overrides[crm_routes.authenticated] = lambda: Mock()
        self.addCleanup(app.dependency_overrides.clear)
        client = TestClient(app)
        self.assertEqual(client.get("/api/crm/sales/clients/not-a-uuid/copilot").status_code, 422)
        self.assertEqual(client.post("/api/crm/sales/extract", json={"text": "a" * 4001}).status_code, 422)

    def test_public_offer_uses_capability_rpc_and_no_store(self):
        with patch.object(crm_routes.Gateway, "rpc", return_value={"id": "offer", "items": []}) as rpc:
            response = crm_routes.public_offer(UUID("11111111-1111-4111-8111-111111111111"))
            self.assertEqual(response.headers["cache-control"], "no-store")
            self.assertEqual(rpc.call_args.args[0], "crm_read_sales_offer")

    def test_expired_share_is_404(self):
        with patch.object(crm_routes.Gateway, "rpc", return_value=None):
            with self.assertRaises(HTTPException) as error:
                crm_routes.public_offer(UUID("11111111-1111-4111-8111-111111111111"))
            self.assertEqual(error.exception.status_code, 404)

    def test_legacy_endpoint_rejects_missing_token_and_filter_injection(self):
        client = TestClient(app)
        self.assertEqual(client.post("/api/crm/ai/lead", json={"lead_id": "x"}).status_code, 401)
        self.assertEqual(client.post("/api/crm/ai/lead", json={"token": "test", "lead_id": "x&select=*"}).status_code, 422)

    def test_category_mismatch_is_explained(self):
        result = sales.find_property_matches({"category": "commercial"}, [self.property])[0]
        self.assertEqual(result["score"], 0)
        self.assertEqual(result["evidence"][0]["status"], "mismatch")

    def test_extreme_extracted_amount_is_not_saved(self):
        result = sales.extract_client_requirements("budget 999999999 million")
        self.assertNotIn("budget_max", result["requirements"])

    def test_removed_favorites_do_not_keep_favorite_points(self):
        now = datetime(2026, 9, 9, tzinfo=timezone.utc)
        events = [{"kind": "favorite_removed", "listing_id": "one", "created_at": "2026-09-08T12:00:00Z"},
                  {"kind": "saved", "listing_id": "one", "created_at": "2026-09-07T12:00:00Z"}]
        result = sales.calculate_lead_score({}, events, now)
        self.assertEqual(result["score"], 0)

    def test_performance_does_not_infer_skipped_stages(self):
        leads = [{"id": "lead", "stage": "closed", "created_at": "2026-09-01T00:00:00Z"}]
        deals = [{"lead_id": "lead", "status": "won", "value": 2000000, "actual_close": "2026-09-09"}]
        result = sales.calculate_performance(leads, deals, [], [], [])
        self.assertEqual(result["funnel"]["closed"], 1)
        self.assertEqual(result["funnel"]["offers"], 0)
        self.assertIsNone(result["first_recorded_contact_hours"])
        self.assertEqual(result["average_sales_cycle_days"], 8)

    def test_performance_first_contact_and_empty_denominators(self):
        leads = [{"id": "lead", "stage": "new", "created_at": "2026-09-01T00:00:00Z"}]
        activities = [{"lead_id": "lead", "kind": "call", "created_at": "2026-09-01T02:00:00Z"}]
        result = sales.calculate_performance(leads, [], [], activities, [])
        self.assertEqual(result["first_recorded_contact_hours"], 2)
        self.assertIsNone(result["offer_conversion"])

    def test_postgrest_requests_are_paged_below_default_cap(self):
        gateway = crm_routes.Gateway("fixture")
        gateway.request = Mock(side_effect=[[{"id": i} for i in range(500)], [{"id": 500}]])
        rows = gateway.rows("clients", limit=10000, order="id")
        self.assertEqual(len(rows), 501)
        self.assertEqual(gateway.request.call_args.kwargs["params"]["offset"], 500)
        self.assertEqual(gateway.request.call_args.kwargs["params"]["limit"], 500)

    def test_followup_requires_timezone_and_valid_reminder(self):
        with self.assertRaises(ValidationError):
            crm_routes.Followup(kind="call", title="Call", due_at="2026-09-09T12:00:00", local_day="2026-09-09")
        with self.assertRaises(ValidationError):
            crm_routes.Followup(kind="call", title="Call", due_at="2026-09-09T12:00:00Z", local_day="2026-09-09", reminder_minutes=-1)

    def test_activity_scores_filter_by_client_owner_not_activity_actor(self):
        gateway = Mock(uid="11111111-1111-4111-8111-111111111111")
        gateway.rows.return_value = []
        crm_routes.scores(gateway)
        activity_call = next(c for c in gateway.rows.call_args_list if c.args[0] == "crm_lead_activities")
        self.assertNotIn("owner_id", activity_call.kwargs)
        self.assertEqual(activity_call.kwargs["clients.owner_id"], "eq." + gateway.uid)
        self.assertIn("clients!inner(owner_id)", activity_call.kwargs["select"])


if __name__ == "__main__":
    unittest.main()
