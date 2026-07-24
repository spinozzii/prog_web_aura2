from django.urls import path

from .views import batches, finalize, health, migration_status

urlpatterns = [
    path("health", health, name="health"),
    path("api/v1/migrations/<str:migration_id>/batches", batches, name="migration-batches"),
    path("api/v1/migrations/<str:migration_id>/finalize", finalize, name="migration-finalize"),
    path("api/v1/migrations/<str:migration_id>", migration_status, name="migration-status"),
]
