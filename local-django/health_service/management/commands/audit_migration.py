import json

from django.core.management.base import BaseCommand, CommandError

from ...canonical import sha256_dataset, sha256_entity
from ...entity_schema import ENTITY_ORDER
from ...migration_service import validate_migration_id
from ...models import EntityMigrationRun, MigrationExecution
from ...repository import DjangoEntityRepository


class Command(BaseCommand):
    help = "Verifica conteggi e digest senza stampare le righe migrate."

    def add_arguments(self, parser):
        parser.add_argument("--migration-id", required=True)

    def handle(self, *args, **options):
        migration_id = options["migration_id"]
        try:
            validate_migration_id(migration_id)
        except Exception as error:
            raise CommandError("migrationId non valido.") from error

        try:
            execution = MigrationExecution.objects.get(migration_id=migration_id)
        except MigrationExecution.DoesNotExist as error:
            raise CommandError("Migrazione non trovata.") from error
        runs = {
            run.entity: run
            for run in EntityMigrationRun.objects.filter(migration_id=migration_id)
        }
        if set(runs) != set(ENTITY_ORDER):
            raise CommandError("Registro entità incompleto.")

        repository = DjangoEntityRepository()
        descriptors = {}
        entities = []
        total = 0
        for entity in ENTITY_ORDER:
            rows = repository._all_contract_rows(entity)
            digest = sha256_entity(entity, rows)
            run = runs[entity]
            if (
                len(rows) != run.expected_row_count
                or digest != run.expected_digest
                or run.status != "completed"
            ):
                raise CommandError(f"Verifica fallita per {entity}.")
            descriptors[entity] = {"rowCount": len(rows), "digest": digest}
            entities.append({
                "entity": entity,
                "rowCount": len(rows),
                "digest": digest,
            })
            total += len(rows)

        repository._assert_final_invariants("patologia_ricovero")
        repository._assert_final_invariants("progressivo_ricovero")
        actual_dataset_id = sha256_dataset(descriptors)
        if actual_dataset_id != execution.dataset_id or execution.status != "completed":
            raise CommandError("Verifica globale della migrazione fallita.")

        self.stdout.write(json.dumps(
            {
                "apiVersion": "1.0",
                "migrationId": migration_id,
                "datasetId": actual_dataset_id,
                "status": execution.status,
                "entities": entities,
                "totalRowCount": total,
                "verification": {
                    "rowCountMatches": True,
                    "digestMatches": True,
                    "constraintsValid": True,
                },
            },
            ensure_ascii=False,
            separators=(",", ":"),
        ))
