#!/usr/bin/env python3
"""Deadline regressions; pass --native to also exercise installed telemetrygen."""
import http.server
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import unittest

HELPER = Path(__file__).with_name("last9-emit-telemetry.sh")
NATIVE = "--native" in sys.argv
if NATIVE:
    sys.argv.remove("--native")
    if not shutil.which("telemetrygen"):
        sys.exit("--native requires telemetrygen v0.163.0 on PATH")


class DeadlineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        TMPDIR=str(self.root))
        self.credential = self.root / "credential.env"
        self.credential.write_text("OTLP_ENDPOINT=localhost:4317\n"
                                   "OTLP_HEADERS=Authorization=test-placeholder\n")

    def generator(self, code):
        path = self.bin / "telemetrygen"
        path.write_text(f"#!{sys.executable}\n" + code)
        path.chmod(0o755)

    def run_emit(self, signals, rate="0.1"):
        start = time.monotonic()
        process = subprocess.Popen(
            [str(HELPER), "--org", "example-org", "--environment", "test",
             "--datasource", "test-ds", "--credential-file", str(self.credential),
             "--signals", signals, "--duration", "100ms", "--rate", rate],
            env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=4)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            for path in self.root.glob("last9-emit-*"):
                path.unlink()
            self.fail(f"{signals}, rate {rate}: exceeded 4s outer safety deadline")
        elapsed = time.monotonic() - start
        # 100ms + 1s normal shutdown + 0.5s TERM grace, with scheduling slack.
        self.assertLess(elapsed, 3, "100ms emit plus bounded shutdown allowance")
        self.assertNotIn("test-placeholder", stdout + stderr)
        receipt = json.loads(stdout)
        self.assertEqual(receipt["last9_queryable"], "no")
        self.assertEqual(list(self.root.glob("last9-emit-*")), [])
        return process.returncode, receipt

    def test_terminate_and_reap(self):
        handlers = {
            "default": "",
            "ignore": "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n",
            "exit_zero": "signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))\n",
        }
        for termination, handler in handlers.items():
            with self.subTest(termination=termination):
                pid_file = self.root / "pid"
                self.generator(
                    "import os, signal, sys, time\n"
                    + handler
                    + f"open({str(pid_file)!r}, 'w').write(str(os.getpid()))\n"
                    "time.sleep(30)\n")
                status, receipt = self.run_emit("metrics")
                self.assertNotEqual(status, 0)
                self.assertEqual(receipt["otlp_export"], "client_failed")
                with self.assertRaises(ProcessLookupError):
                    os.kill(int(pid_file.read_text()), 0)

    def test_timeout_remains_failed_after_later_success(self):
        self.generator("import sys, time\n"
                       "if sys.argv[1] == 'metrics': time.sleep(30)\n")
        status, receipt = self.run_emit("metrics,logs")
        self.assertNotEqual(status, 0)
        self.assertEqual(receipt["signal_types"], ["metrics", "logs"])
        self.assertEqual(receipt["otlp_export"], "client_failed")

    @unittest.skipUnless(NATIVE, "pass --native for the installed-binary regression")
    def test_native_low_rates_and_controls(self):
        # HTTP/protobuf uses the same native rate-limited workers as gRPC,
        # while a stdlib loopback receiver avoids a collector dependency.
        requests = []

        class Receiver(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                requests.append((self.path, body))
                self.send_response(200)
                self.send_header("Content-Type", "application/x-protobuf")
                self.send_header("Content-Length", "0")
                self.end_headers()  # Empty protobuf Export*ServiceResponse.

            def log_message(self, *args):
                pass

        receiver = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Receiver)
        thread = threading.Thread(target=receiver.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(receiver.server_close)
        self.addCleanup(thread.join)
        self.addCleanup(receiver.shutdown)
        self.credential.write_text(f"OTLP_ENDPOINT=127.0.0.1:{receiver.server_port}\n"
                                   "OTLP_HEADERS=Authorization=test-placeholder\n")
        native = shutil.which("telemetrygen")
        pid_file = self.root / "native.pid"
        self.generator("import os, sys\n"
                       f"open({str(pid_file)!r}, 'w').write(str(os.getpid()))\n"
                       f"os.execv({native!r}, [{native!r}, sys.argv[1], "
                       "'--otlp-http', *sys.argv[2:]])\n")
        for kind in ("metrics", "logs", "traces"):
            for rate in ("0.1", "100"):
                with self.subTest(signal=kind, rate=rate):
                    requests.clear()
                    status, receipt = self.run_emit(kind, rate)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(int(pid_file.read_text()), 0)
                    if rate == "0.1":
                        self.assertNotEqual(status, 0)
                        self.assertEqual(receipt["otlp_export"], "client_failed")
                    else:
                        self.assertEqual(status, 0)
                        self.assertEqual(receipt["otlp_export"], "client_ok")
                        self.assertTrue(any(path == f"/v1/{kind}" and body
                                            for path, body in requests))


if __name__ == "__main__":
    unittest.main()
