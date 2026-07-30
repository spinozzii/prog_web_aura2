#!/usr/bin/env python3
"""Loopback-only remote API used by the offline installation smoke test."""

from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import parse_qs, urlsplit


API_VERSION = "1.0"
MAX_BATCH_SIZE = 100
DEFAULT_BATCH_SIZE = 50
CURSOR_CONTEXT = b"drive-aura-offline-cursor-v1\n"
CURSOR_PATTERN = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$")
ENTITY_PATTERN = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
DATASET_PATTERN = re.compile(r"^[0-9a-f]{64}$")
AUTH_PATTERN = re.compile(r"^Bearer[ \t]+([^\r\n]+)$", re.IGNORECASE)


class ApiError(Exception):
    """An expected, client-safe API error."""

    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def _compact_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def _canonical_bytes(rows: list[dict[str, Any]], fields: tuple[str, ...]) -> bytes:
    if not rows:
        return b""
    return b"".join(
        _compact_json({field: row[field] for field in fields}) + b"\n"
        for row in rows
    )


def _sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _base64url_encode(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def _base64url_decode(value: str) -> bytes:
    if not value or not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise ValueError("invalid base64url")
    if len(value) % 4 == 1:
        raise ValueError("invalid base64url")
    raw = base64.urlsafe_b64decode(value + ("=" * (-len(value) % 4)))
    if _base64url_encode(raw) != value:
        raise ValueError("non-canonical base64url")
    return raw


@dataclass(frozen=True)
class EntityData:
    name: str
    fields: tuple[str, ...]
    key: tuple[str, ...]
    rows: tuple[dict[str, Any], ...]
    digest: str


class FixtureDataset:
    """Validated, ordered in-memory view of the shared synthetic fixture."""

    def __init__(self, fixture_path: Path, schema_path: Path) -> None:
        fixture = self._load_json(fixture_path, "fixture")
        schema = self._load_json(schema_path, "schema")
        if fixture.get("apiVersion") != API_VERSION:
            raise ValueError("La fixture usa una versione API incompatibile.")
        if schema.get("apiVersion") != API_VERSION:
            raise ValueError("Lo schema usa una versione API incompatibile.")

        raw_order = schema.get("entityOrder")
        raw_schemas = schema.get("entities")
        rows_by_entity = fixture.get("rowsByEntity")
        if (
            not isinstance(raw_order, list)
            or not raw_order
            or not isinstance(raw_schemas, dict)
            or not isinstance(rows_by_entity, dict)
            or set(raw_order) != set(raw_schemas)
            or set(raw_order) != set(rows_by_entity)
        ):
            raise ValueError("Schema e fixture non descrivono le stesse entita.")

        entities: dict[str, EntityData] = {}
        descriptors: list[dict[str, Any]] = []
        for name in raw_order:
            if not isinstance(name, str) or not ENTITY_PATTERN.fullmatch(name):
                raise ValueError("Nome entita non valido nello schema.")
            entity_schema = raw_schemas[name]
            raw_fields = entity_schema.get("fields")
            raw_key = entity_schema.get("key")
            raw_rows = rows_by_entity[name]
            if (
                not isinstance(raw_fields, list)
                or not isinstance(raw_key, list)
                or not isinstance(raw_rows, list)
            ):
                raise ValueError(f"Schema o righe non validi per {name}.")

            fields = tuple(field.get("name") for field in raw_fields)
            key = tuple(raw_key)
            if (
                not fields
                or any(not isinstance(field, str) for field in fields)
                or not key
                or any(field not in fields for field in key)
                or len(set(fields)) != len(fields)
            ):
                raise ValueError(f"Campi o chiave non validi per {name}.")

            rows: list[dict[str, Any]] = []
            for raw_row in raw_rows:
                if not isinstance(raw_row, dict) or set(raw_row) != set(fields):
                    raise ValueError(f"Riga non conforme allo schema per {name}.")
                rows.append({field: raw_row[field] for field in fields})
            rows.sort(key=lambda row: tuple(row[field] for field in key))
            keys = [tuple(row[field] for field in key) for row in rows]
            if len(keys) != len(set(keys)):
                raise ValueError(f"Chiave duplicata nella fixture per {name}.")

            digest = _sha256(_canonical_bytes(rows, fields))
            entity = EntityData(name, fields, key, tuple(rows), digest)
            entities[name] = entity
            descriptors.append(
                {"entity": name, "rowCount": len(rows), "digest": digest}
            )

        canonical_dataset = b"".join(
            _compact_json(descriptor) + b"\n" for descriptor in descriptors
        )
        dataset_id = _sha256(canonical_dataset)
        expected_id = fixture.get("expectedDatasetId")
        if expected_id is not None and expected_id != dataset_id:
            raise ValueError("Il digest della fixture non coincide con il vettore atteso.")

        self.entity_order = tuple(raw_order)
        self.entities = entities
        self.descriptors = tuple(descriptors)
        self.dataset_id = dataset_id

    @staticmethod
    def _load_json(path: Path, label: str) -> dict[str, Any]:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise ValueError(f"Impossibile leggere {label}: {path}") from error
        if not isinstance(value, dict):
            raise ValueError(f"Il file {label} non contiene un oggetto JSON.")
        return value

    def manifest(self, generated_at: str) -> dict[str, Any]:
        return {
            "apiVersion": API_VERSION,
            "datasetId": self.dataset_id,
            "generatedAt": generated_at,
            "entityOrder": list(self.entity_order),
            "entities": [dict(descriptor) for descriptor in self.descriptors],
            "maxBatchSize": MAX_BATCH_SIZE,
        }


class CursorCodec:
    """HMAC cursor bound to dataset, entity and next row index."""

    def __init__(
        self,
        secret: str,
        ttl_seconds: int = 900,
        clock: Callable[[], float] = time.time,
    ) -> None:
        if not secret:
            raise ValueError("Il segreto dei cursori e vuoto.")
        if not 1 <= ttl_seconds <= 86400:
            raise ValueError("La durata dei cursori deve essere tra 1 e 86400 secondi.")
        self._secret = secret.encode("utf-8")
        self._ttl_seconds = ttl_seconds
        self._clock = clock

    def encode(self, dataset_id: str, entity: str, index: int) -> str:
        payload = _compact_json(
            [1, dataset_id, entity, index, int(self._clock()) + self._ttl_seconds]
        )
        encoded = _base64url_encode(payload)
        signature = hmac.new(
            self._secret, CURSOR_CONTEXT + encoded.encode("ascii"), hashlib.sha256
        ).digest()
        return f"{encoded}.{_base64url_encode(signature)}"

    def decode(
        self, cursor: str, *, allow_expired: bool = False
    ) -> tuple[str, str, int]:
        try:
            if len(cursor) > 1024 or not CURSOR_PATTERN.fullmatch(cursor):
                raise ValueError("invalid cursor syntax")
            encoded, encoded_signature = cursor.split(".", 1)
            signature = _base64url_decode(encoded_signature)
            expected = hmac.new(
                self._secret,
                CURSOR_CONTEXT + encoded.encode("ascii"),
                hashlib.sha256,
            ).digest()
            if len(signature) != 32 or not hmac.compare_digest(signature, expected):
                raise ValueError("invalid cursor signature")
            payload = json.loads(_base64url_decode(encoded))
            if (
                not isinstance(payload, list)
                or len(payload) != 5
                or payload[0] != 1
                or not isinstance(payload[1], str)
                or not DATASET_PATTERN.fullmatch(payload[1])
                or not isinstance(payload[2], str)
                or not ENTITY_PATTERN.fullmatch(payload[2])
                or type(payload[3]) is not int
                or payload[3] < 0
                or type(payload[4]) is not int
                or payload[4] < 1
                or (not allow_expired and payload[4] <= int(self._clock()))
            ):
                raise ValueError("invalid cursor payload")
            return payload[1], payload[2], payload[3]
        except (ValueError, TypeError, json.JSONDecodeError, UnicodeError) as error:
            raise ApiError(400, "INVALID_CURSOR", "Il cursore non e valido.") from error


class OfflineRemoteServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(
        self,
        server_address: tuple[str, int],
        dataset: FixtureDataset,
        api_secret: str,
        cursor_codec: CursorCodec,
    ) -> None:
        if not api_secret:
            raise ValueError("REMOTE_API_SECRET non e configurato.")
        self.dataset = dataset
        self.api_secret = api_secret
        self.cursor_codec = cursor_codec
        self.generated_at = (
            datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        )
        super().__init__(server_address, OfflineRemoteHandler)


class OfflineRemoteHandler(BaseHTTPRequestHandler):
    """Exact remote API surface needed by the Java migration orchestrator."""

    server: OfflineRemoteServer
    protocol_version = "HTTP/1.1"

    def log_message(self, _format: str, *args: object) -> None:
        # Deliberately silent: neither authorization headers nor fixture payloads
        # belong in installation logs.
        return

    def version_string(self) -> str:
        return "DriveAuraOfflineMock"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        try:
            parsed = urlsplit(self.path)
            if parsed.path == "/health":
                if parsed.query:
                    raise ApiError(400, "INVALID_REQUEST", "La richiesta non e valida.")
                self._json(
                    200,
                    {
                        "apiVersion": API_VERSION,
                        "service": "remote-php",
                        "status": "ok",
                    },
                )
                return

            self._authorize()
            if parsed.path == "/api/v1/manifest":
                if parsed.query:
                    raise ApiError(400, "INVALID_REQUEST", "La richiesta non e valida.")
                self._json(200, self.server.dataset.manifest(self.server.generated_at))
                return

            prefix = "/api/v1/export/"
            if parsed.path.startswith(prefix):
                self._export(parsed.path[len(prefix) :], parsed.query)
                return
            raise ApiError(404, "NOT_FOUND", "Risorsa non trovata.")
        except ApiError as error:
            self._error(error)
        except Exception:
            self._error(ApiError(500, "INTERNAL_ERROR", "Errore interno del servizio remoto."))

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self._error(ApiError(405, "METHOD_NOT_ALLOWED", "Metodo non consentito."))

    def _authorize(self) -> None:
        authorization = self.headers.get("Authorization", "")
        match = AUTH_PATTERN.fullmatch(authorization)
        if match is None or not hmac.compare_digest(
            match.group(1), self.server.api_secret
        ):
            raise ApiError(401, "UNAUTHORIZED", "Autenticazione richiesta.")

    def _export(self, entity_name: str, raw_query: str) -> None:
        if (
            not ENTITY_PATTERN.fullmatch(entity_name)
            or entity_name not in self.server.dataset.entities
        ):
            raise ApiError(400, "INVALID_ENTITY", "Entita non ammessa.")
        try:
            query = parse_qs(raw_query, keep_blank_values=True, strict_parsing=True)
        except ValueError as error:
            raise ApiError(400, "INVALID_REQUEST", "La richiesta non e valida.") from error
        if any(
            name not in {"datasetId", "limit", "cursor"} or len(values) != 1
            for name, values in query.items()
        ):
            raise ApiError(400, "INVALID_REQUEST", "La richiesta non e valida.")

        dataset_id = query.get("datasetId", [None])[0]
        if not isinstance(dataset_id, str) or not DATASET_PATTERN.fullmatch(dataset_id):
            raise ApiError(400, "INVALID_DATASET", "Il dataset non e valido.")
        if dataset_id != self.server.dataset.dataset_id:
            raise ApiError(409, "DATASET_CHANGED", "Il dataset remoto e cambiato.")

        raw_limit = query.get("limit", [str(DEFAULT_BATCH_SIZE)])[0]
        if not re.fullmatch(r"[1-9][0-9]*", raw_limit):
            raise ApiError(400, "INVALID_LIMIT", "Il limite non e valido.")
        limit = int(raw_limit)
        if limit > MAX_BATCH_SIZE:
            raise ApiError(400, "INVALID_LIMIT", "Il limite supera il massimo consentito.")

        requested_cursor = query.get("cursor", [None])[0]
        index = 0
        if requested_cursor is not None:
            if requested_cursor == "":
                raise ApiError(400, "INVALID_CURSOR", "Il cursore non e valido.")
            cursor_dataset, cursor_entity, index = self.server.cursor_codec.decode(
                requested_cursor,
                allow_expired=True,
            )
            if cursor_dataset != dataset_id:
                raise ApiError(409, "DATASET_CHANGED", "Il dataset remoto e cambiato.")
            if cursor_entity != entity_name:
                raise ApiError(400, "INVALID_CURSOR", "Il cursore non e valido.")

        entity = self.server.dataset.entities[entity_name]
        if index > len(entity.rows):
            raise ApiError(400, "INVALID_CURSOR", "Il cursore non e valido.")
        end = min(index + limit, len(entity.rows))
        rows = [dict(row) for row in entity.rows[index:end]]
        has_more = end < len(entity.rows)
        next_cursor = (
            self.server.cursor_codec.encode(dataset_id, entity_name, end)
            if has_more
            else None
        )
        self._json(
            200,
            {
                "apiVersion": API_VERSION,
                "datasetId": dataset_id,
                "entity": entity_name,
                "cursor": requested_cursor,
                "nextCursor": next_cursor,
                "hasMore": has_more,
                "rowCount": len(rows),
                "rows": rows,
                "digest": _sha256(_canonical_bytes(rows, entity.fields)),
            },
        )

    def _error(self, error: ApiError) -> None:
        self._json(
            error.status,
            {
                "apiVersion": API_VERSION,
                "error": {"code": error.code, "message": error.message},
            },
        )

    def _json(self, status: int, body: dict[str, Any]) -> None:
        payload = _compact_json(body)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)


