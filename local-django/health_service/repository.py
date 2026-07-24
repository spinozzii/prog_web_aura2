from django.db import transaction

from .canonical import sha256_patologia
from .errors import MigrationApiError
from .models import MigrationBatch, MigrationRun, Patologia


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
