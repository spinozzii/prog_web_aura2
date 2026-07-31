import re
from dataclasses import dataclass

from django.core.exceptions import ImproperlyConfigured


_INTEGER = re.compile(r"[1-9][0-9]*\Z", re.ASCII)


def _read_integer(environment, name, default, minimum, maximum):
    raw = environment.get(name)
    if raw is None:
        return default
    if not isinstance(raw, str) or _INTEGER.fullmatch(raw) is None:
        raise ImproperlyConfigured(f"{name} deve essere un intero valido.")
    value = int(raw)
    if value < minimum or value > maximum:
        raise ImproperlyConfigured(
            f"{name} deve essere compreso tra {minimum} e {maximum}."
        )
    return value


@dataclass(frozen=True)
class PostgresTimeouts:
    connect_seconds: int
    lock_ms: int
    statement_ms: int
    idle_transaction_ms: int

    @classmethod
    def from_environment(cls, environment):
        return cls(
            connect_seconds=_read_integer(
                environment, "POSTGRES_CONNECT_TIMEOUT_SECONDS", 10, 1, 60
            ),
            lock_ms=_read_integer(
                environment, "POSTGRES_LOCK_TIMEOUT_MS", 10_000, 100, 120_000
            ),
            statement_ms=_read_integer(
                environment,
                "POSTGRES_STATEMENT_TIMEOUT_MS",
                120_000,
                1_000,
                600_000,
            ),
            idle_transaction_ms=_read_integer(
                environment,
                "POSTGRES_IDLE_TRANSACTION_TIMEOUT_MS",
                120_000,
                1_000,
                600_000,
            ),
        )

    def django_options(self):
        return {
            "connect_timeout": self.connect_seconds,
            "options": (
                f"-c lock_timeout={self.lock_ms} "
                f"-c statement_timeout={self.statement_ms} "
                "-c idle_in_transaction_session_timeout="
                f"{self.idle_transaction_ms}"
            ),
        }
