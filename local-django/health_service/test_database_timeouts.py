import json
import os
import threading
import time
import uuid
from unittest import skipUnless

from django.core.exceptions import ImproperlyConfigured
from django.db import close_old_connections, connection
from django.test import Client, SimpleTestCase, TransactionTestCase, override_settings
from django.urls import reverse

from .canonical import sha256_dataset, sha256_entity
from .database_timeouts import PostgresTimeouts
from .entity_schema import ENTITY_ORDER
from .models import Cittadino, EntityMigrationBatch, EntityMigrationRun, MigrationExecution


class DatabaseTimeoutConfigurationTests(SimpleTestCase):
    def test_defaults_are_finite(self):
        timeouts = PostgresTimeouts.from_environment({})
        self.assertEqual(timeouts.connect_seconds, 10)
        self.assertEqual(timeouts.lock_ms, 10_000)
        self.assertEqual(timeouts.statement_ms, 120_000)
        self.assertEqual(timeouts.idle_transaction_ms, 120_000)
        self.assertEqual(
            timeouts.django_options(),
            {
                "connect_timeout": 10,
                "options": (
                    "-c lock_timeout=10000 -c statement_timeout=120000 "
                    "-c idle_in_transaction_session_timeout=120000"
                ),
            },
        )

    def test_valid_boundaries_are_accepted(self):
        timeouts = PostgresTimeouts.from_environment({
            "POSTGRES_CONNECT_TIMEOUT_SECONDS": "60",
            "POSTGRES_LOCK_TIMEOUT_MS": "100",
            "POSTGRES_STATEMENT_TIMEOUT_MS": "600000",
            "POSTGRES_IDLE_TRANSACTION_TIMEOUT_MS": "1000",
        })
        self.assertEqual(timeouts.connect_seconds, 60)
        self.assertEqual(timeouts.lock_ms, 100)

    def test_invalid_values_are_rejected_without_echoing_them(self):
        cases = {
            "POSTGRES_CONNECT_TIMEOUT_SECONDS": ("", " 1", "+1", "0", "61"),
            "POSTGRES_LOCK_TIMEOUT_MS": ("99", "120001", "1.5", "abc"),
            "POSTGRES_STATEMENT_TIMEOUT_MS": ("999", "600001", "-1"),
            "POSTGRES_IDLE_TRANSACTION_TIMEOUT_MS": ("999", "600001", "1e3"),
        }
        for name, invalid_values in cases.items():
            for invalid in invalid_values:
                with self.subTest(name=name, invalid=invalid):
                    with self.assertRaises(ImproperlyConfigured) as caught:
                        PostgresTimeouts.from_environment({name: invalid})
                    self.assertIn(name, str(caught.exception))


