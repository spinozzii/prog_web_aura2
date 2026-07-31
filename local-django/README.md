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
python manage.py test health_service --settings health_service.test_settings
```

Le API protette sono:

- `POST /api/v1/migrations/{migrationId}`;
- `POST /api/v1/migrations/{migrationId}/batches`;
- `POST /api/v1/migrations/{migrationId}/finalize`;
- `POST /api/v1/migrations/{migrationId}/failure`;
- `GET /api/v1/migrations/{migrationId}`.

Persistono in PostgreSQL tutte le entità definite da
`shared/entity-schema.json`, con PK semplici e composte, FK, direttore
sanitario univoco e vincoli di dominio. `entity_migration_run` e
`entity_migration_batch` registrano separatamente ogni entità e lotto. Le
tabelle T02 `migration_run` e `migration_batch` restano soltanto nella storia
delle migrazioni; l'API finale usa un unico percorso con manifest globale,
checkpoint obbligatori e `DjangoEntityRepository`.

Configurare `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`,
`POSTGRES_HOST`, `POSTGRES_PORT`, `LOCAL_API_SECRET` e `DJANGO_SECRET_KEY`,
quindi applicare le migrazioni:

```text
python manage.py migrate
```

Le connessioni operative PostgreSQL applicano scadenze finite, configurabili
senza modificare il codice:

- `POSTGRES_CONNECT_TIMEOUT_SECONDS`: 10 secondi, intervallo 1-60;
- `POSTGRES_LOCK_TIMEOUT_MS`: 10000 ms, intervallo 100-120000;
- `POSTGRES_STATEMENT_TIMEOUT_MS`: 120000 ms, intervallo 1000-600000;
- `POSTGRES_IDLE_TRANSACTION_TIMEOUT_MS`: 120000 ms, intervallo
  1000-600000.

Sono accettati soltanto interi ASCII positivi negli intervalli indicati. I
limiti sono opzioni di sessione PostgreSQL 14-18: non alterano transazioni,
digest o checkpoint. Un timeout database produce una risposta pubblica 503
senza dettagli SQL; la transazione viene annullata e un successivo rilancio
può riprendere lo stesso `migrationId` dal checkpoint confermato.

Le impostazioni operative non contengono SQLite e falliscono se
`DJANGO_SECRET_KEY` manca. Il modulo `health_service.test_settings` usa
SQLite in memoria esclusivamente per i test isolati; non costituisce una
prova PostgreSQL.

La regressione reale del lock si abilita soltanto su un database di test
dedicato con `RUN_POSTGRES_LOCK_TEST=1`; usa un watchdog esterno e rilascia le
connessioni in ogni esito.

La finalizzazione segue l'ordine completo, ricalcola digest e `datasetId`,
controlla FK e unicità, richiede una patologia per ogni ricovero e verifica
ogni progressivo con `MAX(cod) + 1`.

Da T07 `migration_execution` conserva lo stato globale e ogni run di entità
conserva sequenza, cursori sorgente e indicazione `hasMore`. Lotto e checkpoint
avanzano atomicamente: Java, dopo un riavvio, può riprendere lo stesso
`migrationId` dal primo lotto non confermato. Gli stati sono `created`,
`running`, `interrupted`, `failed` e `completed`; l'errore resta sintetico.

Per verificare una migrazione senza stampare righe:

```text
python manage.py audit_migration --migration-id <migrationId>
```

Il comando ricalcola conteggi, digest, `datasetId` e invarianti PostgreSQL e
restituisce soltanto metadati JSON.