def _default_file(*relative_candidates: str) -> Path:
    script = Path(__file__).resolve()
    for parent in script.parents:
        for relative in relative_candidates:
            candidate = parent / relative
            if candidate.is_file():
                return candidate
    raise ValueError(
        "File condiviso non trovato; specificare il percorso esplicitamente."
    )


def create_server(
    *,
    port: int,
    api_secret: str,
    cursor_secret: str,
    fixture_path: Path,
    schema_path: Path,
    cursor_ttl: int = 900,
    clock: Callable[[], float] = time.time,
) -> OfflineRemoteServer:
    dataset = FixtureDataset(fixture_path, schema_path)
    codec = CursorCodec(cursor_secret, cursor_ttl, clock)
    return OfflineRemoteServer(("127.0.0.1", port), dataset, api_secret, codec)


def _arguments(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sorgente sintetica loopback per la verifica offline Drive Aura."
    )
    parser.add_argument("--port", type=int, default=18081)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--schema", type=Path)
    parser.add_argument("--cursor-ttl", type=int, default=900)
    args = parser.parse_args(argv)
    if not 0 <= args.port <= 65535:
        parser.error("--port deve essere compreso tra 0 e 65535")
    return args


def main(argv: list[str] | None = None) -> int:
    args = _arguments(argv)
    try:
        fixture = args.fixture or _default_file(
            "source/tests/fixtures/t03-dataset.json",
            "tests/fixtures/t03-dataset.json",
        )
        schema = args.schema or _default_file(
            "source/shared/entity-schema.json",
            "shared/entity-schema.json",
        )
        api_secret = os.environ.get("REMOTE_API_SECRET", "")
        cursor_secret = os.environ.get("REMOTE_CURSOR_SECRET", api_secret)
        server = create_server(
            port=args.port,
            api_secret=api_secret,
            cursor_secret=cursor_secret,
            fixture_path=fixture,
            schema_path=schema,
            cursor_ttl=args.cursor_ttl,
        )
    except (OSError, ValueError) as error:
        print(f"ERRORE: {error}", file=sys.stderr)
        return 2

    host, port = server.server_address
    print(f"READY {host}:{port}", flush=True)
    try:
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
