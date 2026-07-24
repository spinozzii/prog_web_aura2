import json
import secrets

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured, RequestDataTooBig
from django.db import DatabaseError
from django.http import JsonResponse

from .errors import MigrationApiError
from .migration_service import validate_batch, validate_finalize, validate_migration_id
from .repository import DjangoEntityRepository, DjangoPatologiaRepository


def _strict_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON field")
        result[key] = value
    return result


def _reject_json_constant(_value):
    raise ValueError("Non-finite JSON number")


def _json(body, status=200):
    return JsonResponse(body, status=status, content_type="application/json; charset=utf-8")


def health(request):
    if request.method != "GET":
        return _error(MigrationApiError(405, "METHOD_NOT_ALLOWED", "Metodo non consentito."))
    return _json({"apiVersion": "1.0", "service": "local-django", "status": "ok"})


def batches(request, migration_id):
    return _dispatch(request, migration_id, "POST", _receive_batch)


def finalize(request, migration_id):
    return _dispatch(request, migration_id, "POST", _finalize)


def migration_status(request, migration_id):
    return _dispatch(request, migration_id, "GET", _status)


def _dispatch(request, migration_id, expected_method, operation):
    try:
        if request.method != expected_method:
            raise MigrationApiError(405, "METHOD_NOT_ALLOWED", "Metodo non consentito.")
        _authorize(request)
        validate_migration_id(migration_id)
        payload = None if expected_method == "GET" else _parse_body(request)
        return operation(migration_id, payload)
    except MigrationApiError as error:
        return _error(error)
    except (DatabaseError, ImproperlyConfigured):
        return _error(MigrationApiError(503, "DATABASE_UNAVAILABLE", "PostgreSQL non è disponibile."))
    except Exception:
        return _error(MigrationApiError(500, "INTERNAL_ERROR", "Errore interno del servizio locale."))


def _receive_batch(migration_id, payload):
    batch = validate_batch(payload)
    repository = _repository(batch)
    run, duplicate = repository.apply_batch(migration_id, batch)
    return _json({
        "apiVersion": "1.0",
        "migrationId": migration_id,
        "datasetId": run.dataset_id,
        "entity": batch["entity"],
        "batchSequence": batch["batchSequence"],
        "rowCount": batch["rowCount"],
        "digest": batch["digest"],
        "idempotent": duplicate,
        "status": run.status,
    }, status=200 if duplicate else 201)


def _finalize(migration_id, payload):
    expected = validate_finalize(payload)
    run = _repository(expected).finalize(migration_id, expected)
    return _json({
        "apiVersion": "1.0",
        "migrationId": migration_id,
        "datasetId": run.dataset_id,
        "entity": expected["entity"],
        "status": run.status,
        "rowCount": run.imported_row_count,
        "batchCount": run.next_sequence,
        "digest": run.expected_digest,
        "verification": {"rowCountMatches": True, "digestMatches": True, "constraintsValid": True},
    })


def _status(migration_id, payload):
    try:
        summary = DjangoEntityRepository().status(migration_id)
    except MigrationApiError as error:
        if error.code != "MIGRATION_NOT_FOUND":
            raise
        run = DjangoPatologiaRepository().status(migration_id)
        summary = {
            "dataset_id": run.dataset_id,
            "entity": run.entity,
            "status": run.status,
            "imported_row_count": run.imported_row_count,
            "expected_row_count": run.expected_row_count,
            "next_sequence": run.next_sequence,
            "last_batch_sequence": run.next_sequence - 1 if run.next_sequence else None,
            "last_error": run.last_error,
        }
    return _json({
        "apiVersion": "1.0",
        "migrationId": migration_id,
        "datasetId": summary["dataset_id"],
        "entity": summary["entity"],
        "status": summary["status"],
        "rowsImported": summary["imported_row_count"],
        "totalExpected": summary["expected_row_count"],
        "batchesImported": summary["next_sequence"],
        "lastBatchSequence": summary["last_batch_sequence"],
        "lastError": summary["last_error"] or None,
    })


def _repository(payload):
    # Keep the executable T02.2 one-entity contract usable while T03 uses a
    # global dataset identifier distinct from each entity digest.
    if (
        payload["entity"] == "patologia"
        and payload["datasetId"] == payload["expectedDigest"]
    ):
        return DjangoPatologiaRepository()
    return DjangoEntityRepository()


def _authorize(request):
    secret = settings.LOCAL_API_SECRET
    if not secret:
        raise MigrationApiError(503, "SERVICE_NOT_CONFIGURED", "Il segreto locale non è configurato.")
    if not secrets.compare_digest(request.headers.get("Authorization", ""), "Bearer " + secret):
        raise MigrationApiError(401, "UNAUTHORIZED", "Autenticazione richiesta.")


def _parse_body(request):
    if request.content_type != "application/json":
        raise MigrationApiError(400, "INVALID_JSON", "È richiesto JSON.")
    raw_length = request.META.get("CONTENT_LENGTH", "")
    if raw_length:
        try:
            if int(raw_length) > settings.MAX_MIGRATION_REQUEST_BYTES:
                raise MigrationApiError(413, "REQUEST_TOO_LARGE", "La richiesta supera il limite consentito.")
        except ValueError:
            raise MigrationApiError(400, "INVALID_REQUEST", "Content-Length non valido.")
    try:
        body = request.body
        if len(body) > settings.MAX_MIGRATION_REQUEST_BYTES:
            raise MigrationApiError(413, "REQUEST_TOO_LARGE", "La richiesta supera il limite consentito.")
        return json.loads(
            body.decode("utf-8"),
            object_pairs_hook=_strict_object,
            parse_constant=_reject_json_constant,
        )
    except RequestDataTooBig:
        raise MigrationApiError(413, "REQUEST_TOO_LARGE", "La richiesta supera il limite consentito.")
    except (UnicodeDecodeError, ValueError):
        raise MigrationApiError(400, "INVALID_JSON", "JSON non valido.")


def _error(error):
    return _json({"apiVersion": "1.0", "error": {"code": error.code, "message": error.message}}, status=error.status)
