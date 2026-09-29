#!/usr/bin/env python3
"""One existing TEST event retry. No credentials or provider payloads in output.

HTTP contract: stripe/stripe-cli v1.52.1, pkg/cmd/resource/events_resend.go.
This stdlib adapter intentionally has no generic write operation or retry loop.
"""
import json
import math
import os
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPRedirectHandler, Request, build_opener

ACCOUNT = "acct_1T9pt0EVhQ7cb53W"
PROJECT = "mejpriaetwgtcstbgfid"
ENDPOINT = "we_1UKmSiEVhQ7cb53WAuAljU47"
ENDPOINT_URL = f"https://{PROJECT}.supabase.co/functions/v1/stripe-webhook"
API_VERSION = "2026-02-25.clover"
SETUP_RUN = "36488815863"
EXCLUDED_EVENT = "evt_3UKvRlEVhQ7cb53W0HppECKN"
EXPECTED_EVENTS = {
    "evt_3UKvRlEVhQ7cb53W0Ani5a0O": ("charge.pending", "py_3UKvRlEVhQ7cb53W0inCeFyg", "charge"),
    "evt_3UKvRlEVhQ7cb53W0GdDVERo": ("transfer.created", "tr_3UKvRlEVhQ7cb53W0Fz396PB", "transfer"),
    "evt_3UKvRlEVhQ7cb53W0fm2OFrt": ("transfer.reversed", "tr_3UKvRlEVhQ7cb53W0Fz396PB", "transfer"),
}
REPORT = "stripe-test-event-replay.json"
MAX_RESPONSE = 1024 * 1024


class ReplayError(Exception):
    """Only fixed internal codes may cross the command boundary."""


def require(condition, code):
    if not condition:
        raise ReplayError(code)


def validate_event(event, event_id, now):
    kind, object_id, object_type = EXPECTED_EVENTS[event_id]
    require(isinstance(event, dict), "EVENT_INVALID")
    require(event.get("id") == event_id and event.get("object") == "event"
            and event.get("type") == kind and event.get("livemode") is False
            and event.get("account") is None, "EVENT_MISMATCH")
    created = event.get("created")
    require(type(created) is int and math.isfinite(now)
            and 0 <= now - created < 30 * 86400, "EVENT_EXPIRED_OR_INVALID")
    data = event.get("data")
    obj = data.get("object") if isinstance(data, dict) else None
    require(isinstance(obj, dict) and obj.get("id") == object_id
            and obj.get("object") == object_type
            and obj.get("livemode") is False, "EVENT_OBJECT_MISMATCH")


def run_replay(event_id, stripe_key, *, request, now=time.time):
    """Validate four GET responses before the sole narrowly scoped POST."""
    require(isinstance(event_id, str) and event_id in EXPECTED_EVENTS
            and event_id != EXCLUDED_EVENT, "EVENT_NOT_ALLOWED")
    require(isinstance(stripe_key, str)
            and re.fullmatch(r"(?:sk|rk)_test_[A-Za-z0-9]+", stripe_key), "TEST_KEY_REQUIRED")

    def call(method, path, **kwargs):
        try:
            result = request(method, path, **kwargs)
        except Exception:
            # Even unknown transport errors can contain Authorization/payloads.
            raise ReplayError("REQUEST_FAILED") from None
        require(isinstance(result, dict), "RESPONSE_INVALID")
        return result

    account = call("GET", "/v1/account")
    require(account.get("id") == ACCOUNT and account.get("object") == "account", "ACCOUNT_MISMATCH")
    balance = call("GET", "/v1/balance")
    require(balance.get("object") == "balance" and balance.get("livemode") is False, "NOT_TEST_MODE")
    endpoint = call("GET", f"/v1/webhook_endpoints/{ENDPOINT}")
    require(endpoint.get("id") == ENDPOINT and endpoint.get("object") == "webhook_endpoint"
            and endpoint.get("url") == ENDPOINT_URL and endpoint.get("status") == "enabled"
            and endpoint.get("livemode") is False and endpoint.get("api_version") == API_VERSION,
            "ENDPOINT_MISMATCH")
    metadata = endpoint.get("metadata")
    require(isinstance(metadata, dict) and metadata.get("jolene_project") == PROJECT
            and metadata.get("setup_run") == SETUP_RUN, "ENDPOINT_METADATA_MISMATCH")
    events = endpoint.get("enabled_events")
    require(isinstance(events, list) and all(isinstance(x, str) for x in events)
            and len(set(events)) == len(events) and "*" not in events
            and {x[0] for x in EXPECTED_EVENTS.values()}.issubset(set(events)), "ENDPOINT_EVENTS_MISMATCH")
    event = call("GET", f"/v1/events/{event_id}")
    validate_event(event, event_id, now())

    # Deterministic per event/endpoint, independent of GitHub run/attempt.
    # A rerun is not permission to produce a second delivery automatically.
    result = call("POST", f"/v1/events/{event_id}/retry",
                  body={"webhook_endpoint": ENDPOINT},
                  idempotency_key=f"jolene-staging-existing-event-retry-v1/{ENDPOINT}/{event_id}")
    validate_event(result, event_id, now())
    kind, object_id, _ = EXPECTED_EVENTS[event_id]
    return {"status": "RETRY_REQUESTED", "account": ACCOUNT, "project_ref": PROJECT,
            "endpoint_id": ENDPOINT, "event_id": event_id, "event_type": kind,
            "object_id": object_id, "webhook_delivery_confirmed": False,
            "provider_payments_created": 0, "provider_refunds_created": 0}


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ReplayError("REDIRECT_REFUSED")


