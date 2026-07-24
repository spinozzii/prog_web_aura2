from datetime import date
from decimal import Decimal

from django.db import IntegrityError, transaction
from django.db.models import Exists, Max, OuterRef

from .canonical import sha256_dataset, sha256_entity, sha256_patologia
from .entity_schema import ENTITIES, ENTITY_ORDER
from .errors import MigrationApiError
from .models import (
    Cittadino,
    EntityMigrationBatch,
    EntityMigrationRun,
    MigrationBatch,
    MigrationRun,
    Ospedale,
    Patologia,
    PatologiaCronica,
    PatologiaMortale,
    PatologiaRicovero,
    ProgressivoRicovero,
    Ricovero,
)


class DjangoPatologiaRepository:
    @transaction.atomic
    def apply_batch(self, migration_id, batch):
        try:
            run = MigrationRun.objects.select_for_update().get(migration_id=migration_id)
        except MigrationRun.DoesNotExist:
            if batch["batchSequence"] != 0:
                raise MigrationApiError(409, "UNEXPECTED_SEQUENCE", "Il primo lotto deve avere sequenza zero.")
            run = MigrationRun.objects.create(
                migration_id=migration_id,
                dataset_id=batch["datasetId"],
                expected_row_count=batch["expectedRowCount"],
                expected_digest=batch["expectedDigest"],
                status="created",
            )

        self._assert_identity(run, batch)
        existing = MigrationBatch.objects.filter(
            migration=run, entity="patologia", batch_sequence=batch["batchSequence"]
        ).first()
        if existing:
            if existing.digest == batch["digest"] and existing.row_count == batch["rowCount"]:
                return run, True
            raise MigrationApiError(409, "BATCH_CONFLICT", "Il lotto esiste con contenuto diverso.")
        if run.status == "completed":
            raise MigrationApiError(409, "MIGRATION_COMPLETED", "La migrazione è già completata.")
        if run.status == "failed":
            raise MigrationApiError(409, "MIGRATION_FAILED", "La migrazione è fallita.")
        if batch["batchSequence"] != run.next_sequence:
            raise MigrationApiError(409, "UNEXPECTED_SEQUENCE", "La sequenza del lotto non è quella attesa.")
        if run.imported_row_count + batch["rowCount"] > run.expected_row_count:
            raise MigrationApiError(409, "ROW_COUNT_CONFLICT", "Il lotto supera il totale atteso.")
        if run.last_key and batch["rows"][0]["cod"] <= run.last_key:
            raise MigrationApiError(409, "BATCH_ORDER_CONFLICT", "Il lotto non segue l’ultima chiave confermata.")

        for row in batch["rows"]:
            existing_row = Patologia.objects.select_for_update().filter(cod=row["cod"]).first()
            if existing_row is None:
                Patologia.objects.create(
                    cod=row["cod"],
                    nome=row["nome"],
                    criticita=row["criticita"],
                )
            elif existing_row.nome != row["nome"] or existing_row.criticita != row["criticita"]:
                raise MigrationApiError(
                    409,
                    "ROW_CONFLICT",
                    "Una Patologia esistente contiene valori diversi.",
                )
        MigrationBatch.objects.create(
            migration=run,
            entity="patologia",
            batch_sequence=batch["batchSequence"],
            digest=batch["digest"],
            row_count=batch["rowCount"],
        )
        run.next_sequence += 1
        run.imported_row_count += batch["rowCount"]
        run.last_key = batch["rows"][-1]["cod"]
        run.status = "running"
        run.last_error = ""
        run.save()
        return run, False

    @transaction.atomic
    def finalize(self, migration_id, expected):
        try:
            run = MigrationRun.objects.select_for_update().get(migration_id=migration_id)
        except MigrationRun.DoesNotExist:
            if expected["expectedRowCount"] != 0 or expected["expectedBatchCount"] != 0:
                raise MigrationApiError(404, "MIGRATION_NOT_FOUND", "Migrazione non trovata.")
            run = MigrationRun.objects.create(
                migration_id=migration_id,
                dataset_id=expected["datasetId"],
                expected_row_count=0,
                expected_digest=expected["expectedDigest"],
                status="created",
            )
        self._assert_identity(run, expected)
        if run.status == "failed":
            raise MigrationApiError(409, "MIGRATION_FAILED", "La migrazione è fallita.")
        sequences = list(run.batches.order_by("batch_sequence").values_list("batch_sequence", flat=True))
        if (
            sequences != list(range(expected["expectedBatchCount"]))
            or run.next_sequence != expected["expectedBatchCount"]
            or run.imported_row_count != run.expected_row_count
        ):
            raise MigrationApiError(409, "MIGRATION_INCOMPLETE", "La migrazione non contiene tutti i lotti attesi.")
        rows = list(Patologia.objects.order_by("cod").values("cod", "nome", "criticita"))
        actual_digest = sha256_patologia(rows)
        if len(rows) != run.expected_row_count or actual_digest != run.expected_digest:
            raise MigrationApiError(409, "FINAL_DIGEST_MISMATCH", "Conteggio o digest finale non coincide.")
        run.status = "completed"
        run.last_error = ""
        run.save()
        return run

    def status(self, migration_id):
        try:
            return MigrationRun.objects.get(migration_id=migration_id)
        except MigrationRun.DoesNotExist:
            raise MigrationApiError(404, "MIGRATION_NOT_FOUND", "Migrazione non trovata.")

    @staticmethod
    def _assert_identity(run, payload):
        if (
            run.dataset_id != payload["datasetId"]
            or run.entity != payload["entity"]
            or run.expected_row_count != payload["expectedRowCount"]
            or run.expected_digest != payload["expectedDigest"]
        ):
            raise MigrationApiError(409, "MIGRATION_CONFLICT", "La migrazione usa un contratto diverso.")


