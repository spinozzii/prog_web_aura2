import json
import uuid
from pathlib import Path
from unittest.mock import patch

from django.db import DatabaseError, IntegrityError, transaction
from django.test import SimpleTestCase, TestCase, override_settings
from django.urls import reverse

from .canonical import canonicalize_patologia, sha256_patologia
from .models import EntityMigrationBatch, MigrationExecution, Patologia


class HealthContractTests(SimpleTestCase):
    def test_health_contract(self):
        response = self.client.get(reverse("health"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response["Content-Type"], "application/json; charset=utf-8")
        self.assertJSONEqual(response.content, {
            "apiVersion": "1.0", "service": "local-django", "status": "ok"
        })


class PatologiaCanonicalContractTests(SimpleTestCase):
    def assert_fixture(self, fixture_name):
        fixture_path = (
            Path(__file__).resolve().parents[2] / "tests" / "fixtures" / fixture_name
        )
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        rows = list(reversed(fixture["rows"]))
        canonical = canonicalize_patologia(rows)
        self.assertEqual(
            canonical.encode("utf-8"),
            fixture["expectedCanonical"].encode("utf-8"),
        )
        self.assertEqual(sha256_patologia(rows), fixture["expectedSha256"])

    def test_shared_fixture_has_expected_bytes_and_digest(self):
        self.assert_fixture("patologia-canonical.json")

    def test_empty_sequence_is_zero_bytes(self):
        self.assert_fixture("patologia-empty.json")

    def test_unicode_line_separators_are_unescaped_utf8(self):
        self.assert_fixture("patologia-line-separators.json")


@override_settings(LOCAL_API_SECRET="local-test-secret")
class MigrationEndpointSecurityTests(TestCase):
    migration_id = str(uuid.UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
    auth = {"HTTP_AUTHORIZATION": "Bearer local-test-secret"}
    rows = [{"cod": "P001", "nome": "Patologia di prova", "criticita": 1}]

    def endpoint(self):
        return reverse("migration-batches", args=[self.migration_id])

    def legacy_batch(self):
        digest = sha256_patologia(self.rows)
        return {
            "apiVersion": "1.0",
            "datasetId": digest,
            "entity": "patologia",
            "batchSequence": 0,
            "rowCount": 1,
            "rows": self.rows,
            "digest": digest,
            "expectedRowCount": 1,
            "expectedDigest": digest,
        }

    def post(self, payload, **headers):
        return self.client.post(
            self.endpoint(),
            data=json.dumps(payload, ensure_ascii=False),
            content_type="application/json",
            **{**self.auth, **headers},
        )

    def test_legacy_batch_without_checkpoint_is_rejected(self):
        response = self.post(self.legacy_batch())
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "INVALID_CONTRACT")
        self.assertEqual(MigrationExecution.objects.count(), 0)

    def test_checkpoint_batch_requires_manifest_initialization(self):
        payload = {
            **self.legacy_batch(),
            "sourceCursor": None,
            "nextCursor": None,
            "hasMore": False,
        }
        response = self.post(payload)
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"]["code"], "MIGRATION_NOT_FOUND")
        self.assertEqual(EntityMigrationBatch.objects.count(), 0)

    def test_authentication_and_missing_configuration_fail_closed(self):
        status_url = reverse("migration-status", args=[self.migration_id])
        response = self.client.get(status_url)
        self.assertEqual(response.status_code, 401)
        response = self.client.get(
            status_url,
            HTTP_AUTHORIZATION="Bearer wrong",
        )
        self.assertEqual(response.status_code, 401)
        with self.settings(LOCAL_API_SECRET=""):
            response = self.client.get(status_url, **self.auth)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["error"]["code"], "SERVICE_NOT_CONFIGURED")

    def test_invalid_duplicate_and_oversized_json_are_rejected(self):
        invalid = self.client.post(
            self.endpoint(),
            data="{",
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(invalid.status_code, 400)
        duplicate = self.client.post(
            self.endpoint(),
            data='{"apiVersion":"1.0","apiVersion":"1.0"}',
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(duplicate.status_code, 400)
        with self.settings(MAX_MIGRATION_REQUEST_BYTES=128):
            oversized = self.client.post(
                self.endpoint(),
                data="{" + '"padding":"' + ("x" * 256) + '"}',
                content_type="application/json",
                **self.auth,
            )
        self.assertEqual(oversized.status_code, 413)

    @patch(
        "health_service.views.DjangoEntityRepository.status",
        side_effect=DatabaseError("temporary test failure"),
    )
    def test_database_unavailable_has_uniform_error(self, _status):
        response = self.client.get(
            reverse("migration-status", args=[self.migration_id]),
            **self.auth,
        )
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["error"]["code"], "DATABASE_UNAVAILABLE")

    def test_database_constraints_reject_invalid_domain_values(self):
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Patologia.objects.create(
                    cod="P000",
                    nome="Non valida",
                    criticita=0,
                )
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Patologia.objects.create(
                    cod="",
                    nome="Non valida",
                    criticita=1,
                )
        self.assertEqual(Patologia._meta.db_table, "patologia")
