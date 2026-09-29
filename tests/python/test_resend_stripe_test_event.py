"""Safety tests for the one-event Stripe TEST replay; no external calls.

All provider responses and credentials below are fabricated. These tests only
prove the local replay guard; they do not prove Stripe delivery or frontend
behavior.
"""

from contextlib import ExitStack, redirect_stderr, redirect_stdout
from copy import deepcopy
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError, URLError


SCRIPT = (
    Path(__file__).resolve().parents[2]
    / "scripts/recette-fournisseurs/resend-stripe-test-event.py"
)
SPEC = importlib.util.spec_from_file_location("resend_stripe_test_event", SCRIPT)
replay = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(replay)

ACCOUNT = "acct_1T9pt0EVhQ7cb53W"
PROJECT = "mejpriaetwgtcstbgfid"
ENDPOINT = "we_1UKmSiEVhQ7cb53WAuAljU47"
ENDPOINT_PATH = f"/v1/webhook_endpoints/{ENDPOINT}"
ENDPOINT_URL = f"https://{PROJECT}.supabase.co/functions/v1/stripe-webhook"
FAKE_KEY = "sk_test_FabricatedCredentialForUnitTestsOnly"
PRIVATE_MARKER = "FABRICATED_PRIVATE_PROVIDER_PAYLOAD_DO_NOT_LOG"
NOW = 1_800_000_000
MAX_AGE = 30 * 24 * 60 * 60
EVENTS = {
    "evt_3UKvRlEVhQ7cb53W0Ani5a0O": (
        "charge.pending", "charge", "py_3UKvRlEVhQ7cb53W0inCeFyg"
    ),
    "evt_3UKvRlEVhQ7cb53W0GdDVERo": (
        "transfer.created", "transfer", "tr_3UKvRlEVhQ7cb53W0Fz396PB"
    ),
    "evt_3UKvRlEVhQ7cb53W0fm2OFrt": (
        "transfer.reversed", "transfer", "tr_3UKvRlEVhQ7cb53W0Fz396PB"
    ),
}
DEFAULT_EVENT = next(iter(EVENTS))
FORBIDDEN_REFUND = "evt_3UKvRlEVhQ7cb53W0HppECKN"


def event_fixture(event_id=DEFAULT_EVENT):
    event_type, object_type, object_id = EVENTS[event_id]
    return {
        "object": "event",
        "id": event_id,
        "type": event_type,
        "created": NOW - 60,
        "livemode": False,
        "data": {
            "object": {
                "object": object_type,
                "id": object_id,
                "livemode": False,
                "description": PRIVATE_MARKER,
                "metadata": {"sensitive_test_value": PRIVATE_MARKER},
            }
        },
    }


class FakeStripe:
    """Strict in-memory transport: an unexpected route fails the test."""

    def __init__(self, event_id=DEFAULT_EVENT):
        self.calls = []
        self.fail_at = None
        self.failure = None
        self.responses = {
            "/v1/account": {"id": ACCOUNT, "object": "account", "private_test_value": PRIVATE_MARKER},
            "/v1/balance": {"object": "balance", "livemode": False, "private_test_value": PRIVATE_MARKER},
            ENDPOINT_PATH: {
                "id": ENDPOINT,
                "object": "webhook_endpoint",
                "url": ENDPOINT_URL,
                "status": "enabled",
                "livemode": False,
                "api_version": "2026-02-25.clover",
                "metadata": {"jolene_project": PROJECT, "setup_run": "36488815863"},
                # The existing endpoint has other subscriptions. Their presence
                # does not authorize replaying those other event types.
                "enabled_events": [
                    "charge.pending", "transfer.created", "transfer.reversed",
                    "charge.refunded", "charge.succeeded",
                ],
                "secret": PRIVATE_MARKER,
            },
            f"/v1/events/{event_id}": event_fixture(event_id),
        }
        self.post_response = event_fixture(event_id)

    def __call__(self, method, path, body=None, idempotency_key=None):
        self.calls.append((method, path, deepcopy(body), idempotency_key))
        if self.fail_at == (method, path):
            raise self.failure
        if method == "GET":
            if path not in self.responses or body is not None or idempotency_key is not None:
                raise AssertionError("Unexpected read request")
            return deepcopy(self.responses[path])
        if method == "POST" and path.endswith("/retry"):
            return deepcopy(self.post_response)
        raise AssertionError("Unexpected mutation request")

    @property
    def posts(self):
        return [call for call in self.calls if call[0] == "POST"]