MODEL_BY_ENTITY = {
    "cittadino": Cittadino,
    "patologia": Patologia,
    "patologia_cronica": PatologiaCronica,
    "patologia_mortale": PatologiaMortale,
    "ospedale": Ospedale,
    "ricovero": Ricovero,
    "patologia_ricovero": PatologiaRicovero,
    "progressivo_ricovero": ProgressivoRicovero,
}


class DjangoEntityRepository:
    """Generic T03 persistence driven by the shared entity schema."""

    def apply_batch(self, migration_id, batch):
        try:
            with transaction.atomic():
                return self._apply_batch(migration_id, batch)
        except IntegrityError:
            raise MigrationApiError(
                409, "CONSTRAINT_CONFLICT", "Il lotto viola un vincolo PostgreSQL."
            )

    def _apply_batch(self, migration_id, batch):
        entity = batch["entity"]
        run = EntityMigrationRun.objects.select_for_update().filter(
            migration_id=migration_id, entity=entity
        ).first()
        if run is None:
            if batch["batchSequence"] != 0:
                raise MigrationApiError(
                    409, "UNEXPECTED_SEQUENCE", "Il primo lotto deve avere sequenza zero."
                )
            self._assert_dataset_and_dependency(migration_id, batch)
            run = EntityMigrationRun.objects.create(
                migration_id=migration_id,
                dataset_id=batch["datasetId"],
                entity=entity,
                expected_row_count=batch["expectedRowCount"],
                expected_digest=batch["expectedDigest"],
                status="created",
            )

        self._assert_identity(run, batch)
        existing_batch = run.batches.filter(batch_sequence=batch["batchSequence"]).first()
        if existing_batch:
            if (
                existing_batch.digest == batch["digest"]
                and existing_batch.row_count == batch["rowCount"]
            ):
                return run, True
            raise MigrationApiError(
                409, "BATCH_CONFLICT", "Il lotto esiste con contenuto diverso."
            )
        if run.status == "completed":
            raise MigrationApiError(409, "MIGRATION_COMPLETED", "L'entità è già completata.")
        if run.status == "failed":
            raise MigrationApiError(409, "MIGRATION_FAILED", "La migrazione è fallita.")
        if batch["batchSequence"] != run.next_sequence:
            raise MigrationApiError(
                409, "UNEXPECTED_SEQUENCE", "La sequenza del lotto non è quella attesa."
            )
        if run.imported_row_count + batch["rowCount"] > run.expected_row_count:
            raise MigrationApiError(
                409, "ROW_COUNT_CONFLICT", "Il lotto supera il totale atteso."
            )

        definition = ENTITIES[entity]
        first_key = [batch["rows"][0][name] for name in definition["key"]]
        if run.last_key and tuple(first_key) <= tuple(run.last_key):
            raise MigrationApiError(
                409, "BATCH_ORDER_CONFLICT", "Il lotto non segue l'ultima chiave confermata."
            )

        model = MODEL_BY_ENTITY[entity]
        for row in batch["rows"]:
            self._assert_foreign_keys(row, definition)
            self._assert_uniques(row, definition, model)
            key_filter = self._filter(model, definition["key"], row)
            existing = model.objects.select_for_update().filter(**key_filter).first()
            values = self._database_values(model, definition, row)
            if existing is None:
                model.objects.create(**values)
            elif any(getattr(existing, name) != value for name, value in values.items()):
                raise MigrationApiError(
                    409,
                    "ROW_CONFLICT",
                    f"Una riga {entity} esistente contiene valori diversi.",
                )

        EntityMigrationBatch.objects.create(
            run=run,
            batch_sequence=batch["batchSequence"],
            digest=batch["digest"],
            row_count=batch["rowCount"],
        )
        run.next_sequence += 1
        run.imported_row_count += batch["rowCount"]
        run.last_key = [batch["rows"][-1][name] for name in definition["key"]]
        run.status = "running"
        run.last_error = ""
        run.save()
        return run, False

    def finalize(self, migration_id, expected):
        try:
            with transaction.atomic():
                return self._finalize(migration_id, expected)
        except IntegrityError:
            raise MigrationApiError(
                409, "CONSTRAINT_CONFLICT", "La finalizzazione viola un vincolo PostgreSQL."
            )

    def _finalize(self, migration_id, expected):
        entity = expected["entity"]
        run = EntityMigrationRun.objects.select_for_update().filter(
            migration_id=migration_id, entity=entity
        ).first()
        if run is None:
            if expected["expectedRowCount"] != 0 or expected["expectedBatchCount"] != 0:
                raise MigrationApiError(404, "MIGRATION_NOT_FOUND", "Migrazione non trovata.")
            self._assert_dataset_and_dependency(migration_id, expected)
            run = EntityMigrationRun.objects.create(
                migration_id=migration_id,
                dataset_id=expected["datasetId"],
                entity=entity,
                expected_row_count=0,
                expected_digest=expected["expectedDigest"],
                status="created",
            )
        self._assert_identity(run, expected)
        if run.status == "failed":
            raise MigrationApiError(409, "MIGRATION_FAILED", "La migrazione è fallita.")
        sequences = list(run.batches.order_by("batch_sequence").values_list("batch_sequence", flat=True))
        if (
            sequences != list(range(expected["expectedBatchCount"]))
            or run.next_sequence != expected["expectedBatchCount"]
            or run.imported_row_count != run.expected_row_count
        ):
            raise MigrationApiError(
                409, "MIGRATION_INCOMPLETE", "La migrazione non contiene tutti i lotti attesi."
            )

        rows = self._all_contract_rows(entity)
        if len(rows) != run.expected_row_count or sha256_entity(entity, rows) != run.expected_digest:
            raise MigrationApiError(
                409, "FINAL_DIGEST_MISMATCH", "Conteggio o digest finale non coincide."
            )
        self._assert_final_invariants(entity)
        if entity == ENTITY_ORDER[-1]:
            self._assert_global_dataset(migration_id, run)
        run.status = "completed"
        run.last_error = ""
        run.save()
        return run

    def status(self, migration_id):
        runs = list(EntityMigrationRun.objects.filter(migration_id=migration_id))
        if not runs:
            raise MigrationApiError(404, "MIGRATION_NOT_FOUND", "Migrazione non trovata.")
        by_entity = {run.entity: run for run in runs}
        ordered = [by_entity[name] for name in ENTITY_ORDER if name in by_entity]
        current = next((run for run in ordered if run.status != "completed"), ordered[-1])
        complete = len(ordered) == len(ENTITY_ORDER) and all(
            run.status == "completed" for run in ordered
        )
        if any(run.status == "failed" for run in ordered):
            aggregate_status = "failed"
        elif complete:
            aggregate_status = "completed"
        else:
            aggregate_status = "running"
        return {
            "dataset_id": current.dataset_id,
            "entity": current.entity,
            "status": aggregate_status,
            "imported_row_count": sum(run.imported_row_count for run in ordered),
            "expected_row_count": sum(run.expected_row_count for run in ordered),
            "next_sequence": sum(run.next_sequence for run in ordered),
            "last_batch_sequence": (
                current.next_sequence - 1 if current.next_sequence else None
            ),
            "last_error": current.last_error,
        }

    @staticmethod
    def _assert_identity(run, payload):
        if (
            run.dataset_id != payload["datasetId"]
            or run.entity != payload["entity"]
            or run.expected_row_count != payload["expectedRowCount"]
            or run.expected_digest != payload["expectedDigest"]
        ):
            raise MigrationApiError(
                409, "MIGRATION_CONFLICT", "La migrazione usa un contratto diverso."
            )

    @staticmethod
    def _assert_global_dataset(migration_id, current_run):
        runs = {
            run.entity: run
            for run in EntityMigrationRun.objects.select_for_update().filter(
                migration_id=migration_id
            )
        }
        if set(runs) != set(ENTITY_ORDER):
            raise MigrationApiError(
                409, "DATASET_INCOMPLETE", "Il dataset non contiene tutte le entità."
            )
        descriptors = {}
        for entity in ENTITY_ORDER:
            run = runs[entity]
            if run.dataset_id != current_run.dataset_id or (
                entity != current_run.entity and run.status != "completed"
            ):
                raise MigrationApiError(
                    409, "DATASET_INCOMPLETE", "Il dataset non è stato finalizzato in ordine."
                )
            descriptors[entity] = {
                "rowCount": run.expected_row_count,
                "digest": run.expected_digest,
            }
        if sha256_dataset(descriptors) != current_run.dataset_id:
            raise MigrationApiError(
                409,
                "DATASET_DIGEST_MISMATCH",
                "Il digest globale del dataset non coincide.",
            )

    @staticmethod
    def _assert_dataset_and_dependency(migration_id, payload):
        if EntityMigrationRun.objects.filter(migration_id=migration_id).exclude(
            dataset_id=payload["datasetId"]
        ).exists():
            raise MigrationApiError(
                409, "MIGRATION_CONFLICT", "Le entità non appartengono allo stesso dataset."
            )
        previous = ENTITIES[payload["entity"]]["previousEntity"]
        if previous and not EntityMigrationRun.objects.filter(
            migration_id=migration_id,
            dataset_id=payload["datasetId"],
            entity=previous,
            status="completed",
        ).exists():
            raise MigrationApiError(
                409,
                "DEPENDENCY_NOT_COMPLETED",
                "L'entità precedente non è stata completata.",
            )

    def _assert_foreign_keys(self, row, definition):
        for foreign_key in definition["foreignKeys"]:
            target = foreign_key["targetEntity"]
            target_model = MODEL_BY_ENTITY[target]
            target_definition = ENTITIES[target]
            target_row = dict(zip(
                foreign_key["targetFields"],
                (row[name] for name in foreign_key["fields"]),
            ))
            key_filter = self._filter(
                target_model, foreign_key["targetFields"], target_row
            )
            if not target_model.objects.filter(**key_filter).exists():
                raise MigrationApiError(
                    409, "FOREIGN_KEY_CONFLICT", "Il lotto riferisce una riga inesistente."
                )

    def _assert_uniques(self, row, definition, model):
        for unique_fields in definition["unique"]:
            unique_filter = self._filter(model, unique_fields, row)
            key_filter = self._filter(model, definition["key"], row)
            if model.objects.filter(**unique_filter).exclude(**key_filter).exists():
                raise MigrationApiError(
                    409, "UNIQUE_CONFLICT", "Il lotto viola un vincolo univoco."
                )

    @staticmethod
    def _filter(model, names, row):
        return {
            model._meta.get_field(name).attname: row[name]
            for name in names
        }

    @staticmethod
    def _database_values(model, definition, row):
        values = {}
        for field in definition["fields"]:
            name = field["name"]
            value = row[name]
            if field["type"] == "date":
                value = date.fromisoformat(value)
            elif field["type"] == "decimal2":
                value = Decimal(value)
            values[model._meta.get_field(name).attname] = value
        return values

    def _all_contract_rows(self, entity):
        definition = ENTITIES[entity]
        model = MODEL_BY_ENTITY[entity]
        rows = []
        for instance in model.objects.all():
            row = {}
            for field in definition["fields"]:
                name = field["name"]
                value = getattr(instance, model._meta.get_field(name).attname)
                if field["type"] == "date":
                    value = value.isoformat()
                elif field["type"] == "decimal2":
                    value = format(value, ".2f")
                row[name] = value
            rows.append(row)
        return rows

    @staticmethod
    def _assert_final_invariants(entity):
        if entity == "patologia_ricovero":
            associated = PatologiaRicovero.objects.filter(
                cod_ospedale=OuterRef("cod_ospedale_id"),
                cod_ricovero=OuterRef("cod"),
            )
            if Ricovero.objects.annotate(has_pathology=Exists(associated)).filter(
                has_pathology=False
            ).exists():
                raise MigrationApiError(
                    409,
                    "MISSING_RICOVERO_PATHOLOGY",
                    "Ogni ricovero deve avere almeno una patologia.",
                )
        elif entity == "progressivo_ricovero":
            progressivi = {
                row.cod_ospedale_id: row.prossimo_cod
                for row in ProgressivoRicovero.objects.all()
            }
            if set(progressivi) != set(Ospedale.objects.values_list("codice", flat=True)):
                raise MigrationApiError(
                    409,
                    "INVALID_PROGRESSIVO",
                    "Ogni ospedale deve avere un progressivo.",
                )
            maxima = {
                row["cod_ospedale_id"]: row["maximum"]
                for row in Ricovero.objects.values("cod_ospedale_id").annotate(maximum=Max("cod"))
            }
            for hospital, next_code in progressivi.items():
                if next_code != maxima.get(hospital, 0) + 1:
                    raise MigrationApiError(
                        409,
                        "INVALID_PROGRESSIVO",
                        "Il progressivo non coincide con il massimo ricovero.",
                    )
