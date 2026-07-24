# Servizio Django locale

## Servizio disponibile

Il servizio usa Django 5.2.16 e `psycopg[binary]` 3.3.4 su Python 3.12.
`GET /health` restituisce:

```json
{"apiVersion":"1.0","service":"local-django","status":"ok"}
```

La risposta usa `application/json; charset=utf-8`. In un ambiente Python 3.12
con dipendenze installate, il test è:

```text
python manage.py test health_service
```

Le API protette sono:

- `POST /api/v1/migrations/{migrationId}/batches`;
- `POST /api/v1/migrations/{migrationId}/finalize`;
- `GET /api/v1/migrations/{migrationId}`.

Persistono `patologia`, `migration_run` e `migration_batch` in PostgreSQL.
Configurare `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_HOST`, `POSTGRES_PORT`, `LOCAL_API_SECRET` e
`DJANGO_SECRET_KEY`, quindi applicare la migrazione:

```text
python manage.py migrate
```

`DJANGO_TEST_SQLITE=1` è ammesso esclusivamente dal runner isolato: non
costituisce una prova PostgreSQL.
