import re
import uuid
from datetime import date
from decimal import Decimal, InvalidOperation

from .canonical import sha256_entity
from .entity_schema import ENTITIES
from .errors import MigrationApiError


HEX_64 = re.compile(r"^[0-9a-f]{64}$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
DECIMAL_2 = re.compile(r"^(?:0|[1-9][0-9]*)\.[0-9]{2}$")
BATCH_FIELDS = {
    "apiVersion", "datasetId", "entity", "batchSequence", "rowCount", "rows",
    "digest", "expectedRowCount", "expectedDigest",
}
FINAL_FIELDS = {
    "apiVersion", "datasetId", "entity", "expectedRowCount", "expectedBatchCount", "expectedDigest",
}


def validate_migration_id(migration_id):
    try:
        parsed = uuid.UUID(migration_id)
    except (ValueError, TypeError, AttributeError):
        raise MigrationApiError(400, "INVALID_MIGRATION_ID", "Identificativo migrazione non valido.")
    if str(parsed) != migration_id.lower():
        raise MigrationApiError(400, "INVALID_MIGRATION_ID", "Identificativo migrazione non valido.")


def validate_batch(payload):
    _exact_fields(payload, BATCH_FIELDS)
    entity = _common(payload)
    _integer(payload["batchSequence"], "batchSequence", minimum=0)
    _integer(payload["rowCount"], "rowCount", minimum=1)
    _integer(payload["expectedRowCount"], "expectedRowCount", minimum=1)
    if not isinstance(payload["rows"], list):
        raise MigrationApiError(400, "INVALID_BATCH", "Tipi del lotto non validi.")
    if len(payload["rows"]) != payload["rowCount"]:
        raise MigrationApiError(400, "INVALID_BATCH", "Il conteggio del lotto non coincide.")
    if payload["rowCount"] > payload["expectedRowCount"]:
        raise MigrationApiError(400, "INVALID_BATCH", "Il lotto supera il totale atteso.")

    definition = ENTITIES[entity]
    expected_fields = {field["name"] for field in definition["fields"]}
    key_names = definition["key"]
    rows = []
    previous_key = None
    for raw_row in payload["rows"]:
        if not isinstance(raw_row, dict) or set(raw_row) != expected_fields:
            raise MigrationApiError(400, "INVALID_BATCH", f"Schema {entity} non valido.")
        row = {}
        for field in definition["fields"]:
            row[field["name"]] = _validate_value(raw_row[field["name"]], field)
        key = tuple(row[name] for name in key_names)
        if previous_key is not None and key <= previous_key:
            raise MigrationApiError(
                400, "INVALID_BATCH_ORDER", "Le righe non sono in ordine strettamente crescente."
            )
        previous_key = key
        rows.append(row)
    if sha256_entity(entity, rows) != payload["digest"]:
        raise MigrationApiError(400, "DIGEST_MISMATCH", "Il digest del lotto non coincide.")
    return {**payload, "rows": rows}


def validate_finalize(payload):
    _exact_fields(payload, FINAL_FIELDS)
    entity = _common(payload)
    _integer(payload["expectedRowCount"], "expectedRowCount", minimum=0)
    _integer(payload["expectedBatchCount"], "expectedBatchCount", minimum=0)
    if payload["expectedRowCount"] == 0:
        if (
            payload["expectedBatchCount"] != 0
            or payload["expectedDigest"] != sha256_entity(entity, [])
        ):
            raise MigrationApiError(
                400, "INVALID_CONTRACT", "Il dataset vuoto ha conteggio o digest non valido."
            )
    elif payload["expectedBatchCount"] == 0:
        raise MigrationApiError(
            400, "INVALID_CONTRACT", "Un dataset non vuoto richiede almeno un lotto."
        )
    return payload


def _common(payload):
    if payload["apiVersion"] != "1.0":
        raise MigrationApiError(400, "INVALID_CONTRACT", "Versione non valida.")
    entity = payload["entity"]
    if not isinstance(entity, str) or entity not in ENTITIES:
        raise MigrationApiError(400, "INVALID_CONTRACT", "Entità non valida.")
    for name in ("datasetId", "expectedDigest"):
        if not isinstance(payload[name], str) or not HEX_64.fullmatch(payload[name]):
            raise MigrationApiError(400, "INVALID_CONTRACT", f"{name} non valido.")
    if "digest" in payload and (
        not isinstance(payload["digest"], str) or not HEX_64.fullmatch(payload["digest"])
    ):
        raise MigrationApiError(400, "INVALID_BATCH", "Digest del lotto non valido.")
    return entity


def _validate_value(value, field):
    kind = field["type"]
    name = field["name"]
    if kind == "string":
        if not _valid_text(
            value,
            minimum=field.get("minLength", 1),
            maximum=field.get("maxLength"),
        ):
            raise MigrationApiError(400, "INVALID_BATCH", f"{name} non valido.")
        return value
    if kind == "integer":
        _integer(value, name, field.get("minimum"), field.get("maximum"))
        return value
    if kind == "date":
        if not isinstance(value, str) or not DATE.fullmatch(value):
            raise MigrationApiError(400, "INVALID_BATCH", f"{name} non è una data civile valida.")
        try:
            parsed = date.fromisoformat(value)
        except ValueError:
            raise MigrationApiError(400, "INVALID_BATCH", f"{name} non è una data civile valida.")
        if parsed.isoformat() != value:
            raise MigrationApiError(400, "INVALID_BATCH", f"{name} non è una data civile valida.")
        return value
    if kind == "decimal2":
        if not isinstance(value, str) or not DECIMAL_2.fullmatch(value):
            raise MigrationApiError(400, "INVALID_BATCH", f"{name} non è un decimale canonico.")
        try:
            number = Decimal(value)
            minimum = Decimal(field.get("minimum", "0.00"))
        except InvalidOperation:
            raise MigrationApiError(400, "INVALID_BATCH", f"{name} non è un decimale valido.")
        if number < minimum:
            raise MigrationApiError(400, "INVALID_BATCH", f"{name} fuori dominio.")
        return value
    raise RuntimeError(f"Tipo condiviso non supportato: {kind}")


def _exact_fields(payload, expected):
    if not isinstance(payload, dict) or set(payload) != expected:
        raise MigrationApiError(400, "INVALID_CONTRACT", "Campi della richiesta non validi.")


def _integer(value, name, minimum=None, maximum=None):
    if isinstance(value, bool) or not isinstance(value, int):
        raise MigrationApiError(400, "INVALID_CONTRACT", f"{name} deve essere intero.")
    if minimum is not None and value < minimum or maximum is not None and value > maximum:
        raise MigrationApiError(400, "INVALID_CONTRACT", f"{name} fuori dominio.")


def _valid_text(value, minimum=1, maximum=None):
    if not isinstance(value, str) or "\x00" in value or len(value) < minimum:
        return False
    if maximum is not None and len(value) > maximum:
        return False
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True