class StripeTransport:
    """Fixed host, fixed routes, redirects refused, at most one POST."""
    def __init__(self, key):
        self.key = key
        self.post_attempts = 0
        self.opener = build_opener(NoRedirect())

    def __call__(self, method, path, body=None, idempotency_key=None):
        read_paths = {"/v1/account", "/v1/balance", f"/v1/webhook_endpoints/{ENDPOINT}",
                      *(f"/v1/events/{event_id}" for event_id in EXPECTED_EVENTS)}
        post_paths = {f"/v1/events/{event_id}/retry" for event_id in EXPECTED_EVENTS}
        if method == "GET":
            require(path in read_paths and body is None and idempotency_key is None, "ROUTE_REFUSED")
        else:
            require(method == "POST" and path in post_paths and self.post_attempts == 0
                    and body == {"webhook_endpoint": ENDPOINT}
                    and isinstance(idempotency_key, str) and bool(idempotency_key), "ROUTE_REFUSED")
            self.post_attempts += 1
        headers = {"Authorization": f"Bearer {self.key}", "Stripe-Version": API_VERSION,
                   "Accept": "application/json"}
        payload = None
        if body is not None:
            headers["Content-Type"] = "application/x-www-form-urlencoded"
            headers["Idempotency-Key"] = idempotency_key
            payload = urlencode(body).encode("ascii")
        req = Request(f"https://api.stripe.com{path}", data=payload, headers=headers, method=method)
        try:
            with self.opener.open(req, timeout=20) as response:
                require(200 <= response.status < 300, "HTTP_FAILURE")
                raw = response.read(MAX_RESPONSE + 1)
                require(len(raw) <= MAX_RESPONSE, "RESPONSE_TOO_LARGE")
                return json.loads(raw, parse_constant=lambda _: require(False, "RESPONSE_INVALID"))
        except (HTTPError, URLError, ValueError, OSError):
            raise ReplayError("REQUEST_FAILED") from None


def main():
    report = {"status": "BLOCKED", "project_ref": PROJECT, "account": ACCOUNT,
              "endpoint_id": ENDPOINT, "webhook_delivery_confirmed": False}
    exit_code = 1
    transport = None
    try:
        require(os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch"
                and os.environ.get("GITHUB_REF") == "refs/heads/main"
                and os.environ.get("GITHUB_REPOSITORY") == "Gabpcd/JJJJJ", "MANUAL_MAIN_ONLY")
        require(os.environ.get("STRIPE_REPLAY_SQL_PRECHECK") == "true", "SQL_PRECHECK_REQUIRED")
        # This is an operator attestation, not a substitute for the read-only DB
        # evidence and postchecks prescribed in the README.
        key = os.environ.get("STRIPE_API_KEY", "")
        event_id = os.environ.get("STRIPE_REPLAY_EVENT_ID", "")
        if event_id in EXPECTED_EVENTS:
            kind, object_id, _ = EXPECTED_EVENTS[event_id]
            report.update(event_id=event_id, event_type=kind, object_id=object_id)
        transport = StripeTransport(key)
        report = run_replay(event_id, key, request=transport)
        exit_code = 0
    except ReplayError as error:
        # Only fixed codes from our implementation; provider exceptions never escape call().
        report["issue"] = str(error)
    except Exception:
        report["issue"] = "UNEXPECTED_FAILURE"
    report["retry_post_attempted"] = bool(transport and transport.post_attempts)
    if exit_code and report["retry_post_attempted"]:
        report["status"] = "RETRY_UNCONFIRMED"
    try:
        Path(REPORT).write_text(json.dumps(report, sort_keys=True) + "\n", encoding="utf-8")
    except OSError:
        print("REPLAY_REPORT_WRITE_FAILED")
        return 1
    print(report["status"])
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
