import hashlib
import json


def canonicalize_patologia(rows):
    ordered_rows = sorted(rows, key=lambda row: row["cod"])
    return "".join(
        json.dumps(
            {"cod": row["cod"], "nome": row["nome"], "criticita": row["criticita"]},
            ensure_ascii=False,
            separators=(",", ":"),
        ) + "\n"
        for row in ordered_rows
    )


def sha256_patologia(rows):
    return hashlib.sha256(canonicalize_patologia(rows).encode("utf-8")).hexdigest()
