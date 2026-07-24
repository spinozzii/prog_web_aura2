import json
import uuid
from pathlib import Path
from unittest.mock import patch

from django.db import DatabaseError, IntegrityError, transaction
from django.test import SimpleTestCase, TestCase, override_settings
from django.urls import reverse

from .canonical import canonicalize_patologia, sha256_patologia
from .models import MigrationBatch, MigrationRun, Patologia


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
        fixture_path = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / fixture_name
        fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
        rows = list(reversed(fixture["rows"]))
        canonical = canonicalize_patologia(rows)
        self.assertEqual(canonical.encode("utf-8"), fixture["expectedCanonical"].encode("utf-8"))
        self.assertEqual(sha256_patologia(rows), fixture["expectedSha256"])

    def test_shared_fixture_has_expected_bytes_and_digest(self):
        self.assert_fixture("patologia-canonical.json")

    def test_empty_sequence_is_zero_bytes(self):
        self.assert_fixture("patologia-empty.json")

    def test_unicode_line_separators_are_unescaped_utf8(self):
        self.assert_fixture("patologia-line-separators.json")


@override_settings(LOCAL_API_SECRET="local-test-secret")
class MigrationEndpointTests(TestCase):
    migration_id = str(uuid.UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
    auth = {"HTTP_AUTHORIZATION": "Bearer local-test-secret"}
    rows = [
        {"cod": "P001", "nome": "Uno", "criticita": 1},
        {"cod": "P002", "nome": "Dùe", "criticita": 5},
    ]

    def batch(self, sequence, rows, expected_rows=None):
        expected_rows = self.rows if expected_rows is None else expected_rows
        return {
            "apiVersion": "1.0",
            "datasetId": sha256_patologia(expected_rows),
            "entity": "patologia",
            "batchSequence": sequence,
            "rowCount": len(rows),
            "rows": rows,
            "digest": sha256_patologia(rows),
            "expectedRowCount": len(expected_rows),
            "expectedDigest": sha256_patologia(expected_rows),
        }

    def post_batch(self, payload, **headers):
        merged = {**self.auth, **headers}
        return self.client.post(
            reverse("migration-batches", args=[self.migration_id]),
            data=json.dumps(payload, ensure_ascii=False),
            content_type="application/json",
            **merged,
        )

    def finalize(self, expected_batches=2, expected_rows=None):
        expected_rows = self.rows if expected_rows is None else expected_rows
        payload = {
            "apiVersion": "1.0",
            "datasetId": sha256_patologia(expected_rows),
            "entity": "patologia",
            "expectedRowCount": len(expected_rows),
            "expectedBatchCount": expected_batches,
            "expectedDigest": sha256_patologia(expected_rows),
        }
        return self.client.post(
            reverse("migration-finalize", args=[self.migration_id]),
            data=json.dumps(payload),
            content_type="application/json",
            **self.auth,
        )

    def test_success_multipage_finalize_and_status(self):
        self.assertEqual(self.post_batch(self.batch(0, self.rows[:1])).status_code, 201)
        self.assertEqual(self.post_batch(self.batch(1, self.rows[1:])).status_code, 201)
        finalized = self.finalize()
        self.assertEqual(finalized.status_code, 200)
        self.assertEqual(finalized.json()["status"], "completed")
        status = self.client.get(reverse("migration-status", args=[self.migration_id]), **self.auth)
        self.assertEqual(status.json()["rowsImported"], 2)
        self.assertEqual(Patologia.objects.count(), 2)

    def test_duplicate_same_is_idempotent_and_different_conflicts(self):
        payload = self.batch(0, self.rows[:1])
        self.assertEqual(self.post_batch(payload).status_code, 201)
        duplicate = self.post_batch(payload)
        self.assertEqual(duplicate.status_code, 200)
        self.assertTrue(duplicate.json()["idempotent"])
        changed = self.batch(0, [{"cod": "P001", "nome": "Modificata", "criticita": 1}])
        self.assertEqual(self.post_batch(changed).status_code, 409)
        self.assertEqual(MigrationBatch.objects.count(), 1)

    def test_invalid_row_rolls_back_and_bad_digest_is_rejected(self):
        invalid = self.batch(0, [{"cod": "P001", "nome": "Uno", "criticita": 1}])
        invalid["rows"][0]["criticita"] = 6
        self.assertEqual(self.post_batch(invalid).status_code, 400)
        self.assertEqual(Patologia.objects.count(), 0)
        self.assertEqual(MigrationRun.objects.count(), 0)

        wrong_digest = self.batch(0, self.rows[:1])
        wrong_digest["digest"] = "0" * 64
        self.assertEqual(self.post_batch(wrong_digest).status_code, 400)
        self.assertEqual(Patologia.objects.count(), 0)

        wrong_dataset = self.batch(0, self.rows[:1])
        wrong_dataset["datasetId"] = "f" * 64
        response = self.post_batch(wrong_dataset)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "INVALID_CONTRACT")
        self.assertEqual(Patologia.objects.count(), 0)

    def test_finalize_incomplete_and_authentication_errors(self):
        self.assertEqual(self.post_batch(self.batch(0, self.rows[:1])).status_code, 201)
        self.assertEqual(self.finalize().status_code, 409)
        unauthorized = self.client.get(reverse("migration-status", args=[self.migration_id]))
        self.assertEqual(unauthorized.status_code, 401)
        wrong = self.client.get(
            reverse("migration-status", args=[self.migration_id]),
            HTTP_AUTHORIZATION="Bearer wrong",
        )
        self.assertEqual(wrong.status_code, 401)
        with self.settings(LOCAL_API_SECRET=""):
            missing = self.client.get(reverse("migration-status", args=[self.migration_id]))
        self.assertEqual(missing.status_code, 503)
        self.assertEqual(missing.json()["error"]["code"], "SERVICE_NOT_CONFIGURED")

    def test_invalid_json_exact_fields_and_types_are_rejected(self):
        endpoint = reverse("migration-batches", args=[self.migration_id])
        invalid_json = self.client.post(
            endpoint, data="{", content_type="application/json", **self.auth
        )
        self.assertEqual(invalid_json.status_code, 400)
        self.assertEqual(invalid_json.json()["error"]["code"], "INVALID_JSON")

        duplicate_field = self.client.post(
            endpoint,
            data='{"apiVersion":"1.0","apiVersion":"1.0"}',
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(duplicate_field.status_code, 400)
        self.assertEqual(duplicate_field.json()["error"]["code"], "INVALID_JSON")

        missing_field = self.batch(0, self.rows[:1])
        del missing_field["digest"]
        self.assertEqual(self.post_batch(missing_field).status_code, 400)

        wrong_type = self.batch(0, [dict(self.rows[0])])
        wrong_type["rows"][0]["criticita"] = "1"
        self.assertEqual(self.post_batch(wrong_type).status_code, 400)
        self.assertEqual(MigrationRun.objects.count(), 0)

    @patch(
        "health_service.views.DjangoPatologiaRepository.status",
        side_effect=DatabaseError("temporary test failure"),
    )
    def test_database_unavailable_has_uniform_error(self, _status):
        response = self.client.get(
            reverse("migration-status", args=[self.migration_id]), **self.auth
        )
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["error"]["code"], "DATABASE_UNAVAILABLE")

    @override_settings(MAX_MIGRATION_REQUEST_BYTES=128)
    def test_oversized_request_is_rejected_before_parsing(self):
        response = self.client.post(
            reverse("migration-batches", args=[self.migration_id]),
            data="{" + '"padding":"' + ("x" * 256) + '"}',
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(response.status_code, 413)
        self.assertEqual(response.json()["error"]["code"], "REQUEST_TOO_LARGE")
        self.assertEqual(MigrationRun.objects.count(), 0)

    def test_is_last_is_not_part_of_the_batch_contract(self):
        payload = self.batch(0, self.rows[:1])
        payload["isLast"] = True
        response = self.post_batch(payload)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "INVALID_CONTRACT")
        self.assertEqual(MigrationRun.objects.count(), 0)

    def test_order_must_be_strict_inside_and_across_batches(self):
        reversed_rows = list(reversed(self.rows))
        response = self.post_batch(self.batch(0, reversed_rows))
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "INVALID_BATCH_ORDER")
        self.assertEqual(MigrationRun.objects.count(), 0)

        self.assertEqual(self.post_batch(self.batch(0, self.rows[1:])).status_code, 201)
        response = self.post_batch(self.batch(1, self.rows[:1]))
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "BATCH_ORDER_CONFLICT")
        self.assertEqual(MigrationBatch.objects.count(), 1)
        self.assertFalse(Patologia.objects.filter(cod="P001").exists())

    def test_existing_different_row_is_not_overwritten_and_batch_rolls_back(self):
        Patologia.objects.create(cod="P002", nome="Valore locale", criticita=5)
        conflicting_rows = [
            {"cod": "P001", "nome": "Uno", "criticita": 1},
            {"cod": "P002", "nome": "Valore remoto", "criticita": 5},
        ]
        response = self.post_batch(self.batch(0, conflicting_rows))
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "ROW_CONFLICT")
        self.assertFalse(Patologia.objects.filter(cod="P001").exists())
        self.assertEqual(Patologia.objects.get(cod="P002").nome, "Valore locale")
        self.assertEqual(MigrationRun.objects.count(), 0)
        self.assertEqual(MigrationBatch.objects.count(), 0)

    def test_existing_identical_row_is_idempotently_accepted(self):
        Patologia.objects.create(**self.rows[0])
        response = self.post_batch(self.batch(0, self.rows[:1]))
        self.assertEqual(response.status_code, 201)
        self.assertEqual(Patologia.objects.count(), 1)
        self.assertEqual(MigrationBatch.objects.count(), 1)

    def test_empty_dataset_finalizes_without_batches(self):
        response = self.finalize(expected_batches=0, expected_rows=[])
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "completed")
        self.assertEqual(response.json()["rowCount"], 0)
        self.assertEqual(response.json()["batchCount"], 0)
        run = MigrationRun.objects.get(migration_id=self.migration_id)
        self.assertEqual(run.expected_digest, sha256_patologia([]))
        self.assertEqual(run.status, "completed")
        self.assertEqual(MigrationBatch.objects.count(), 0)

        repeated = self.finalize(expected_batches=0, expected_rows=[])
        self.assertEqual(repeated.status_code, 200)
        self.assertEqual(MigrationRun.objects.count(), 1)

    def test_empty_finalize_contract_rejects_inconsistent_counts(self):
        payload = {
            "apiVersion": "1.0",
            "datasetId": sha256_patologia([]),
            "entity": "patologia",
            "expectedRowCount": 0,
            "expectedBatchCount": 1,
            "expectedDigest": sha256_patologia([]),
        }
        response = self.client.post(
            reverse("migration-finalize", args=[self.migration_id]),
            data=json.dumps(payload),
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(MigrationRun.objects.count(), 0)

    def test_database_constraints_reject_invalid_domain_values(self):
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Patologia.objects.create(cod="P000", nome="Non valida", criticita=0)
        with self.assertRaises(IntegrityError):
            with transaction.atomic():
                Patologia.objects.create(cod="", nome="Non valida", criticita=1)
        self.assertEqual(Patologia._meta.db_table, "patologia")
        self.assertEqual(MigrationRun._meta.db_table, "migration_run")
        self.assertEqual(MigrationBatch._meta.db_table, "migration_batch")