class ReplaySafetyTests(unittest.TestCase):
    def setUp(self):
        # A test must fail before reaching any live provider, even if the core
        # accidentally ignores the injected request implementation.
        self.network_guard = patch(
            "socket.socket", side_effect=AssertionError("Network is forbidden in replay unit tests")
        )
        self.network_guard.start()
        self.addCleanup(self.network_guard.stop)

    def invoke(self, fake, event_id=DEFAULT_EVENT, key=FAKE_KEY):
        stdout, stderr = io.StringIO(), io.StringIO()
        try:
            with redirect_stdout(stdout), redirect_stderr(stderr):
                return replay.run_replay(event_id, key, request=fake, now=lambda: NOW)
        finally:
            output = stdout.getvalue() + stderr.getvalue()
            self.assertNotIn(FAKE_KEY, output)
            self.assertNotIn(PRIVATE_MARKER, output)
            if isinstance(key, str) and key:
                self.assertNotIn(key, output)

    def assert_refused(self, fake, event_id=DEFAULT_EVENT, key=FAKE_KEY, before_get=False):
        with self.assertRaises(replay.ReplayError) as caught:
            self.invoke(fake, event_id=event_id, key=key)
        self.assertRegex(str(caught.exception), r"^[A-Z][A-Z0-9_]*$")
        self.assertNotIn(FAKE_KEY, str(caught.exception))
        self.assertNotIn(PRIVATE_MARKER, str(caught.exception))
        if isinstance(key, str) and key:
            self.assertNotIn(key, str(caught.exception))
        self.assertEqual(fake.posts, [])
        if before_get:
            self.assertEqual(fake.calls, [])

    def test_each_allowed_event_has_exactly_four_reads_and_one_targeted_post(self):
        for event_id, (event_type, _, object_id) in EVENTS.items():
            with self.subTest(event_id=event_id):
                fake = FakeStripe(event_id)
                report = self.invoke(fake, event_id)
                self.assertEqual(
                    [(method, path) for method, path, _, _ in fake.calls],
                    [
                        ("GET", "/v1/account"),
                        ("GET", "/v1/balance"),
                        ("GET", ENDPOINT_PATH),
                        ("GET", f"/v1/events/{event_id}"),
                        ("POST", f"/v1/events/{event_id}/retry"),
                    ],
                )
                self.assertEqual(fake.posts[0][2], {"webhook_endpoint": ENDPOINT})
                idempotency_key = fake.posts[0][3]
                self.assertIsInstance(idempotency_key, str)
                self.assertTrue(idempotency_key)
                self.assertLessEqual(len(idempotency_key), 255)
                self.assertEqual(
                    report,
                    {
                        "status": "RETRY_REQUESTED",
                        "account": ACCOUNT,
                        "project_ref": PROJECT,
                        "endpoint_id": ENDPOINT,
                        "event_id": event_id,
                        "event_type": event_type,
                        "object_id": object_id,
                        "webhook_delivery_confirmed": False,
                        "provider_payments_created": 0,
                        "provider_refunds_created": 0,
                    },
                )
                serialized = json.dumps(report)
                self.assertNotIn(FAKE_KEY, serialized)
                self.assertNotIn(PRIVATE_MARKER, serialized)

    def test_idempotency_key_is_stable_for_the_same_event_and_distinct_between_events(self):
        keys = []
        for event_id in EVENTS:
            first, second = FakeStripe(event_id), FakeStripe(event_id)
            self.invoke(first, event_id)
            self.invoke(second, event_id)
            self.assertEqual(first.posts[0][3], second.posts[0][3])
            self.assertNotIn(FAKE_KEY, first.posts[0][3])
            keys.append(first.posts[0][3])
        self.assertEqual(len(set(keys)), len(EVENTS))

    def test_restricted_test_key_is_accepted(self):
        fake = FakeStripe()
        self.invoke(fake, key="rk_test_FabricatedRestrictedCredential")
        self.assertEqual(len(fake.posts), 1)

    def test_unknown_or_refund_event_is_rejected_before_any_provider_call(self):
        for event_id in (
            None, "", FORBIDDEN_REFUND, "evt_arbitrary", "charge.pending",
            DEFAULT_EVENT + " ", " " + DEFAULT_EVENT,
            DEFAULT_EVENT + "/retry", DEFAULT_EVENT + "?webhook_endpoint=we_other",
        ):
            with self.subTest(event_id=event_id):
                self.assert_refused(FakeStripe(), event_id=event_id, before_get=True)

    def test_invalid_or_live_credential_is_rejected_before_any_provider_call(self):
        for key in (
            None, "", "sk_live_Fabricated", "rk_live_Fabricated", "pk_test_Fabricated",
            "sk_test_", " sk_test_Fabricated", "sk_test_Fabricated ",
            "sk_test_Fabricated\n", "sk_test_Fabricated/nonalphanumeric",
        ):
            with self.subTest(key=key):
                self.assert_refused(FakeStripe(), key=key, before_get=True)

    def test_only_exact_account_is_accepted(self):
        for account in (
            None, [], {}, {"object": "account", "id": None},
            {"object": "account", "id": "acct_other"},
            {"object": "account", "id": ACCOUNT + " "}, {"id": ACCOUNT},
            {"object": "customer", "id": ACCOUNT},
        ):
            with self.subTest(account=account):
                fake = FakeStripe()
                fake.responses["/v1/account"] = account
                self.assert_refused(fake)

    def test_balance_must_explicitly_report_boolean_test_mode(self):
        for balance in (
            None, [], {}, {"object": "balance"}, {"livemode": False},
            {"object": "account", "livemode": False},
            {"object": "balance", "livemode": True},
            {"object": "balance", "livemode": 0},
            {"object": "balance", "livemode": "false"},
        ):
            with self.subTest(balance=balance):
                fake = FakeStripe()
                fake.responses["/v1/balance"] = balance
                self.assert_refused(fake)

    def test_endpoint_identity_configuration_and_test_mode_are_pinned(self):
        changes = [
            ("id", "we_other"), ("object", "event"), ("url", ENDPOINT_URL + "/"),
            ("url", ENDPOINT_URL.replace(PROJECT, "production-project")),
            ("status", "disabled"), ("livemode", True), ("livemode", 0),
            ("api_version", "2025-02-24.acacia"),
            ("metadata", {}), ("metadata", None), ("metadata", []),
            ("metadata", {"jolene_project": "other", "setup_run": "36488815863"}),
            ("metadata", {"jolene_project": PROJECT, "setup_run": "other"}),
            ("metadata", {"jolene_project": PROJECT, "setup_run": 36488815863}),
        ]
        for field, value in changes:
            with self.subTest(field=field, value=value):
                fake = FakeStripe()
                fake.responses[ENDPOINT_PATH][field] = value
                self.assert_refused(fake)
        for field in ("id", "object", "url", "status", "livemode", "api_version", "metadata", "enabled_events"):
            with self.subTest(missing=field):
                fake = FakeStripe()
                del fake.responses[ENDPOINT_PATH][field]
                self.assert_refused(fake)

    def test_endpoint_subscription_must_include_all_three_types_without_wildcard(self):
        required = [values[0] for values in EVENTS.values()]
        invalid_events = [
            None, [], "charge.pending", ["*"], required + ["*"], [None], [{}],
            required + [None], required + [{}], required + [required[0]],
        ]
        invalid_events.extend([event for event in required if event != omitted] for omitted in required)
        for events in invalid_events:
            with self.subTest(events=events):
                fake = FakeStripe()
                fake.responses[ENDPOINT_PATH]["enabled_events"] = events
                self.assert_refused(fake)

    def test_malformed_endpoint_is_rejected(self):
        for endpoint in (None, [], "not an endpoint", False):
            with self.subTest(endpoint=endpoint):
                fake = FakeStripe()
                fake.responses[ENDPOINT_PATH] = endpoint
                self.assert_refused(fake)

    def test_event_identity_type_mode_and_platform_scope_are_pinned(self):
        changes = [
            ("object", "charge"), ("id", "evt_other"), ("id", FORBIDDEN_REFUND),
            ("type", "charge.refunded"), ("type", "transfer.created"),
            ("livemode", True), ("livemode", 0), ("livemode", "false"),
            ("account", "acct_connected"), ("account", ACCOUNT),
            ("account", ""), ("account", False),
        ]
        for field, value in changes:
            with self.subTest(field=field, value=value):
                fake = FakeStripe()
                fake.responses[f"/v1/events/{DEFAULT_EVENT}"][field] = value
                self.assert_refused(fake)
        for field in ("object", "id", "type", "livemode", "created", "data"):
            with self.subTest(missing=field):
                fake = FakeStripe()
                del fake.responses[f"/v1/events/{DEFAULT_EVENT}"][field]
                self.assert_refused(fake)

    def test_null_account_is_accepted_as_a_platform_event(self):
        for event_id in EVENTS:
            with self.subTest(event_id=event_id):
                fake = FakeStripe(event_id)
                fake.responses[f"/v1/events/{event_id}"]["account"] = None
                fake.post_response["account"] = None
                self.invoke(fake, event_id)
                self.assertEqual(len(fake.posts), 1)

    def test_event_age_rejects_future_expired_and_noninteger_dates(self):
        for created in (NOW + 1, NOW - MAX_AGE, NOW - MAX_AGE - 1, None, True, False, str(NOW), NOW - 0.5):
            with self.subTest(created=created):
                fake = FakeStripe()
                fake.responses[f"/v1/events/{DEFAULT_EVENT}"]["created"] = created
                self.assert_refused(fake)

    def test_event_age_accepts_current_second_and_last_second_before_expiry(self):
        for created in (NOW, NOW - MAX_AGE + 1):
            with self.subTest(created=created):
                fake = FakeStripe()
                fake.responses[f"/v1/events/{DEFAULT_EVENT}"]["created"] = created
                self.invoke(fake)
                self.assertEqual(len(fake.posts), 1)

    def test_event_resource_identity_and_object_type_are_pinned_for_each_event(self):
        for event_id, (_, object_type, object_id) in EVENTS.items():
            for resource in (
                None, [], {}, {"id": object_id, "livemode": False},
                {"object": object_type, "livemode": False},
                {"id": "other_resource", "object": object_type, "livemode": False},
                {"id": object_id, "object": "refund", "livemode": False},
                {"id": object_id, "object": object_type},
                {"id": object_id, "object": object_type, "livemode": True},
                {"id": object_id, "object": object_type, "livemode": 0},
            ):
                with self.subTest(event_id=event_id, resource=resource):
                    fake = FakeStripe(event_id)
                    fake.responses[f"/v1/events/{event_id}"]["data"]["object"] = resource
                    self.assert_refused(fake, event_id)

    def test_malformed_event_or_data_cannot_reach_post(self):
        for malformed in (None, [], "not an event", False):
            with self.subTest(event=malformed):
                fake = FakeStripe()
                fake.responses[f"/v1/events/{DEFAULT_EVENT}"] = malformed
                self.assert_refused(fake)
            with self.subTest(data=malformed):
                fake = FakeStripe()
                fake.responses[f"/v1/events/{DEFAULT_EVENT}"]["data"] = malformed
                self.assert_refused(fake)

    def test_provider_or_network_failure_is_opaque_and_never_retried(self):
        calls = [
            ("GET", "/v1/account"), ("GET", "/v1/balance"), ("GET", ENDPOINT_PATH),
            ("GET", f"/v1/events/{DEFAULT_EVENT}"),
            ("POST", f"/v1/events/{DEFAULT_EVENT}/retry"),
        ]
        private_error = f"{FAKE_KEY} {PRIVATE_MARKER}"
        for failure in (
            TimeoutError(private_error), URLError(private_error),
            HTTPError("https://api.stripe.com/", 500, private_error, {}, None),
            ValueError(private_error),
        ):
            for index, call in enumerate(calls):
                with self.subTest(failure=type(failure).__name__, call=call):
                    fake = FakeStripe()
                    fake.fail_at, fake.failure = call, failure
                    with self.assertRaises(replay.ReplayError) as caught:
                        self.invoke(fake)
                    self.assertEqual(str(caught.exception), "REQUEST_FAILED")
                    self.assertEqual([(m, p) for m, p, _, _ in fake.calls], calls[:index + 1])
                    self.assertEqual(len(fake.posts), 1 if call[0] == "POST" else 0)

    def test_post_response_is_validated_without_another_mutation(self):
        invalid_responses = [None, [], {}, "accepted", {"id": DEFAULT_EVENT}]
        for field, value in (
            ("object", "charge"), ("id", "evt_other"), ("type", "charge.refunded"),
            ("livemode", True), ("livemode", 0), ("account", "acct_connected"),
            ("data", None), ("data", {"object": {"id": "other", "object": "charge"}}),
            ("data", {"object": {"id": EVENTS[DEFAULT_EVENT][2], "object": "refund"}}),
        ):
            response = event_fixture()
            response[field] = value
            invalid_responses.append(response)
        for response in invalid_responses:
            with self.subTest(response=response):
                fake = FakeStripe()
                fake.post_response = response
                with self.assertRaises(replay.ReplayError) as caught:
                    self.invoke(fake)
                self.assertRegex(str(caught.exception), r"^[A-Z][A-Z0-9_]*$")
                self.assertNotIn(PRIVATE_MARKER, str(caught.exception))
                self.assertEqual(len(fake.calls), 5)
                self.assertEqual(len(fake.posts), 1)


