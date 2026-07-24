import json
from pathlib import Path


_SCHEMA_PATH = Path(__file__).resolve().parents[2] / "shared" / "entity-schema.json"


def _load_schema():
    raw = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
    if raw.get("apiVersion") != "1.0":
        raise RuntimeError("Versione dello schema condiviso non supportata.")
    order = raw.get("entityOrder")
    entities = raw.get("entities")
    if not isinstance(order, list) or not isinstance(entities, dict) or set(order) != set(entities):
        raise RuntimeError("Schema condiviso delle entità non valido.")
    for index, entity in enumerate(order):
        definition = entities[entity]
        fields = definition.get("fields")
        key = definition.get("key")
        expected_previous = order[index - 1] if index else None
        if (
            not isinstance(fields, list)
            or not fields
            or not isinstance(key, list)
            or not key
            or definition.get("previousEntity") != expected_previous
        ):
            raise RuntimeError("Dipendenze dello schema condiviso non valide.")
        names = [field.get("name") for field in fields]
        if len(names) != len(set(names)) or not set(key).issubset(names):
            raise RuntimeError("Campi dello schema condiviso non validi.")
    return raw


SCHEMA = _load_schema()
ENTITY_ORDER = tuple(SCHEMA["entityOrder"])
ENTITIES = SCHEMA["entities"]