@skipUnless(
    os.environ.get("RUN_POSTGRES_LOCK_TEST") == "1",
    "Prova lock PostgreSQL reale non richiesta.",
)
@override_settings(LOCAL_API_SECRET="local-test-secret")
class PostgresLockTimeoutIntegrationTests(TransactionTestCase):
    migration_id = str(uuid.UUID("12121212-1212-4212-8212-121212121212"))
    auth = {"HTTP_AUTHORIZATION": "Bearer local-test-secret"}
    citizen = {
        "cssn": "LOCK-TEST-001",
        "nome": "Anna",
        "cognome": "Rossi",
        "data_nascita": "1980-02-29",
        "luogo_nascita": "Bergamo",
        "indirizzo": "Via Test 1",
    }

    def manifest(self):
        rows = {entity: [] for entity in ENTITY_ORDER}
        rows["cittadino"] = [self.citizen]
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

    def batch(self, manifest):
        digest = sha256_entity("cittadino", [self.citizen])
        return {
            "apiVersion": "1.0",
            "datasetId": manifest["datasetId"],
            "entity": "cittadino",
            "batchSequence": 0,
            "rowCount": 1,
            "rows": [self.citizen],
            "digest": digest,
            "expectedRowCount": 1,
            "expectedDigest": digest,
            "sourceCursor": None,
            "nextCursor": None,
            "hasMore": False,
        }

    def test_lock_timeout_rolls_back_and_retry_resumes(self):
        self.assertEqual(connection.vendor, "postgresql")
        with connection.cursor() as cursor:
            cursor.execute("SHOW lock_timeout")
            self.assertEqual(cursor.fetchone()[0], "500ms")

        manifest = self.manifest()
        initialized = self.client.post(
            reverse("migration-status", args=[self.migration_id]),
            data=json.dumps(manifest),
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(initialized.status_code, 201, initialized.content)

        import psycopg

        database = connection.settings_dict
        locker = psycopg.connect(
            dbname=database["NAME"],
            user=database["USER"],
            password=database["PASSWORD"],
            host=database["HOST"],
            port=database["PORT"],
            connect_timeout=2,
            options="-c statement_timeout=5000 -c lock_timeout=1000",
        )
        result = {}
        payload = self.batch(manifest)

        def post_locked_batch():
            close_old_connections()
            try:
                response = Client().post(
                    reverse("migration-batches", args=[self.migration_id]),
                    data=json.dumps(payload),
                    content_type="application/json",
                    **self.auth,
                )
                result["response"] = response
            except Exception as error:  # pragma: no cover - reported by the parent thread
                result["error"] = error
            finally:
                close_old_connections()

        worker = None
        started = time.monotonic()
        try:
            with locker.cursor() as cursor:
                cursor.execute(
                    "SELECT migration_id FROM migration_execution "
                    "WHERE migration_id = %s FOR UPDATE",
                    (self.migration_id,),
                )
                self.assertIsNotNone(cursor.fetchone())
            worker = threading.Thread(target=post_locked_batch, daemon=True)
            worker.start()
            worker.join(5)
            if worker.is_alive():
                locker.rollback()
                worker.join(2)
                self.fail("La richiesta è rimasta attiva oltre il watchdog di 5 secondi.")
        finally:
            try:
                locker.rollback()
            finally:
                locker.close()
        elapsed = time.monotonic() - started
        self.assertLess(elapsed, 5)
        if "error" in result:
            raise result["error"]
        response = result.get("response")
        self.assertIsNotNone(response)
        self.assertEqual(response.status_code, 503, response.content)
        self.assertEqual(response.json()["error"]["code"], "DATABASE_UNAVAILABLE")

        run = EntityMigrationRun.objects.get(
            migration_id=self.migration_id, entity="cittadino"
        )
        execution = MigrationExecution.objects.get(migration_id=self.migration_id)
        self.assertEqual(run.next_sequence, 0)
        self.assertEqual(run.imported_row_count, 0)
        self.assertIsNone(run.next_cursor)
        self.assertEqual(execution.status, "created")
        self.assertEqual(EntityMigrationBatch.objects.count(), 0)
        self.assertEqual(Cittadino.objects.count(), 0)

        interrupted = self.client.post(
            reverse("migration-failure", args=[self.migration_id]),
            data=json.dumps({
                "apiVersion": "1.0",
                "datasetId": manifest["datasetId"],
                "entity": "cittadino",
                "errorCode": "LOCAL_DATABASE_TIMEOUT",
                "recoverable": True,
            }),
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(interrupted.status_code, 200, interrupted.content)
        self.assertEqual(interrupted.json()["status"], "interrupted")

        resumed = self.client.post(
            reverse("migration-batches", args=[self.migration_id]),
            data=json.dumps(payload),
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(resumed.status_code, 201, resumed.content)
        run.refresh_from_db()
        execution.refresh_from_db()
        self.assertEqual(run.next_sequence, 1)
        self.assertEqual(run.imported_row_count, 1)
        self.assertEqual(execution.status, "running")
        self.assertEqual(execution.last_error, "")
        self.assertIsNone(execution.last_error_recoverable)
        self.assertEqual(EntityMigrationBatch.objects.count(), 1)
        self.assertEqual(Cittadino.objects.count(), 1)