class FakeHTTPResponse(io.BytesIO):
    def __init__(self, raw=b'{"object":"fixture"}', status=200):
        super().__init__(raw)
        self.status = status


class TransportSafetyTests(unittest.TestCase):
    def setUp(self):
        guard = patch("socket.socket", side_effect=AssertionError("Network is forbidden in tests"))
        guard.start()
        self.addCleanup(guard.stop)

    def transport(self, response=None, error=None):
        opener = Mock()
        opener.open.return_value = response if response is not None else FakeHTTPResponse()
        if error is not None:
            opener.open.side_effect = error
        with patch.object(replay, "build_opener", return_value=opener):
            transport = replay.StripeTransport(FAKE_KEY)
        return transport, opener

    def test_fixed_host_and_form_contain_only_the_selected_endpoint(self):
        transport, opener = self.transport()
        response = transport(
            "POST", f"/v1/events/{DEFAULT_EVENT}/retry",
            body={"webhook_endpoint": ENDPOINT}, idempotency_key="fabricated-stable-key",
        )
        self.assertEqual(response, {"object": "fixture"})
        opener.open.assert_called_once()
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, f"https://api.stripe.com/v1/events/{DEFAULT_EVENT}/retry")
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.data, f"webhook_endpoint={ENDPOINT}".encode("ascii"))
        self.assertEqual(request.get_header("Authorization"), f"Bearer {FAKE_KEY}")
        self.assertEqual(request.get_header("Stripe-version"), "2026-02-25.clover")
        self.assertEqual(request.get_header("Idempotency-key"), "fabricated-stable-key")
        self.assertEqual(opener.open.call_args.kwargs, {"timeout": 20})

    def test_arbitrary_routes_and_mutations_are_refused_before_opening_connection(self):
        retry_path = f"/v1/events/{DEFAULT_EVENT}/retry"
        invalid_requests = [
            ("GET", "https://other.example/v1/account", None, None),
            ("GET", "/v1/account?expand[]=external_accounts", None, None),
            ("GET", f"/v1/events/{FORBIDDEN_REFUND}", None, None),
            ("GET", "/v1/account", {}, None),
            ("GET", "/v1/account", None, "unexpected-idempotency"),
            ("POST", "/v1/refunds", {"charge": "fabricated"}, "fake"),
            ("POST", "/v1/payment_intents", {"amount": 1}, "fake"),
            ("DELETE", ENDPOINT_PATH, None, None),
            ("POST", f"/v1/events/{FORBIDDEN_REFUND}/retry", {"webhook_endpoint": ENDPOINT}, "fake"),
            ("POST", retry_path, {"webhook_endpoint": "we_other"}, "fake"),
            ("POST", retry_path, {"webhook_endpoint": ENDPOINT, "other": "value"}, "fake"),
            ("POST", retry_path, {"webhook_endpoint": ENDPOINT}, None),
            ("POST", retry_path, {"webhook_endpoint": ENDPOINT}, ""),
        ]
        for method, path, body, idempotency_key in invalid_requests:
            with self.subTest(method=method, path=path, body=body, idempotency_key=idempotency_key):
                transport, opener = self.transport()
                with self.assertRaises(replay.ReplayError):
                    transport(method, path, body=body, idempotency_key=idempotency_key)
                opener.open.assert_not_called()

    def test_second_post_is_refused_even_if_first_attempt_failed(self):
        for error in (None, URLError(f"{FAKE_KEY} {PRIVATE_MARKER}")):
            with self.subTest(failed_first_attempt=error is not None):
                transport, opener = self.transport(error=error)
                args = ("POST", f"/v1/events/{DEFAULT_EVENT}/retry")
                kwargs = {"body": {"webhook_endpoint": ENDPOINT}, "idempotency_key": "fake"}
                if error is None:
                    transport(*args, **kwargs)
                else:
                    with self.assertRaises(replay.ReplayError) as caught:
                        transport(*args, **kwargs)
                    self.assertEqual(str(caught.exception), "REQUEST_FAILED")
                with self.assertRaises(replay.ReplayError):
                    transport(*args, **kwargs)
                opener.open.assert_called_once()

    def test_redirect_handler_refuses_every_redirect_status(self):
        handler = replay.NoRedirect()
        for status in (301, 302, 303, 307, 308):
            with self.subTest(status=status):
                with self.assertRaises(replay.ReplayError) as caught:
                    handler.redirect_request(None, None, status, "fixture", {}, "https://other.example")
                self.assertEqual(str(caught.exception), "REDIRECT_REFUSED")

    def test_http_failures_are_opaque_and_not_retried(self):
        message = f"{FAKE_KEY} {PRIVATE_MARKER}"
        errors = [
            URLError(message), TimeoutError(message),
            HTTPError("https://api.stripe.com/", 429, message, {}, None),
            HTTPError("https://api.stripe.com/", 500, message, {}, None),
        ]
        for error in errors:
            with self.subTest(error=type(error).__name__):
                transport, opener = self.transport(error=error)
                with self.assertRaises(replay.ReplayError) as caught:
                    transport("GET", "/v1/account")
                self.assertEqual(str(caught.exception), "REQUEST_FAILED")
                opener.open.assert_called_once()

    def test_non_success_status_or_invalid_response_cannot_be_accepted(self):
        cases = [
            (302, b"{}"), (400, b"{}"), (429, b"{}"), (500, b"{}"),
            (200, PRIVATE_MARKER.encode("ascii")), (200, b'{"value":NaN}'),
            (200, b'{"value":Infinity}'), (200, b"x" * (replay.MAX_RESPONSE + 1)),
        ]
        for status, raw in cases:
            with self.subTest(status=status, size=len(raw)):
                transport, opener = self.transport(FakeHTTPResponse(raw, status))
                with self.assertRaises(replay.ReplayError) as caught:
                    transport("GET", "/v1/account")
                self.assertRegex(str(caught.exception), r"^[A-Z][A-Z0-9_]*$")
                self.assertNotIn(PRIVATE_MARKER, str(caught.exception))
                opener.open.assert_called_once()


