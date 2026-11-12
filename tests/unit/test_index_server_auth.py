# Unit tests for the index server token auth dependency and health endpoint.
import unittest
import tempfile
from pathlib import Path

from fastapi import FastAPI
from fastapi.testclient import TestClient

from dt_image_search.index_server.app import create_app

TOKEN = "test-token-123"


def _client(token=TOKEN, static_dir=None):
    app = create_app(ctx=None, token=token, static_dir=static_dir)
    return TestClient(app)


class TestTokenAuth(unittest.TestCase):
    def test_health_needs_no_token(self):
        client = _client()
        resp = client.get("/health")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"status": "ok"})

    def test_protected_route_without_token_is_401(self):
        client = _client()
        self.assertEqual(client.get("/ping").status_code, 401)

    def test_protected_route_with_wrong_token_is_401(self):
        client = _client()
        self.assertEqual(client.get("/ping", headers={"X-Auth-Token": "nope"}).status_code, 401)

    def test_protected_route_accepts_header_token(self):
        client = _client()
        resp = client.get("/ping", headers={"X-Auth-Token": TOKEN})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"ok": True})

    def test_protected_route_accepts_query_token(self):
        client = _client()
        resp = client.get("/ping", params={"auth": TOKEN})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"ok": True})

    def test_generated_documentation_is_not_exposed(self):
        client = _client()
        for path in ("/docs", "/redoc", "/openapi.json"):
            with self.subTest(path=path):
                self.assertEqual(client.get(path).status_code, 404)

    def test_spa_entry_accepts_header_token(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "index.html").write_text("<html>AuSearch</html>")
            client = _client(static_dir=directory)
            for path in ("/", "/index.html", "/settings"):
                with self.subTest(path=path):
                    self.assertEqual(client.get(path).status_code, 401)
                    response = client.get(path, headers={"X-Auth-Token": TOKEN})
                    self.assertEqual(response.status_code, 200)
                    self.assertIn("AuSearch", response.text)


if __name__ == '__main__':
    unittest.main()
