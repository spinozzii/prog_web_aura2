import re
import uuid

from .canonical import sha256_patologia
from .errors import MigrationApiError


HEX_64 = re.compile(r"^[0-9a-f]{64}$")
EMPTY_SHA256 = sha256_patologia([])
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
    _common(payload)
    _integer(payload["batchSequence"], "batchSequence", minimum=0)
    _integer(payload["rowCount"], "rowCount", minimum=1)
    _integer(payload["expectedRowCount"], "expectedRowCount", minimum=1)
    if not isinstance(payload["rows"], list):
        raise MigrationApiError(400, "INVALID_BATCH", "Tipi del lotto non validi.")
    if len(payload["rows"]) != payload["rowCount"]:
        raise MigrationApiError(400, "INVALID_BATCH", "Il conteggio del lotto non coincide.")
    if payload["rowCount"] > payload["expectedRowCount"]:
        raise MigrationApiError(400, "INVALID_BATCH", "Il lotto supera il totale atteso.")
    rows = []
    previous_cod = None
    for row in payload["rows"]:
        if not isinstance(row, dict) or set(row) != {"cod", "nome", "criticita"}:
            raise MigrationApiError(400, "INVALID_BATCH", "Schema Patologia non valido.")
        cod, nome, criticita = row["cod"], row["nome"], row["criticita"]
        if not _valid_text(cod, maximum=20):
            raise MigrationApiError(400, "INVALID_BATCH", "Codice Patologia non valido.")
        if not _valid_text(nome):
            raise MigrationApiError(400, "INVALID_BATCH", "Nome Patologia non valido.")
        _integer(criticita, "criticita", minimum=1, maximum=5)
        if previous_cod is not None and cod <= previous_cod:
            raise MigrationApiError(400, "INVALID_BATCH_ORDER", "Le righe non sono in ordine strettamente crescente.")
        previous_cod = cod
        rows.append({"cod": cod, "nome": nome, "criticita": criticita})
    if sha256_patologia(rows) != payload["digest"]:
        raise MigrationApiError(400, "DIGEST_MISMATCH", "Il digest del lotto non coincide.")
    return {**payload, "rows": rows}


def validate_finalize(payload):
    _exact_fields(payload, FINAL_FIELDS)
    _common(payload)
    _integer(payload["expectedRowCount"], "expectedRowCount", minimum=0)
    _integer(payload["expectedBatchCount"], "expectedBatchCount", minimum=0)
    if payload["expectedRowCount"] == 0:
        if payload["expectedBatchCount"] != 0 or payload["expectedDigest"] != EMPTY_SHA256:
            raise MigrationApiError(400, "INVALID_CONTRACT", "Il dataset vuoto ha conteggio o digest non valido.")
    elif payload["expectedBatchCount"] == 0:
        raise MigrationApiError(400, "INVALID_CONTRACT", "Un dataset non vuoto richiede almeno un lotto.")
    return payload


def _common(payload):
    if payload["apiVersion"] != "1.0" or payload["entity"] != "patologia":
        raise MigrationApiError(400, "INVALID_CONTRACT", "Versione o entità non valida.")
    for name in ("datasetId", "expectedDigest"):
        if not isinstance(payload[name], str) or not HEX_64.fullmatch(payload[name]):
            raise MigrationApiError(400, "INVALID_CONTRACT", f"{name} non valido.")
    if payload["datasetId"] != payload["expectedDigest"]:
        raise MigrationApiError(400, "INVALID_CONTRACT", "Dataset e digest atteso non coincidono.")
    if "digest" in payload and (not isinstance(payload["digest"], str) or not HEX_64.fullmatch(payload["digest"])):
        raise MigrationApiError(400, "INVALID_BATCH", "Digest del lotto non valido.")


def _exact_fields(payload, expected):
    if not isinstance(payload, dict) or set(payload) != expected:
        raise MigrationApiError(400, "INVALID_CONTRACT", "Campi della richiesta non validi.")


def _integer(value, name, minimum=None, maximum=None):
    if isinstance(value, bool) or not isinstance(value, int):
        raise MigrationApiError(400, "INVALID_CONTRACT", f"{name} deve essere intero.")
    if minimum is not None and value < minimum or maximum is not None and value > maximum:
        raise MigrationApiError(400, "INVALID_CONTRACT", f"{name} fuori dominio.")


def _valid_text(value, maximum=None):
    if not isinstance(value, str) or not value or "\x00" in value:
        return False
    if maximum is not None and len(value) > maximum:
        return False
    try:
        value.encode("utf-8")
    except UnicodeEncodeError:
        return False
    return True
