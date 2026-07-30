import json
import uuid
from pathlib import Path

from django.test import SimpleTestCase, TestCase, override_settings
from django.urls import reverse

from .canonical import (
    canonicalize_dataset,
    canonicalize_entity,
    sha256_dataset,
    sha256_entity,
)
from .entity_schema import ENTITY_ORDER
from .models import (
    Cittadino,
    EntityMigrationBatch,
    EntityMigrationRun,
    Ospedale,
    Patologia,
    PatologiaRicovero,
    ProgressivoRicovero,
    Ricovero,
)


class T03SharedCanonicalContractTests(SimpleTestCase):
    @classmethod
    def fixture(cls):
        path = Path(__file__).resolve().parents[2] / "tests" / "fixtures" / "t03-dataset.json"
        return json.loads(path.read_text(encoding="utf-8"))

    def test_all_entities_match_the_shared_fixture(self):
        fixture = self.fixture()
        for entity in ENTITY_ORDER:
            rows = list(reversed(fixture["rowsByEntity"][entity]))
            expected = fixture["expectedByEntity"][entity]
            self.assertEqual(
                canonicalize_entity(entity, rows).encode("utf-8"),
                expected["expectedCanonical"].encode("utf-8"),
                entity,
            )
            self.assertEqual(sha256_entity(entity, rows), expected["expectedSha256"], entity)

    def test_global_dataset_descriptor_matches_the_shared_fixture(self):
        fixture = self.fixture()
        descriptors = {
            entity: {
                "rowCount": fixture["expectedByEntity"][entity]["rowCount"],
                "digest": fixture["expectedByEntity"][entity]["expectedSha256"],
            }
            for entity in ENTITY_ORDER
        }
        self.assertEqual(canonicalize_dataset(descriptors), fixture["expectedDatasetCanonical"])
        self.assertEqual(sha256_dataset(descriptors), fixture["expectedDatasetId"])


