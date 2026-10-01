import base64
import importlib.util
import io
import json
import os
import stat
import sys
import tempfile
import time
import unittest
import urllib.error
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("last9", os.path.join(HERE, "last9.py"))
last9 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(last9)


def jwt(**claims):
    b = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()
    base = {"aud": ["app.last9.io"], "organization_slug": "acme", "scopes": ["read"],
            "exp": 2000000000, "email": "a@b.c"}
    base.update(claims)
    return "%s.%s.sig" % (b({"alg": "none"}), b(base))


class FakeResp(io.BytesIO):
    def __init__(self, body, status=200):
        super().__init__(body if isinstance(body, bytes) else body.encode())
        self.status = status

    def __enter__(self):
        return self

    def __exit__(self, *a):
        pass


def http_error(code, body=b""):
    return urllib.error.HTTPError("u", code, "x", {}, io.BytesIO(body))


def token_resp(tok="ACCESS", ttl=86400):
    return FakeResp(json.dumps({"access_token": tok, "expires_at": int(time.time()) + ttl}))


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.cfg = os.path.join(self.tmp, "cfg")
        patcher = mock.patch.dict(os.environ, {"LAST9_CONFIG_DIR": self.cfg}, clear=False)
        patcher.start()
        self.addCleanup(patcher.stop)
        os.environ.pop("LAST9_REFRESH_TOKEN", None)
        self.refresh = jwt()

    def login(self, token=None, profile="default"):
        last9.write_private(last9.creds_path(), {"profiles": {profile: {"refresh_token": token or self.refresh}}})

    def run_cli(self, argv, stdin=""):
        out, err = io.StringIO(), io.StringIO()
        out.buffer = io.BytesIO()
        stdin = io.StringIO(stdin)
        stdin.buffer = io.BytesIO(stdin.getvalue().encode())
        with mock.patch.object(sys, "stdout", out), mock.patch.object(sys, "stderr", err), \
                mock.patch.object(sys, "stdin", stdin):
            try:
                last9.main(argv)
                code = 0
            except SystemExit as e:
                code = e.code
        return code, out.getvalue() + out.buffer.getvalue().decode(), err.getvalue()


class TestClaims(unittest.TestCase):
    def test_decode(self):
        c = last9.decode_claims(jwt())
        self.assertEqual(c["organization_slug"], "acme")
        self.assertEqual(last9.host_org(c), ("app.last9.io", "acme"))

    def test_aud_strip(self):
        for aud in ("https://app.last9.io", "app.last9.io/api", "https://app.last9.io/api/"):
            self.assertEqual(last9.host_org({"aud": [aud], "organization_slug": "o"})[0], "app.last9.io")

    def test_missing_claim(self):
        with self.assertRaises(SystemExit):
            with mock.patch.object(sys, "stderr", io.StringIO()):
                last9.host_org({"aud": ["h"]})


class TestUrl(Base):
    def ctx(self):
        self.login()
        return last9.Ctx("default")

    def test_relative(self):
        self.assertEqual(last9.resolve_url(self.ctx(), "/change_events", []),
                         "https://app.last9.io/api/v4/organizations/acme/change_events")

    def test_api_path(self):
        self.assertEqual(last9.resolve_url(self.ctx(), "/api/v4/x", []), "https://app.last9.io/api/v4/x")

    def test_full_url_same_host(self):
        u = "https://app.last9.io/api/v4/x"
        self.assertEqual(last9.resolve_url(self.ctx(), u, []), u)

    def test_foreign_host_rejected(self):
        with mock.patch.object(sys, "stderr", io.StringIO()), self.assertRaises(SystemExit):
            last9.resolve_url(self.ctx(), "https://evil.example.com/x", [])

    def test_query_appended(self):
        c = self.ctx()
        self.assertTrue(last9.resolve_url(c, "logs?a=1", ["b=2", "c=x y"]).endswith("logs?a=1&b=2&c=x+y"))
        self.assertTrue(last9.resolve_url(c, "logs", ["b=2"]).endswith("logs?b=2"))


