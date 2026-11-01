import io
import time
import unittest
import urllib.request
from unittest import mock

from test_last9 import Base, FakeResp, last9


class TestTransport(Base):
    def setUp(self):
        super().setUp()
        self.login()
        self.ctx = last9.Ctx("default")
        last9.write_private(self.ctx.cache_file, {"access_token": "SYNTHETIC_ACCESS", "expires_at": time.time() + 7200})
        saved = urllib.request._opener
        self.addCleanup(urllib.request.install_opener, saved)

    def test_http_must_not_send_bearer(self):
        with mock.patch("urllib.request.urlopen", return_value=FakeResp(b"{}")) as network:
            code, _, err = self.run_cli(["api", "GET", "http://app.last9.io/api/v4/organizations/acme/change_events"])
        self.assertEqual(code, 1)
        self.assertIn("https", err)
        network.assert_not_called()

    def test_https_positive_control(self):
        with mock.patch("urllib.request.urlopen", return_value=FakeResp(b"{}")) as network:
            code, _, _ = self.run_cli(["api", "GET", "https://app.last9.io/api/v4/organizations/acme/change_events"])
        self.assertEqual(code, 0)
        network.assert_called_once()
        self.assertEqual(network.call_args.args[0].get_header("X-last9-api-token"), "Bearer SYNTHETIC_ACCESS")

    def test_foreign_authorities_rejected(self):
        paths = ["https://foreign.example/x", "https://app.last9.io.foreign.example/x",
                 "https://app.last9.io@foreign.example/x", "http://foreign.example/x"]
        for path in paths:
            with self.subTest(path=path), mock.patch("urllib.request.urlopen") as network:
                code, _, _ = self.run_cli(["api", "GET", path])
                self.assertEqual(code, 1)
                network.assert_not_called()

    def test_redirect_refused(self):
        req = urllib.request.Request("https://app.last9.io/x", headers={"X-LAST9-API-TOKEN": "Bearer SYNTHETIC_ACCESS"})
        for code in [301, 302, 303, 307, 308]:
            with self.subTest(code=code):
                self.assertIsNone(last9.NoRedirect().redirect_request(req, io.BytesIO(), code, "redirect", {}, "https://foreign.example/x"))


if __name__ == "__main__":
    unittest.main()
