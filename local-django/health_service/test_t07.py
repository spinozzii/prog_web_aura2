import json
import uuid

from django.test import TestCase, override_settings
from django.urls import reverse

from .canonical import sha256_dataset, sha256_entity
from .entity_schema import ENTITY_ORDER
from .models import (
    Cittadino,
    EntityMigrationBatch,
    EntityMigrationRun,
    MigrationExecution,
)


@override_settings(LOCAL_API_SECRET="local-test-secret")
class ResilientMigrationTests(TestCase):
    migration_id = str(uuid.UUID("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"))
    auth = {"HTTP_AUTHORIZATION": "Bearer local-test-secret"}
    citizens = [
        {
            "cssn": "CSSN-001",
            "nome": "Anna",
            "cognome": "Rossi",
            "data_nascita": "1980-02-29",
            "luogo_nascita": "Bergamo",
            "indirizzo": "Via Roma 1",
        },
        {
            "cssn": "CSSN-002",
            "nome": "Luca",
            "cognome": "Verdi",
            "data_nascita": "1990-01-01",
            "luogo_nascita": "Milano",
            "indirizzo": "Via Milano 2",
        },
    ]

    def manifest(self, citizens=None):
        citizens = self.citizens if citizens is None else citizens
        rows = {entity: [] for entity in ENTITY_ORDER}
        rows["cittadino"] = citizens
        descriptors = {
            entity: {
                "rowCount": len(rows[entity]),
                "digest": sha256_entity(entity, rows[entity]),
            }
            for entity in ENTITY_ORDER
        }
        return {
            "apiVersion": "1.0",
            "datasetId": sha256_dataset(descriptors),
            "entityOrder": list(ENTITY_ORDER),
            "entities": [
                {
                    "entity": entity,
                    "rowCount": descriptors[entity]["rowCount"],
                    "digest": descriptors[entity]["digest"],
                }
                for entity in ENTITY_ORDER
            ],
        }

    def initialize(self, manifest=None):
        return self.client.post(
            reverse("migration-status", args=[self.migration_id]),
            data=json.dumps(manifest or self.manifest(), ensure_ascii=False),
            content_type="application/json",
            **self.auth,
        )

    def batch(self, sequence, rows, source_cursor, next_cursor, has_more, all_rows=None):
        all_rows = self.citizens if all_rows is None else all_rows
        manifest = self.manifest(all_rows)
        return {
            "apiVersion": "1.0",
            "datasetId": manifest["datasetId"],
            "entity": "cittadino",
            "batchSequence": sequence,
            "rowCount": len(rows),
            "rows": rows,
            "digest": sha256_entity("cittadino", rows),
            "expectedRowCount": len(all_rows),
            "expectedDigest": sha256_entity("cittadino", all_rows),
            "sourceCursor": source_cursor,
            "nextCursor": next_cursor,
            "hasMore": has_more,
        }

    def post_batch(self, payload):
        return self.client.post(
            reverse("migration-batches", args=[self.migration_id]),
            data=json.dumps(payload, ensure_ascii=False),
            content_type="application/json",
            **self.auth,
        )

    def finalize_cittadino(self, rows=None, batches=2):
        rows = self.citizens if rows is None else rows
        manifest = self.manifest(rows)
        return self.client.post(
            reverse("migration-finalize", args=[self.migration_id]),
            data=json.dumps({
                "apiVersion": "1.0",
                "datasetId": manifest["datasetId"],
                "entity": "cittadino",
                "expectedRowCount": len(rows),
                "expectedBatchCount": batches if rows else 0,
                "expectedDigest": sha256_entity("cittadino", rows),
            }),
            content_type="application/json",
            **self.auth,
        )

    def record_failure(self, code, recoverable):
        manifest = self.manifest()
        return self.client.post(
            reverse("migration-failure", args=[self.migration_id]),
            data=json.dumps({
                "apiVersion": "1.0",
                "datasetId": manifest["datasetId"],
                "entity": "cittadino",
                "errorCode": code,
                "recoverable": recoverable,
            }),
            content_type="application/json",
            **self.auth,
        )

    def test_manifest_is_pinned_and_repeated_initialization_is_idempotent(self):
        created = self.initialize()
        self.assertEqual(created.status_code, 201, created.content)
        self.assertFalse(created.json()["idempotent"])
        self.assertEqual(MigrationExecution.objects.count(), 1)
        self.assertEqual(EntityMigrationRun.objects.count(), len(ENTITY_ORDER))

        repeated = self.initialize()
        self.assertEqual(repeated.status_code, 200)
        self.assertTrue(repeated.json()["idempotent"])

        changed = self.initialize(self.manifest(self.citizens[:1]))
        self.assertEqual(changed.status_code, 409)
        self.assertEqual(changed.json()["error"]["code"], "DATASET_CHANGED")
        self.assertEqual(MigrationExecution.objects.count(), 1)

    def test_checkpoint_is_atomic_and_resume_uses_persisted_next_cursor(self):
        self.assertEqual(self.initialize().status_code, 201)
        first = self.batch(0, self.citizens[:1], None, "page1.signature", True)
        response = self.post_batch(first)
        self.assertEqual(response.status_code, 201, response.content)
        self.assertEqual(response.json()["nextCursor"], "page1.signature")

        status = self.client.get(
            reverse("migration-status", args=[self.migration_id]), **self.auth
        )
        self.assertEqual(status.status_code, 200)
        checkpoint = status.json()["entities"][0]
        self.assertEqual(checkpoint["nextBatchSequence"], 1)
        self.assertEqual(checkpoint["nextCursor"], "page1.signature")
        self.assertTrue(checkpoint["hasMore"])

        second = self.batch(
            1, self.citizens[1:], "page1.signature", None, False
        )
        self.assertEqual(self.post_batch(second).status_code, 201)
        finalized = self.finalize_cittadino()
        self.assertEqual(finalized.status_code, 200, finalized.content)
        execution = MigrationExecution.objects.get(migration_id=self.migration_id)
        self.assertEqual(execution.current_entity, "patologia")
        self.assertEqual(execution.status, "running")

        duplicate = self.post_batch(second)
        self.assertEqual(duplicate.status_code, 200)
        self.assertTrue(duplicate.json()["idempotent"])
        self.assertIsNone(duplicate.json()["nextCursor"])
        self.assertEqual(Cittadino.objects.count(), 2)
        self.assertEqual(EntityMigrationBatch.objects.count(), 2)

    def test_duplicate_data_returns_the_authoritative_saved_cursor(self):
        self.assertEqual(self.initialize().status_code, 201)
        first = self.batch(0, self.citizens[:1], None, "saved.signature", True)
        self.assertEqual(self.post_batch(first).status_code, 201)
        repeated = dict(first, nextCursor="renewed.signature")
        duplicate = self.post_batch(repeated)
        self.assertEqual(duplicate.status_code, 200)
        self.assertEqual(duplicate.json()["nextCursor"], "saved.signature")
        self.assertEqual(EntityMigrationBatch.objects.count(), 1)

    def test_wrong_resume_cursor_and_row_conflict_do_not_advance_checkpoint(self):
        self.assertEqual(self.initialize().status_code, 201)
        first = self.batch(0, self.citizens[:1], None, "page1.signature", True)
        self.assertEqual(self.post_batch(first).status_code, 201)
        wrong = self.batch(1, self.citizens[1:], "wrong.signature", None, False)
        rejected = self.post_batch(wrong)
        self.assertEqual(rejected.status_code, 409)
        self.assertEqual(rejected.json()["error"]["code"], "CHECKPOINT_CONFLICT")
        run = EntityMigrationRun.objects.get(
            migration_id=self.migration_id, entity="cittadino"
        )
        self.assertEqual(run.next_sequence, 1)
        self.assertEqual(run.next_cursor, "page1.signature")

        self.migration_id = str(uuid.UUID("ffffffff-ffff-4fff-8fff-ffffffffffff"))
        one = self.citizens[:1]
        self.assertEqual(self.initialize(self.manifest(one)).status_code, 201)
        Cittadino.objects.filter(cssn=one[0]["cssn"]).update(nome="Valore locale")
        conflict = self.post_batch(self.batch(0, one, None, None, False, one))
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(conflict.json()["error"]["code"], "ROW_CONFLICT")
        run = EntityMigrationRun.objects.get(
            migration_id=self.migration_id, entity="cittadino"
        )
        self.assertEqual(run.next_sequence, 0)
        self.assertIsNone(run.next_cursor)
        self.assertEqual(EntityMigrationBatch.objects.count(), 1)

    def test_terminal_page_is_required_before_finalize(self):
        one = self.citizens[:1]
        self.assertEqual(self.initialize(self.manifest(one)).status_code, 201)
        open_page = self.batch(0, one, None, "more.signature", True, one)
        self.assertEqual(self.post_batch(open_page).status_code, 201)
        response = self.finalize_cittadino(one, batches=1)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "SOURCE_NOT_EXHAUSTED")

    def test_recoverable_failure_can_resume_but_terminal_failure_cannot(self):
        self.assertEqual(self.initialize().status_code, 201)
        interrupted = self.record_failure("REMOTE_TIMEOUT", True)
        self.assertEqual(interrupted.status_code, 200)
        self.assertEqual(interrupted.json()["status"], "interrupted")
        status = self.client.get(
            reverse("migration-status", args=[self.migration_id]), **self.auth
        ).json()
        self.assertTrue(status["recoverable"])
        self.assertEqual(status["lastError"], "REMOTE_TIMEOUT")

        first = self.batch(0, self.citizens[:1], None, "page1.signature", True)
        self.assertEqual(self.post_batch(first).status_code, 201)
        execution = MigrationExecution.objects.get(migration_id=self.migration_id)
        self.assertEqual(execution.status, "running")
        self.assertEqual(execution.last_error, "")

        terminal = self.record_failure("DIGEST_MISMATCH", False)
        self.assertEqual(terminal.status_code, 200)
        self.assertEqual(terminal.json()["status"], "failed")
        late_recoverable = self.record_failure("LOCAL_TIMEOUT", True)
        self.assertEqual(late_recoverable.status_code, 409)
        self.assertEqual(
            late_recoverable.json()["error"]["code"], "MIGRATION_FAILED"
        )
        execution.refresh_from_db()
        run = EntityMigrationRun.objects.get(
            migration_id=self.migration_id, entity="cittadino"
        )
        self.assertEqual(execution.status, "failed")
        self.assertEqual(execution.last_error, "DIGEST_MISMATCH")
        self.assertFalse(execution.last_error_recoverable)
        self.assertEqual(run.status, "failed")
        self.assertEqual(run.last_error, "DIGEST_MISMATCH")
        second = self.batch(
            1, self.citizens[1:], "page1.signature", None, False
        )
        rejected = self.post_batch(second)
        self.assertEqual(rejected.status_code, 409)
        self.assertEqual(rejected.json()["error"]["code"], "MIGRATION_FAILED")

    def test_checkpoint_contract_rejects_partial_or_malformed_values(self):
        payload = self.batch(0, self.citizens[:1], None, "page1.signature", True)
        del payload["hasMore"]
        response = self.post_batch(payload)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "INVALID_CONTRACT")

        malformed = self.batch(
            0, self.citizens[:1], None, "not a cursor", True
        )
        response = self.post_batch(malformed)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"]["code"], "INVALID_CHECKPOINT")

    def test_empty_entities_still_finalize_in_dependency_order(self):
        manifest = self.manifest([])
        self.assertEqual(self.initialize(manifest).status_code, 201)

        def finalize(entity):
            descriptor = next(
                item for item in manifest["entities"] if item["entity"] == entity
            )
            return self.client.post(
                reverse("migration-finalize", args=[self.migration_id]),
                data=json.dumps({
                    "apiVersion": "1.0",
                    "datasetId": manifest["datasetId"],
                    "entity": entity,
                    "expectedRowCount": 0,
                    "expectedBatchCount": 0,
                    "expectedDigest": descriptor["digest"],
                }),
                content_type="application/json",
                **self.auth,
            )

        out_of_order = finalize("patologia")
        self.assertEqual(out_of_order.status_code, 409)
        self.assertEqual(
            out_of_order.json()["error"]["code"], "DEPENDENCY_NOT_COMPLETED"
        )
        for entity in ENTITY_ORDER:
            self.assertEqual(finalize(entity).status_code, 200, entity)
        status = self.client.get(
            reverse("migration-status", args=[self.migration_id]), **self.auth
        ).json()
        self.assertEqual(status["status"], "completed")
        self.assertEqual(status["rowsImported"], 0)
        self.assertEqual(status["currentEntity"], ENTITY_ORDER[-1])
