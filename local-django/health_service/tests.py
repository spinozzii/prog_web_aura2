import json
from pathlib import Path

from django.test import SimpleTestCase
from django.urls import reverse

from .canonical import canonicalize_patologia, sha256_patologia


class HealthContractTests(SimpleTestCase):
    def test_health_contract(self):
        response = self.client.get(reverse("health"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "application/json; charset=utf-8")
        self.assertJSONEqual(response.content, {
            "apiVersion": "1.0", "service": "local-django", "status": "ok"
        })


class PatologiaCanonicalContractTests(SimpleTestCase):
    def test_shared_fixture_has_expected_bytes_and_digest(self):
        fixture_path = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "patologia-canonical.json"
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        rows = list(reversed(fixture["rows"]))
        canonical = canonicalize_patologia(rows)
        self.assertEqual(canonical.encode("utf-8"), fixture["expectedCanonical"].encode("utf-8"))
        self.assertEqual(sha256_patologia(rows), fixture["expectedSha256"])
