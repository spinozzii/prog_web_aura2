from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    initial = True
    dependencies = []

    operations = [
        migrations.CreateModel(
            name="MigrationRun",
            fields=[
                ("migration_id", models.CharField(max_length=36, primary_key=True, serialize=False)),
                ("dataset_id", models.CharField(max_length=64)),
                ("entity", models.CharField(default="patologia", max_length=20)),
                ("expected_row_count", models.PositiveIntegerField()),
                ("expected_digest", models.CharField(max_length=64)),
                ("status", models.CharField(choices=[("created", "created"), ("running", "running"), ("failed", "failed"), ("completed", "completed")], default="created", max_length=16)),
                ("next_sequence", models.PositiveIntegerField(default=0)),
                ("imported_row_count", models.PositiveIntegerField(default=0)),
                ("last_key", models.CharField(blank=True, max_length=20)),
                ("last_error", models.CharField(blank=True, max_length=64)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "db_table": "migration_run",
                "constraints": [
                    models.CheckConstraint(condition=models.Q(entity="patologia"), name="migration_run_entity_patologia"),
                    models.CheckConstraint(condition=models.Q(status__in=["created", "running", "failed", "completed"]), name="migration_run_status_valid"),
                    models.CheckConstraint(condition=models.Q(imported_row_count__lte=models.F("expected_row_count")), name="migration_run_count_not_over_expected"),
                ],
            },
        ),
        migrations.CreateModel(
            name="Patologia",
            fields=[
                ("cod", models.CharField(max_length=20, primary_key=True, serialize=False)),
                ("nome", models.TextField()),
                ("criticita", models.PositiveSmallIntegerField()),
            ],
            options={
                "db_table": "patologia",
                "constraints": [
                    models.CheckConstraint(condition=models.Q(criticita__gte=1, criticita__lte=5), name="patologia_criticita_1_5"),
                    models.CheckConstraint(condition=~models.Q(cod=""), name="patologia_cod_non_vuoto"),
                    models.CheckConstraint(condition=~models.Q(nome=""), name="patologia_nome_non_vuoto"),
                ],
            },
        ),
        migrations.CreateModel(
            name="MigrationBatch",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("entity", models.CharField(max_length=20)),
                ("batch_sequence", models.PositiveIntegerField()),
                ("digest", models.CharField(max_length=64)),
                ("row_count", models.PositiveIntegerField()),
                ("migration", models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name="batches", to="health_service.migrationrun")),
            ],
            options={
                "db_table": "migration_batch",
                "constraints": [
                    models.UniqueConstraint(fields=("migration", "entity", "batch_sequence"), name="migration_batch_identity"),
                    models.CheckConstraint(condition=models.Q(entity="patologia"), name="migration_batch_entity_patologia"),
                ],
            },
        ),
    ]