class MainSafetyTests(unittest.TestCase):
    def setUp(self):
        guard = patch("socket.socket", side_effect=AssertionError("Network is forbidden in tests"))
        guard.start()
        self.addCleanup(guard.stop)
        self.environment = {
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_REPOSITORY": "Gabpcd/JJJJJ",
            "STRIPE_REPLAY_SQL_PRECHECK": "true",
            "STRIPE_REPLAY_EVENT_ID": DEFAULT_EVENT,
            "STRIPE_API_KEY": FAKE_KEY,
        }

    def invoke_main(self, environment, error=None):
        stdout, stderr = io.StringIO(), io.StringIO()
        with ExitStack() as stack:
            stack.enter_context(patch.dict(replay.os.environ, environment, clear=True))
            save = stack.enter_context(patch.object(replay.Path, "write_text"))
            transport_factory = stack.enter_context(patch.object(replay, "StripeTransport"))
            core = stack.enter_context(patch.object(replay, "run_replay"))
            stack.enter_context(redirect_stdout(stdout))
            stack.enter_context(redirect_stderr(stderr))
            transport_factory.return_value.post_attempts = 0
            if error is not None:
                def ambiguous_post(*args, **kwargs):
                    kwargs["request"].post_attempts = 1
                    raise error
                core.side_effect = ambiguous_post
            exit_code = replay.main()
        save.assert_called_once()
        report = json.loads(save.call_args.args[0])
        output = stdout.getvalue() + stderr.getvalue()
        for rendered in (json.dumps(report), output):
            self.assertNotIn(FAKE_KEY, rendered)
            self.assertNotIn(PRIVATE_MARKER, rendered)
        return exit_code, report, output, transport_factory, core

    def test_nonmanual_nonmain_or_missing_sql_precheck_blocks_before_transport(self):
        cases = [
            ("GITHUB_EVENT_NAME", "push"), ("GITHUB_EVENT_NAME", "pull_request"),
            ("GITHUB_REF", "refs/heads/feature"),
            ("GITHUB_REPOSITORY", "other/repository"),
            ("STRIPE_REPLAY_SQL_PRECHECK", "false"), ("STRIPE_REPLAY_SQL_PRECHECK", None),
        ]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                environment = dict(self.environment)
                if value is None:
                    del environment[key]
                else:
                    environment[key] = value
                code, report, output, transport, core = self.invoke_main(environment)
                self.assertEqual(code, 1)
                self.assertEqual(report["status"], "BLOCKED")
                self.assertIs(report["retry_post_attempted"], False)
                self.assertIs(report["webhook_delivery_confirmed"], False)
                self.assertEqual(output, "BLOCKED\n")
                transport.assert_not_called()
                core.assert_not_called()

    def test_ambiguous_post_report_requires_manual_verification_without_payload(self):
        for error in (
            replay.ReplayError("REQUEST_FAILED"),
            RuntimeError(f"{FAKE_KEY} {PRIVATE_MARKER}"),
        ):
            with self.subTest(error=type(error).__name__):
                code, report, output, transport, core = self.invoke_main(self.environment, error)
                self.assertEqual(code, 1)
                self.assertEqual(report["status"], "RETRY_UNCONFIRMED")
                self.assertIs(report["retry_post_attempted"], True)
                self.assertIs(report["webhook_delivery_confirmed"], False)
                self.assertEqual(output, "RETRY_UNCONFIRMED\n")
                self.assertIn(report["issue"], ("REQUEST_FAILED", "UNEXPECTED_FAILURE"))
                transport.assert_called_once_with(FAKE_KEY)
                core.assert_called_once()


if __name__ == "__main__":
    unittest.main()
