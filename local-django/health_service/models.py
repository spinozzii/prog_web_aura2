from django.db import models
from django.db.models import F, Q

from .entity_schema import ENTITY_ORDER


class Cittadino(models.Model):
    cssn = models.TextField(primary_key=True)
    nome = models.TextField()
    cognome = models.TextField()
    data_nascita = models.DateField()
    luogo_nascita = models.TextField()
    indirizzo = models.TextField()

    class Meta:
        db_table = "cittadino"
        constraints = [
            models.CheckConstraint(condition=~Q(cssn=""), name="cittadino_cssn_non_vuoto"),
            models.CheckConstraint(condition=~Q(nome=""), name="cittadino_nome_non_vuoto"),
            models.CheckConstraint(condition=~Q(cognome=""), name="cittadino_cognome_non_vuoto"),
            models.CheckConstraint(
                condition=~Q(luogo_nascita=""), name="cittadino_luogo_nascita_non_vuoto"
            ),
            models.CheckConstraint(condition=~Q(indirizzo=""), name="cittadino_indirizzo_non_vuoto"),
        ]


class Patologia(models.Model):
    cod = models.CharField(max_length=20, primary_key=True)
    nome = models.TextField()
    criticita = models.PositiveSmallIntegerField()

    class Meta:
        db_table = "patologia"
        constraints = [
            models.CheckConstraint(condition=Q(criticita__gte=1, criticita__lte=5), name="patologia_criticita_1_5"),
            models.CheckConstraint(condition=~Q(cod=""), name="patologia_cod_non_vuoto"),
            models.CheckConstraint(condition=~Q(nome=""), name="patologia_nome_non_vuoto"),
        ]


class PatologiaCronica(models.Model):
    cod_patologia = models.OneToOneField(
        Patologia,
        db_column="cod_patologia",
        on_delete=models.PROTECT,
        primary_key=True,
        related_name="+",
    )

    class Meta:
        db_table = "patologia_cronica"


class PatologiaMortale(models.Model):
    cod_patologia = models.OneToOneField(
        Patologia,
        db_column="cod_patologia",
        on_delete=models.PROTECT,
        primary_key=True,
        related_name="+",
    )

    class Meta:
        db_table = "patologia_mortale"


class Ospedale(models.Model):
    codice = models.CharField(max_length=20, primary_key=True)
    nome = models.TextField()
    citta = models.TextField()
    indirizzo = models.TextField()
    direttore_sanitario_cssn = models.OneToOneField(
        Cittadino,
        db_column="direttore_sanitario_cssn",
        on_delete=models.PROTECT,
        related_name="+",
    )

    class Meta:
        db_table = "ospedale"
        constraints = [
            models.CheckConstraint(condition=~Q(codice=""), name="ospedale_codice_non_vuoto"),
            models.CheckConstraint(condition=~Q(nome=""), name="ospedale_nome_non_vuoto"),
            models.CheckConstraint(condition=~Q(citta=""), name="ospedale_citta_non_vuota"),
            models.CheckConstraint(condition=~Q(indirizzo=""), name="ospedale_indirizzo_non_vuoto"),
        ]


class Ricovero(models.Model):
    pk = models.CompositePrimaryKey("cod_ospedale", "cod")
    cod_ospedale = models.ForeignKey(
        Ospedale,
        db_column="cod_ospedale",
        on_delete=models.PROTECT,
        related_name="+",
    )
    cod = models.PositiveIntegerField()
    paziente_cssn = models.ForeignKey(
        Cittadino,
        db_column="paziente_cssn",
        on_delete=models.PROTECT,
        related_name="+",
    )
    data_inizio = models.DateField()
    durata = models.PositiveSmallIntegerField()
    motivo = models.CharField(max_length=500)
    costo = models.DecimalField(max_digits=30, decimal_places=2)

    class Meta:
        db_table = "ricovero"
        constraints = [
            models.CheckConstraint(condition=Q(cod__gte=1), name="ricovero_cod_positivo"),
            models.CheckConstraint(
                condition=Q(durata__gte=1, durata__lte=3650), name="ricovero_durata_1_3650"
            ),
            models.CheckConstraint(condition=~Q(motivo=""), name="ricovero_motivo_non_vuoto"),
            models.CheckConstraint(condition=Q(costo__gte=0), name="ricovero_costo_non_negativo"),
        ]


