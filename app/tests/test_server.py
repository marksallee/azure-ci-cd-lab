import json
import os
import sys
import threading
import unittest
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import server  # noqa: E402


class ServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        os.environ["APP_ENV"] = "test"
        os.environ["APP_VERSION"] = "abc123"
        os.environ["APP_PLATFORM"] = "unit-test"
        cls.httpd = server.make_server(0)  # port 0 = pick a free port
        cls.port = cls.httpd.server_address[1]
        cls.thread = threading.Thread(target=cls.httpd.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.httpd.shutdown()
        cls.httpd.server_close()

    def get(self, path):
        return urllib.request.urlopen(f"http://127.0.0.1:{self.port}{path}", timeout=5)

    def test_healthz(self):
        with self.get("/healthz") as r:
            self.assertEqual(r.status, 200)
            self.assertEqual(json.load(r), {"status": "ok"})

    def test_version_reports_build_and_environment(self):
        with self.get("/version") as r:
            data = json.load(r)
        self.assertEqual(data["version"], "abc123")
        self.assertEqual(data["environment"], "test")
        self.assertEqual(data["platform"], "unit-test")

    def test_unknown_path_is_404(self):
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            self.get("/nope")
        self.assertEqual(ctx.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
