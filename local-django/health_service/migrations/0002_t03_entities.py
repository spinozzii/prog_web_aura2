import django.db.models.deletion
from django.db import migrations, models


def add_ricovero_composite_fk(apps, schema_editor):
    if schema_editor.connection.vendor == "postgresql":
        schema_editor.execute(
            """
            ALTER TABLE "patologia_ricovero"
            ADD CONSTRAINT "patologia_ricovero_ricovero_fk"
            FOREIGN KEY ("cod_ospedale", "cod_ricovero")
            REFERENCES "ricovero" ("cod_ospedale", "cod")
            DEFERRABLE INITIALLY IMMEDIATE
            """
        )


def remove_ricovero_composite_fk(apps, schema_editor):
    if schema_editor.connection.vendor == "postgresql":
        schema_editor.execute(
            """
            ALTER TABLE "patologia_ricovero"
            DROP CONSTRAINT IF EXISTS "patologia_ricovero_ricovero_fk"
            """
        )


class Migration(migrations.Migration):
    dependencies = [("health_service", "0001_initial")]

    operations = [
        migrations.CreateModel(
            name="PatologiaCronica",
            fields=[
                (
                    "cod_patologia",
                    models.OneToOneField(
                        db_column="cod_patologia",
                        on_delete=django.db.models.deletion.PROTECT,
                        primary_key=True,
                        related_name="+",
                        serialize=False,
                        to="health_service.patologia",
                    ),
                ),
            ],
            options={"db_table": "patologia_cronica"},
        ),
        migrations.CreateModel(
            name="PatologiaMortale",
            fields=[
                (
                    "cod_patologia",
                    models.OneToOneField(
                        db_column="cod_patologia",
                        on_delete=django.db.models.deletion.PROTECT,
                        primary_key=True,
                        related_name="+",
                        serialize=False,
                        to="health_service.patologia",
                    ),
                ),
            ],
            options={"db_table": "patologia_mortale"},
        ),
        migrations.CreateModel(
            name="Cittadino",
            fields=[
                ("cssn", models.TextField(primary_key=True, serialize=False)),
                ("nome", models.TextField()),
                ("cognome", models.TextField()),
                ("data_nascita", models.DateField()),
                ("luogo_nascita", models.TextField()),
                ("indirizzo", models.TextField()),
            ],
            options={
                "db_table": "cittadino",
                "constraints": [
                    models.CheckConstraint(
                        condition=~models.Q(cssn=""), name="cittadino_cssn_non_vuoto"
                    ),
                    models.CheckConstraint(
                        condition=~models.Q(nome=""), name="cittadino_nome_non_vuoto"
                    ),
                    models.CheckConstraint(
                        condition=~models.Q(cognome=""), name="cittadino_cognome_non_vuoto"
                    ),
                    models.CheckConstraint(
                        condition=~models.Q(luogo_nascita=""),
                        name="cittadino_luogo_nascita_non_vuoto",
                    ),
                    models.CheckConstraint(
                        condition=~models.Q(indirizzo=""),
                        name="cittadino_indirizzo_non_vuoto",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="EntityMigrationRun",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True, primary_key=True, serialize=False, verbose_name="ID"
                    ),
                ),
                ("migration_id", models.CharField(max_length=36)),
                ("dataset_id", models.CharField(max_length=64)),
                (
                    "entity",
                    models.CharField(
                        choices=[
                            ("cittadino", "cittadino"),
                            ("patologia", "patologia"),
                            ("patologia_cronica", "patologia_cronica"),
                            ("patologia_mortale", "patologia_mortale"),
                            ("ospedale", "ospedale"),
                            ("ricovero", "ricovero"),
                            ("patologia_ricovero", "patologia_ricovero"),
                            ("progressivo_ricovero", "progressivo_ricovero"),
                        ],
                        max_length=32,
                    ),
                ),
                ("expected_row_count", models.PositiveIntegerField()),
                ("expected_digest", models.CharField(max_length=64)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("created", "created"),
                            ("running", "running"),
                            ("failed", "failed"),
                            ("completed", "completed"),
                        ],
                        default="created",
                        max_length=16,
                    ),
                ),
                ("next_sequence", models.PositiveIntegerField(default=0)),
                ("imported_row_count", models.PositiveIntegerField(default=0)),
                ("last_key", models.JSONField(default=list)),
                ("last_error", models.CharField(blank=True, max_length=64)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options={
                "db_table": "entity_migration_run",
                "constraints": [
                    models.UniqueConstraint(
                        fields=("migration_id", "entity"),
                        name="entity_migration_run_identity",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(
                            entity__in=(
                                "cittadino",
                                "patologia",
                                "patologia_cronica",
                                "patologia_mortale",
                                "ospedale",
                                "ricovero",
                                "patologia_ricovero",
                                "progressivo_ricovero",
                            )
                        ),
                        name="entity_migration_run_entity_valid",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(
                            status__in=["created", "running", "failed", "completed"]
                        ),
                        name="entity_migration_run_status_valid",
                    ),
                    models.CheckConstraint(
                        condition=models.Q(
                            imported_row_count__lte=models.F("expected_row_count")
                        ),
                        name="entity_migration_run_count_valid",
                    ),
                ],
            },
        ),
        migrations.CreateModel(
            name="Ospedale",
            fields=[
                ("codice", models.CharField(max_length=20, primary_key=True, serialize=False)),
                ("nome", models.TextField()),
                ("citta", models.TextField()),
                ("indirizzo", models.TextField()),
                (
                    "direttore_sanitario_cssn",
                    models.OneToOneField(
                        db_column="direttore_sanitario_cssn",
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="+",
                        to="health_service.cittadino",
                    ),
                ),
            ],
            options={"db_table": "ospedale"},
        ),
        migrations.CreateModel(
            name="PatologiaRicovero",
            fields=[
                (
                    "pk",
                    models.CompositePrimaryKey(
                        "cod_ospedale",
                        "cod_ricovero",
                        "cod_patologia",
                        blank=True,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("cod_ospedale", models.CharField(max_length=20)),
                ("cod_ricovero", models.PositiveIntegerField()),
                (
                    "cod_patologia",
                    models.ForeignKey(
                        db_column="cod_patologia",
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="+",
                        to="health_service.patologia",
                    ),
                ),
            ],
            options={"db_table": "patologia_ricovero"},
        ),
        migrations.CreateModel(
            name="Ricovero",
            fields=[
                (
                    "pk",
                    models.CompositePrimaryKey(
                        "cod_ospedale",
                        "cod",
                        blank=True,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("cod", models.PositiveIntegerField()),
                ("data_inizio", models.DateField()),
                ("durata", models.PositiveSmallIntegerField()),
                ("motivo", models.CharField(max_length=500)),
                ("costo", models.DecimalField(decimal_places=2, max_digits=30)),
                (
                    "cod_ospedale",
                    models.ForeignKey(
                        db_column="cod_ospedale",
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="+",
                        to="health_service.ospedale",
                    ),
                ),
                (
                    "paziente_cssn",
                    models.ForeignKey(
                        db_column="paziente_cssn",
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="+",
                        to="health_service.cittadino",
                    ),
                ),
            ],
            options={"db_table": "ricovero"},
        ),
        migrations.CreateModel(
            name="EntityMigrationBatch",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True, primary_key=True, serialize=False, verbose_name="ID"
                    ),
                ),
                ("batch_sequence", models.PositiveIntegerField()),
                ("digest", models.CharField(max_length=64)),
                ("row_count", models.PositiveIntegerField()),
                (
                    "run",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="batches",
                        to="health_service.entitymigrationrun",
                    ),
                ),
            ],
            options={
                "db_table": "entity_migration_batch",
                "constraints": [
                    models.UniqueConstraint(
                        fields=("run", "batch_sequence"),
                        name="entity_migration_batch_identity",
                    )
                ],
            },
        ),
        migrations.CreateModel(
            name="ProgressivoRicovero",
            fields=[
                (
                    "cod_ospedale",
                    models.OneToOneField(
                        db_column="cod_ospedale",
                        on_delete=django.db.models.deletion.PROTECT,
                        primary_key=True,
                        related_name="+",
                        serialize=False,
                        to="health_service.ospedale",
                    ),
                ),
                ("prossimo_cod", models.PositiveIntegerField()),
            ],
            options={
                "db_table": "progressivo_ricovero",
                "constraints": [
                    models.CheckConstraint(
                        condition=models.Q(prossimo_cod__gte=1),
                        name="progressivo_ricovero_cod_positivo",
                    )
                ],
            },
        ),
        migrations.AddConstraint(
            model_name="ospedale",
            constraint=models.CheckConstraint(
                condition=~models.Q(codice=""), name="ospedale_codice_non_vuoto"
            ),
        ),
        migrations.AddConstraint(
            model_name="ospedale",
            constraint=models.CheckConstraint(
                condition=~models.Q(nome=""), name="ospedale_nome_non_vuoto"
            ),
        ),
        migrations.AddConstraint(
            model_name="ospedale",
            constraint=models.CheckConstraint(
                condition=~models.Q(citta=""), name="ospedale_citta_non_vuota"
            ),
        ),
        migrations.AddConstraint(
            model_name="ospedale",
            constraint=models.CheckConstraint(
                condition=~models.Q(indirizzo=""), name="ospedale_indirizzo_non_vuoto"
            ),
        ),
        migrations.AddConstraint(
            model_name="patologiaricovero",
            constraint=models.CheckConstraint(
                condition=~models.Q(cod_ospedale=""),
                name="patologia_ricovero_ospedale_non_vuoto",
            ),
        ),
        migrations.AddConstraint(
            model_name="patologiaricovero",
            constraint=models.CheckConstraint(
                condition=models.Q(cod_ricovero__gte=1),
                name="patologia_ricovero_cod_positivo",
            ),
        ),
        migrations.AddConstraint(
            model_name="ricovero",
            constraint=models.CheckConstraint(
                condition=models.Q(cod__gte=1), name="ricovero_cod_positivo"
            ),
        ),
        migrations.AddConstraint(
            model_name="ricovero",
            constraint=models.CheckConstraint(
                condition=models.Q(durata__gte=1, durata__lte=3650),
                name="ricovero_durata_1_3650",
            ),
        ),
        migrations.AddConstraint(
            model_name="ricovero",
            constraint=models.CheckConstraint(
                condition=~models.Q(motivo=""), name="ricovero_motivo_non_vuoto"
            ),
        ),
        migrations.AddConstraint(
            model_name="ricovero",
            constraint=models.CheckConstraint(
                condition=models.Q(costo__gte=0), name="ricovero_costo_non_negativo"
            ),
        ),
        migrations.RunPython(add_ricovero_composite_fk, remove_ricovero_composite_fk),
    ]