class TestTokens(Base):
    def test_fresh_cache_no_exchange(self):
        self.login()
        ctx = last9.Ctx("default")
        last9.write_private(ctx.cache_file, {"access_token": "CACHED", "expires_at": time.time() + 7200})
        with mock.patch("urllib.request.urlopen") as m:
            self.assertEqual(last9.access_token(ctx), "CACHED")
            m.assert_not_called()

    def test_stale_cache_exchanges(self):
        self.login()
        ctx = last9.Ctx("default")
        last9.write_private(ctx.cache_file, {"access_token": "OLD", "expires_at": time.time() + 600})
        with mock.patch("urllib.request.urlopen", return_value=token_resp("NEW")) as m:
            self.assertEqual(last9.access_token(ctx), "NEW")
            m.assert_called_once()
        self.assertEqual(last9.read_json(ctx.cache_file, {})["access_token"], "NEW")

    def test_env_wins_and_not_written(self):
        self.login(jwt(organization_slug="fromfile"))
        os.environ["LAST9_REFRESH_TOKEN"] = jwt(organization_slug="fromenv")
        ctx = last9.Ctx("default")
        self.assertEqual((ctx.org, ctx.source), ("fromenv", "env"))
        self.assertTrue(ctx.cache_key.startswith("env-"))
        with mock.patch("urllib.request.urlopen", return_value=token_resp()):
            last9.access_token(ctx)
        self.assertNotIn("fromenv", open(last9.creds_path()).read())
        self.assertNotIn(os.environ["LAST9_REFRESH_TOKEN"], open(ctx.cache_file).read())

    def test_not_logged_in(self):
        with mock.patch.object(sys, "stderr", io.StringIO()) as err, self.assertRaises(SystemExit):
            last9.Ctx("default")
        self.assertIn("not logged in", err.getvalue())

    def test_file_modes(self):
        self.login()
        ctx = last9.Ctx("default")
        last9.write_private(ctx.cache_file, {"access_token": "x", "expires_at": 1})
        mode = lambda p: stat.S_IMODE(os.stat(p).st_mode)
        self.assertEqual(mode(self.cfg), 0o700)
        self.assertEqual(mode(os.path.dirname(ctx.cache_file)), 0o700)
        self.assertEqual(mode(last9.creds_path()), 0o600)
        self.assertEqual(mode(ctx.cache_file), 0o600)


class TestApi(Base):
    def test_retry_once_on_401(self):
        self.login()
        # exchange, 401, re-exchange, 200
        seq = [token_resp("A1"), http_error(401, b"{}"), token_resp("A2"), FakeResp(b'{"ok":1}')]
        with mock.patch("urllib.request.urlopen", side_effect=seq) as m:
            code, out, err = self.run_cli(["api", "GET", "x"])
        self.assertEqual((code, out), (0, '{"ok":1}'))
        self.assertEqual(m.call_count, 4)
        self.assertEqual(m.call_args[0][0].get_header("X-last9-api-token"), "Bearer A2")

    def test_no_loop_on_repeated_401(self):
        self.login()
        seq = [token_resp("A1"), http_error(401, b"nope"), token_resp("A2"), http_error(401, b"nope")]
        with mock.patch("urllib.request.urlopen", side_effect=seq) as m:
            code, out, err = self.run_cli(["api", "GET", "x"])
        self.assertEqual(code, 1)
        self.assertEqual(m.call_count, 4)
        self.assertIn("HTTP 401", err)
        self.assertEqual(out, "nope")

    def test_expired_body_triggers_retry(self):
        self.login()
        seq = [token_resp("A1"), http_error(403, b'{"error":"Authorization token is expired"}'),
               token_resp("A2"), FakeResp(b"ok")]
        with mock.patch("urllib.request.urlopen", side_effect=seq):
            self.assertEqual(self.run_cli(["api", "GET", "x"])[0], 0)

    def test_data_sets_content_type_and_no_token_leak(self):
        self.login()
        with mock.patch("urllib.request.urlopen", side_effect=[token_resp("SECRETACCESS"), FakeResp(b"{}")]) as m:
            code, out, err = self.run_cli(["api", "PUT", "change_events", "-d", "-", "-i"], stdin='{"a":1}')
        req = m.call_args[0][0]
        self.assertEqual(req.data, b'{"a":1}')
        self.assertEqual(req.get_header("Content-type"), "application/json")
        self.assertIn("HTTP 200", err)
        self.assertNotIn("SECRETACCESS", out + err)

    def test_foreign_host_never_sent(self):
        self.login()
        with mock.patch("urllib.request.urlopen") as m:
            code, _, err = self.run_cli(["api", "GET", "https://evil.example.com/x"])
        self.assertEqual(code, 1)
        m.assert_not_called()