class PatologiaRicovero(models.Model):
    pk = models.CompositePrimaryKey("cod_ospedale", "cod_ricovero", "cod_patologia")
    cod_ospedale = models.CharField(max_length=20)
    cod_ricovero = models.PositiveIntegerField()
    cod_patologia = models.ForeignKey(
        Patologia,
        db_column="cod_patologia",
        on_delete=models.PROTECT,
        related_name="+",
    )

    class Meta:
        db_table = "patologia_ricovero"
        constraints = [
            models.CheckConstraint(
                condition=~Q(cod_ospedale=""), name="patologia_ricovero_ospedale_non_vuoto"
            ),
            models.CheckConstraint(
                condition=Q(cod_ricovero__gte=1), name="patologia_ricovero_cod_positivo"
            ),
        ]


class ProgressivoRicovero(models.Model):
    cod_ospedale = models.OneToOneField(
        Ospedale,
        db_column="cod_ospedale",
        on_delete=models.PROTECT,
        primary_key=True,
        related_name="+",
    )
    prossimo_cod = models.PositiveIntegerField()

    class Meta:
        db_table = "progressivo_ricovero"
        constraints = [
            models.CheckConstraint(
                condition=Q(prossimo_cod__gte=1), name="progressivo_ricovero_cod_positivo"
            ),
        ]


class MigrationRun(models.Model):
    STATUS_CHOICES = [
        ("created", "created"),
        ("running", "running"),
        ("failed", "failed"),
        ("completed", "completed"),
    ]

    migration_id = models.CharField(max_length=36, primary_key=True)
    dataset_id = models.CharField(max_length=64)
    entity = models.CharField(max_length=20, default="patologia")
    expected_row_count = models.PositiveIntegerField()
    expected_digest = models.CharField(max_length=64)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="created")
    next_sequence = models.PositiveIntegerField(default=0)
    imported_row_count = models.PositiveIntegerField(default=0)
    last_key = models.CharField(max_length=20, blank=True)
    last_error = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "migration_run"
        constraints = [
            models.CheckConstraint(condition=Q(entity="patologia"), name="migration_run_entity_patologia"),
            models.CheckConstraint(
                condition=Q(status__in=["created", "running", "failed", "completed"]),
                name="migration_run_status_valid",
            ),
            models.CheckConstraint(
                condition=Q(imported_row_count__lte=F("expected_row_count")),
                name="migration_run_count_not_over_expected",
            ),
        ]


class MigrationBatch(models.Model):
    migration = models.ForeignKey(MigrationRun, on_delete=models.CASCADE, related_name="batches")
    entity = models.CharField(max_length=20)
    batch_sequence = models.PositiveIntegerField()
    digest = models.CharField(max_length=64)
    row_count = models.PositiveIntegerField()

    class Meta:
        db_table = "migration_batch"
        constraints = [
            models.UniqueConstraint(fields=["migration", "entity", "batch_sequence"], name="migration_batch_identity"),
            models.CheckConstraint(condition=Q(entity="patologia"), name="migration_batch_entity_patologia"),
        ]


class EntityMigrationRun(models.Model):
    STATUS_CHOICES = MigrationRun.STATUS_CHOICES

    migration_id = models.CharField(max_length=36)
    dataset_id = models.CharField(max_length=64)
    entity = models.CharField(max_length=32, choices=[(name, name) for name in ENTITY_ORDER])
    expected_row_count = models.PositiveIntegerField()
    expected_digest = models.CharField(max_length=64)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="created")
    next_sequence = models.PositiveIntegerField(default=0)
    imported_row_count = models.PositiveIntegerField(default=0)
    last_key = models.JSONField(default=list)
    last_error = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "entity_migration_run"
        constraints = [
            models.UniqueConstraint(
                fields=["migration_id", "entity"], name="entity_migration_run_identity"
            ),
            models.CheckConstraint(
                condition=Q(entity__in=ENTITY_ORDER), name="entity_migration_run_entity_valid"
            ),
            models.CheckConstraint(
                condition=Q(status__in=["created", "running", "failed", "completed"]),
                name="entity_migration_run_status_valid",
            ),
            models.CheckConstraint(
                condition=Q(imported_row_count__lte=F("expected_row_count")),
                name="entity_migration_run_count_valid",
            ),
        ]


class EntityMigrationBatch(models.Model):
    run = models.ForeignKey(EntityMigrationRun, on_delete=models.CASCADE, related_name="batches")
    batch_sequence = models.PositiveIntegerField()
    digest = models.CharField(max_length=64)
    row_count = models.PositiveIntegerField()

    class Meta:
        db_table = "entity_migration_batch"
        constraints = [
            models.UniqueConstraint(
                fields=["run", "batch_sequence"], name="entity_migration_batch_identity"
            ),
        ]
