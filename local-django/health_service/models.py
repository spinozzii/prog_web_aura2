from django.db import models
from django.db.models import F, Q


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
