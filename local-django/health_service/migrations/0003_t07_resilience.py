from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("health_service", "0002_t03_entities"),
    ]

    operations = [
        migrations.CreateModel(
            name="MigrationExecution",
            fields=[
                (
                    "migration_id",
                    models.CharField(max_length=36, primary_key=True, serialize=False),
                ),
                ("dataset_id", models.CharField(max_length=64)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("created", "created"),
                            ("running", "running"),
                            ("interrupted", "interrupted"),
                            ("failed", "failed"),
                            ("completed", "completed"),
                        ],
                        default="created",
                        max_length=16,
                    ),
                ),
                ("current_entity", models.CharField(blank=True, max_length=32)),
                ("last_error", models.CharField(blank=True, max_length=64)),
                (
                    "last_error_recoverable",
                    models.BooleanField(blank=True, null=True),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "db_table": "migration_execution",
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(
                            status__in=[
                                "created",
                                "running",
                                "interrupted",
                                "failed",
                                "completed",
                            ]
                        ),
                        name="migration_execution_status_valid",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(current_entity="")
                        | models.Q(
                            current_entity__in=[
                                "cittadino",
                                "patologia",
                                "patologia_cronica",
                                "patologia_mortale",
                                "ospedale",
                                "ricovero",
                                "patologia_ricovero",
                                "progressivo_ricovero",
                            ]
                        ),
                        name="migration_execution_entity_valid",
                    ),
                ],
            },
        ),
        migrations.AddField(
            model_name="entitymigrationrun",
            name="has_more",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="entitymigrationrun",
            name="next_cursor",
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="entitymigrationrun",
            name="source_cursor",
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="entitymigrationbatch",
            name="has_more",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="entitymigrationbatch",
            name="next_cursor",
            field=models.TextField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="entitymigrationbatch",
            name="source_cursor",
            field=models.TextField(blank=True, null=True),
        ),
    ]
