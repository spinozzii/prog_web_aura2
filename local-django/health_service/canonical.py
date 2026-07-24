import hashlib
import json

from .entity_schema import ENTITIES, ENTITY_ORDER


def canonicalize_entity(entity, rows):
    definition = ENTITIES[entity]
    field_names = [field["name"] for field in definition["fields"]]
    key_names = definition["key"]
    ordered_rows = sorted(rows, key=lambda row: tuple(row[name] for name in key_names))
    return "".join(
        json.dumps(
            {name: row[name] for name in field_names},
            ensure_ascii=False,
            separators=(",", ":"),
        ) + "\n"
        for row in ordered_rows
    )


def sha256_entity(entity, rows):
    return hashlib.sha256(canonicalize_entity(entity, rows).encode("utf-8")).hexdigest()


def canonicalize_dataset(entities):
    return "".join(
        json.dumps(
            {
                "entity": entity,
                "rowCount": entities[entity]["rowCount"],
                "digest": entities[entity]["digest"],
            },
            ensure_ascii=False,
            separators=(",", ":"),
        ) + "\n"
        for entity in ENTITY_ORDER
    )


def sha256_dataset(entities):
    return hashlib.sha256(canonicalize_dataset(entities).encode("utf-8")).hexdigest()


def canonicalize_patologia(rows):
    return canonicalize_entity("patologia", rows)


def sha256_patologia(rows):
    return sha256_entity("patologia", rows)