@override_settings(LOCAL_API_SECRET="local-test-secret")
class FullEntityMigrationTests(TestCase):
    migration_id = str(uuid.UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"))
    auth = {"HTTP_AUTHORIZATION": "Bearer local-test-secret"}

    fixture = {
        "cittadino": [
            {
                "cssn": "CSSN-001",
                "nome": "Giulia",
                "cognome": "Bianchi",
                "data_nascita": "1900-01-01",
                "luogo_nascita": "Città Alta",
                "indirizzo": "Via dell'Unità 1",
            },
            {
                "cssn": "CSSN-002",
                "nome": "Luca",
                "cognome": "Verdi",
                "data_nascita": "2000-02-29",
                "luogo_nascita": "Bergamo",
                "indirizzo": "Via Roma 2",
            },
        ],
        "patologia": [
            {"cod": "P001", "nome": "Solo cronica", "criticita": 1},
            {"cod": "P002", "nome": "Solo mortale", "criticita": 5},
            {"cod": "P003", "nome": "Entrambe", "criticita": 4},
            {"cod": "P004", "nome": "Nessuna", "criticita": 2},
        ],
        "patologia_cronica": [
            {"cod_patologia": "P001"},
            {"cod_patologia": "P003"},
        ],
        "patologia_mortale": [
            {"cod_patologia": "P002"},
            {"cod_patologia": "P003"},
        ],
        "ospedale": [
            {
                "codice": "H001",
                "nome": "Ospedale Àlfa",
                "citta": "Bergamo",
                "indirizzo": "Via A 1",
                "direttore_sanitario_cssn": "CSSN-001",
            },
            {
                "codice": "H002",
                "nome": "Ospedale Beta",
                "citta": "Milano",
                "indirizzo": "Via B 2",
                "direttore_sanitario_cssn": "CSSN-002",
            },
        ],
        "ricovero": [
            {
                "cod_ospedale": "H001",
                "cod": 1,
                "paziente_cssn": "CSSN-002",
                "data_inizio": "2024-02-29",
                "durata": 5,
                "motivo": "Controllo \"A\"",
                "costo": "10.50",
            },
            {
                "cod_ospedale": "H002",
                "cod": 1,
                "paziente_cssn": "CSSN-001",
                "data_inizio": "2025-12-31",
                "durata": 1,
                "motivo": "Urgenza",
                "costo": "0.00",
            },
        ],
        "patologia_ricovero": [
            {"cod_ospedale": "H001", "cod_ricovero": 1, "cod_patologia": "P001"},
            {"cod_ospedale": "H001", "cod_ricovero": 1, "cod_patologia": "P003"},
            {"cod_ospedale": "H002", "cod_ricovero": 1, "cod_patologia": "P002"},
        ],
        "progressivo_ricovero": [
            {"cod_ospedale": "H001", "prossimo_cod": 2},
            {"cod_ospedale": "H002", "prossimo_cod": 2},
        ],
    }

    @property
    def dataset_id(self):
        return sha256_dataset({
            entity: {
                "rowCount": len(self.active_fixture[entity]),
                "digest": sha256_entity(entity, self.active_fixture[entity]),
            }
            for entity in ENTITY_ORDER
        })

    def manifest(self):
        descriptors = {
            entity: {
                "rowCount": len(self.active_fixture[entity]),
                "digest": sha256_entity(entity, self.active_fixture[entity]),
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

    def initialize(self):
        return self.client.post(
            reverse("migration-status", args=[self.migration_id]),
            data=json.dumps(self.manifest(), ensure_ascii=False),
            content_type="application/json",
            **self.auth,
        )

    def setUp(self):
        self.active_fixture = self.fixture
        self.migration_id = str(
            uuid.UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
        )
        response = self.initialize()
        self.assertEqual(response.status_code, 201, response.content)

    def batch_payload(
        self,
        entity,
        sequence,
        rows,
        expected_rows=None,
        source_cursor=None,
        next_cursor=None,
        has_more=False,
    ):
        expected_rows = (
            self.active_fixture[entity] if expected_rows is None else expected_rows
        )
        return {
            "apiVersion": "1.0",
            "datasetId": self.dataset_id,
            "entity": entity,
            "batchSequence": sequence,
            "rowCount": len(rows),
            "rows": rows,
            "digest": sha256_entity(entity, rows),
            "expectedRowCount": len(expected_rows),
            "expectedDigest": sha256_entity(entity, expected_rows),
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

    def finalize(self, entity, expected_rows=None, expected_batches=1):
        expected_rows = (
            self.active_fixture[entity] if expected_rows is None else expected_rows
        )
        payload = {
            "apiVersion": "1.0",
            "datasetId": self.dataset_id,
            "entity": entity,
            "expectedRowCount": len(expected_rows),
            "expectedBatchCount": expected_batches if expected_rows else 0,
            "expectedDigest": sha256_entity(entity, expected_rows),
        }
        return self.client.post(
            reverse("migration-finalize", args=[self.migration_id]),
            data=json.dumps(payload),
            content_type="application/json",
            **self.auth,
        )

    def complete(self, entity, rows=None):
        rows = self.active_fixture[entity] if rows is None else rows
        if rows:
            response = self.post_batch(self.batch_payload(entity, 0, rows, rows))
            self.assertEqual(response.status_code, 201, response.content)
        response = self.finalize(entity, rows)
        self.assertEqual(response.status_code, 200, response.content)
        return response

    def complete_before(self, target):
        for entity in ENTITY_ORDER[:ENTITY_ORDER.index(target)]:
            self.complete(entity)

    def test_full_order_composite_pagination_and_idempotent_rerun(self):
        for entity in ENTITY_ORDER:
            if entity == "ricovero":
                rows = self.fixture[entity]
                cursor = "ricovero-page-1.signature"
                first = self.batch_payload(
                    entity,
                    0,
                    rows[:1],
                    next_cursor=cursor,
                    has_more=True,
                )
                second = self.batch_payload(
                    entity,
                    1,
                    rows[1:],
                    source_cursor=cursor,
                )
                self.assertEqual(self.post_batch(first).status_code, 201)
                self.assertEqual(self.post_batch(second).status_code, 201)
                self.assertEqual(self.finalize(entity, expected_batches=2).status_code, 200)
                duplicate = self.post_batch(second)
                self.assertEqual(duplicate.status_code, 200)
                self.assertTrue(duplicate.json()["idempotent"])
            else:
                completed = self.complete(entity)
                self.assertEqual(completed.json()["entity"], entity)
                self.assertTrue(completed.json()["verification"]["constraintsValid"])

        self.assertEqual(Cittadino.objects.count(), 2)
        self.assertEqual(Patologia.objects.count(), 4)
        self.assertTrue(Ricovero.objects.filter(pk=("H001", 1)).exists())
        self.assertTrue(Ricovero.objects.filter(pk=("H002", 1)).exists())
        self.assertEqual(PatologiaRicovero.objects.count(), 3)
        self.assertEqual(ProgressivoRicovero.objects.count(), 2)
        self.assertEqual(EntityMigrationRun.objects.count(), 8)
        self.assertEqual(EntityMigrationBatch.objects.count(), 9)
        status = self.client.get(
            reverse("migration-status", args=[self.migration_id]), **self.auth
        )
        self.assertEqual(status.status_code, 200)
        self.assertEqual(status.json()["status"], "completed")
        self.assertEqual(status.json()["entity"], "progressivo_ricovero")
        self.assertEqual(status.json()["lastBatchSequence"], 0)

    def test_dependency_fk_unique_and_transaction_rollback(self):
        early = self.post_batch(self.batch_payload("patologia", 0, self.fixture["patologia"]))
        self.assertEqual(early.status_code, 409)
        self.assertEqual(early.json()["error"]["code"], "DEPENDENCY_NOT_COMPLETED")

        self.complete("cittadino")
        partial_status = self.client.get(
            reverse("migration-status", args=[self.migration_id]), **self.auth
        )
        self.assertEqual(partial_status.status_code, 200)
        self.assertEqual(partial_status.json()["status"], "running")
        self.complete("patologia")
        missing = self.batch_payload(
            "patologia_cronica", 0, [{"cod_patologia": "P999"}]
        )
        response = self.post_batch(missing)
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "FOREIGN_KEY_CONFLICT")
        self.assertEqual(
            EntityMigrationBatch.objects.filter(
                run__migration_id=self.migration_id,
                run__entity="patologia_cronica",
            ).count(),
            0,
        )

        self.complete("patologia_cronica")
        self.complete("patologia_mortale")
        duplicate_director = [
            self.fixture["ospedale"][0],
            {
                **self.fixture["ospedale"][1],
                "direttore_sanitario_cssn": "CSSN-001",
            },
        ]
        response = self.post_batch(
            self.batch_payload("ospedale", 0, duplicate_director)
        )
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "UNIQUE_CONFLICT")
        self.assertEqual(Ospedale.objects.count(), 0)
        self.assertEqual(
            EntityMigrationRun.objects.get(
                migration_id=self.migration_id,
                entity="ospedale",
            ).status,
            "created",
        )

    def test_invalid_civil_dates_decimals_digest_and_incomplete_finalize(self):
        bad_date = [dict(self.fixture["cittadino"][0], data_nascita="2023-02-29")]
        response = self.post_batch(self.batch_payload("cittadino", 0, bad_date, bad_date))
        self.assertEqual(response.status_code, 400)

        self.complete_before("ricovero")
        bad_cost = [dict(self.fixture["ricovero"][0], costo="10.5")]
        response = self.post_batch(self.batch_payload("ricovero", 0, bad_cost, bad_cost))
        self.assertEqual(response.status_code, 400)

        wrong_digest = self.batch_payload("ricovero", 0, self.fixture["ricovero"])
        wrong_digest["digest"] = "0" * 64
        response = self.post_batch(wrong_digest)
        self.assertEqual(response.status_code, 400)

        first = self.batch_payload(
            "ricovero",
            0,
            self.fixture["ricovero"][:1],
            next_cursor="ricovero-page-1.signature",
            has_more=True,
        )
        self.assertEqual(self.post_batch(first).status_code, 201)
        incomplete = self.finalize("ricovero", expected_batches=2)
        self.assertEqual(incomplete.status_code, 409)
        self.assertEqual(incomplete.json()["error"]["code"], "MIGRATION_INCOMPLETE")

    def test_missing_association_and_incoherent_progressivo_are_rejected(self):
        only_one = [self.fixture["patologia_ricovero"][0]]
        self.active_fixture = {
            **self.fixture,
            "patologia_ricovero": only_one,
        }
        self.migration_id = str(
            uuid.UUID("abababab-abab-4bab-8bab-abababababab")
        )
        self.assertEqual(self.initialize().status_code, 201)
        self.complete_before("patologia_ricovero")
        self.assertEqual(
            self.post_batch(
                self.batch_payload("patologia_ricovero", 0, only_one)
            ).status_code,
            201,
        )
        response = self.finalize("patologia_ricovero")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "MISSING_RICOVERO_PATHOLOGY")

        # A new migration id can safely reuse identical domain rows.
        bad_progress = [
            self.fixture["progressivo_ricovero"][0],
            {"cod_ospedale": "H002", "prossimo_cod": 3},
        ]
        self.active_fixture = {
            **self.fixture,
            "progressivo_ricovero": bad_progress,
        }
        self.migration_id = str(uuid.UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc"))
        self.assertEqual(self.initialize().status_code, 201)
        for entity in ENTITY_ORDER[:-1]:
            self.complete(entity)
        self.assertEqual(
            self.post_batch(
                self.batch_payload(
                    "progressivo_ricovero", 0, bad_progress
                )
            ).status_code,
            201,
        )
        response = self.finalize("progressivo_ricovero")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["error"]["code"], "INVALID_PROGRESSIVO")

    def test_global_dataset_digest_is_checked_during_initialization(self):
        invalid_manifest = self.manifest()
        invalid_manifest["datasetId"] = "f" * 64
        self.migration_id = str(
            uuid.UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd")
        )
        response = self.client.post(
            reverse("migration-status", args=[self.migration_id]),
            data=json.dumps(invalid_manifest),
            content_type="application/json",
            **self.auth,
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error"]["code"],
            "DATASET_DIGEST_MISMATCH",
        )