class TestLogin(Base):
    def test_exchange_failure_saves_nothing(self):
        with mock.patch("urllib.request.urlopen", side_effect=http_error(401)):
            code, out, err = self.run_cli(["login", "--with-token"], stdin=self.refresh + "\n")
        self.assertEqual(code, 1)
        self.assertIn("invalid, expired, or revoked", err)
        self.assertFalse(os.path.exists(self.cfg))

    def test_success_saves_and_hides_token(self):
        with mock.patch("urllib.request.urlopen", return_value=token_resp()):
            code, out, err = self.run_cli(["login", "--with-token"], stdin=self.refresh)
        self.assertEqual(code, 0)
        self.assertIn("org: acme", out)
        self.assertNotIn(self.refresh, out + err)
        self.assertEqual(last9.load_creds()["profiles"]["default"]["refresh_token"], self.refresh)

    def test_status_not_logged_in(self):
        code, _, err = self.run_cli(["status"])
        self.assertEqual(code, 1)
        self.assertIn("not logged in", err)


class TestRegion(Base):
    def url(self, path, q=()):
        return last9.resolve_url(last9.Ctx("default"), path, list(q))

    def saved(self, region):
        last9.write_private(last9.creds_path(),
                            {"profiles": {"default": {"refresh_token": self.refresh, "region": region}}})

    def test_added_for_logs_and_cat(self):
        self.saved("ap-south-1")
        self.assertTrue(self.url("logs/api/v1/labels", ["start=1"]).endswith("labels?start=1&region=ap-south-1"))
        self.assertTrue(self.url("/cat/api/traces/x").endswith("traces/x?region=ap-south-1"))
        self.assertTrue(self.url("/api/v4/organizations/acme/logs/x").endswith("logs/x?region=ap-south-1"))

    def test_not_added_elsewhere(self):
        self.saved("ap-south-1")
        self.assertNotIn("region", self.url("change_events"))
        self.assertNotIn("region", self.url("entities/x"))

    def test_explicit_wins_no_dup(self):
        self.saved("ap-south-1")
        self.assertEqual(self.url("logs/x", ["region=eu-west-1"]).count("region="), 1)
        self.assertEqual(self.url("logs/x?region=eu-west-1").count("region="), 1)

    def test_missing_exits_without_request(self):
        self.login()
        with mock.patch("urllib.request.urlopen") as m:
            code, _, err = self.run_cli(["api", "GET", "logs/api/v1/labels"])
        self.assertEqual(code, 1)
        self.assertIn("region required", err)
        m.assert_not_called()

    def test_env_beats_saved(self):
        self.saved("ap-south-1")
        with mock.patch.dict(os.environ, {"LAST9_REGION": "us-east-1"}):
            self.assertTrue(self.url("logs/x").endswith("region=us-east-1"))

    def test_login_persists_and_preserves(self):
        with mock.patch("urllib.request.urlopen", side_effect=[token_resp(), token_resp()]):
            self.run_cli(["login", "--with-token", "--region", "ap-south-1"], stdin=self.refresh)
            self.assertEqual(last9.load_creds()["profiles"]["default"]["region"], "ap-south-1")
            code, out, _ = self.run_cli(["login", "--with-token"], stdin=self.refresh)
        self.assertEqual(last9.load_creds()["profiles"]["default"]["region"], "ap-south-1")
        self.assertIn("region: ap-south-1", out)


if __name__ == "__main__":
    unittest.main()
