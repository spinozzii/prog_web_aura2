"""Contract tests for the stdlib-only offline remote fixture server."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "delivery" / "installer" / "mock_remote.py"
SPEC = importlib.util.spec_from_file_location("drive_aura_mock_remote", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
mock_remote = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = mock_remote
SPEC.loader.exec_module(mock_remote)


class MockRemoteContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.secret = "offline-test-secret"
        cls.server = mock_remote.create_server(
            port=0,
            api_secret=cls.secret,
            cursor_secret="offline-test-cursor-secret",
            fixture_path=ROOT / "tests" / "fixtures" / "t03-dataset.json",
            schema_path=ROOT / "shared" / "entity-schema.json",
        )
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        host, port = cls.server.server_address
        cls.base_url = f"http://{host}:{port}"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def request(
        self, path: str, *, authorized: bool = False
    ) -> tuple[int, dict[str, object]]:
        headers = {"Authorization": f"Bearer {self.secret}"} if authorized else {}
        request = Request(self.base_url + path, headers=headers)
        try:
            with urlopen(request, timeout=2) as response:
                return response.status, json.loads(response.read())
        except HTTPError as error:
            return error.code, json.loads(error.read())

    def test_health_uses_remote_php_contract_without_authentication(self) -> None:
        status, body = self.request("/health")
        self.assertEqual(200, status)
        self.assertEqual(
            {"apiVersion": "1.0", "service": "remote-php", "status": "ok"},
            body,
        )

    def test_manifest_requires_exact_bearer_secret(self) -> None:
        status, body = self.request("/api/v1/manifest")
        self.assertEqual(401, status)
        self.assertEqual("UNAUTHORIZED", body["error"]["code"])

        status, body = self.request("/api/v1/manifest", authorized=True)
        self.assertEqual(200, status)
        self.assertEqual(self.server.dataset.dataset_id, body["datasetId"])
        self.assertEqual(list(self.server.dataset.entity_order), body["entityOrder"])
        self.assertEqual(100, body["maxBatchSize"])

    def test_all_rows_are_returned_in_deterministic_multipage_order(self) -> None:
        dataset_id = self.server.dataset.dataset_id
        cursor = None
        collected: list[dict[str, object]] = []
        page_count = 0
        while True:
            path = (
                f"/api/v1/export/patologia?datasetId={dataset_id}&limit=1"
                + (f"&cursor={cursor}" if cursor is not None else "")
            )
            status, body = self.request(path, authorized=True)
            self.assertEqual(200, status)
            self.assertEqual(cursor, body["cursor"])
            self.assertEqual(1, body["rowCount"])
            page_rows = body["rows"]
            canonical = (
                json.dumps(
                    page_rows[0],
                    ensure_ascii=False,
                    separators=(",", ":"),
                ).encode("utf-8")
                + b"\n"
            )
            self.assertEqual(hashlib.sha256(canonical).hexdigest(), body["digest"])
            collected.extend(page_rows)
            page_count += 1
            cursor = body["nextCursor"]
            self.assertEqual(cursor is not None, body["hasMore"])
            if cursor is None:
                break

        self.assertGreater(page_count, 1)
        self.assertEqual(
            list(self.server.dataset.entities["patologia"].rows), collected
        )

    def test_tampered_cursor_is_rejected(self) -> None:
        dataset_id = self.server.dataset.dataset_id
        status, first = self.request(
            f"/api/v1/export/patologia?datasetId={dataset_id}&limit=1",
            authorized=True,
        )
        self.assertEqual(200, status)
        cursor = first["nextCursor"]
        replacement = "A" if cursor[-1] != "A" else "B"
        status, body = self.request(
            f"/api/v1/export/patologia?datasetId={dataset_id}"
            f"&limit=1&cursor={cursor[:-1]}{replacement}",
            authorized=True,
        )
        self.assertEqual(400, status)
        self.assertEqual("INVALID_CURSOR", body["error"]["code"])

    def test_authenticated_resume_accepts_an_expired_signed_checkpoint(self) -> None:
        now = [1000.0]
        codec = mock_remote.CursorCodec(
            "offline-expiry-test-secret",
            ttl_seconds=10,
            clock=lambda: now[0],
        )
        cursor = codec.encode(
            self.server.dataset.dataset_id,
            "patologia",
            1,
        )
        now[0] = 1011.0
        with self.assertRaises(mock_remote.ApiError):
            codec.decode(cursor)
        self.assertEqual(
            (self.server.dataset.dataset_id, "patologia", 1),
            codec.decode(cursor, allow_expired=True),
        )


if __name__ == "__main__":
    unittest.main()
