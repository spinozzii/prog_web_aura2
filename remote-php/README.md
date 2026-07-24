# Servizio PHP remoto

## Responsabilità

- espone salute, manifest ed export a lotti;
- legge MySQL/MariaDB tramite PDO;
- resta compatibile con Altervista;
- non modifica i dati;
- autentica le richieste;
- applica whitelist e query preparate.

## Endpoint

Il front controller è `public/index.php`. La directory `public/health` e la
regola `public/.htaccess` fanno raggiungere `GET /health` su Apache compatibile
con Altervista, senza un router di sviluppo. La directory richiama soltanto il
front controller e permette lo stesso percorso con `php -S -t public`.

```json
{"apiVersion":"1.0","service":"remote-php","status":"ok"}
```

`GET /health` non richiede database. Le API di migrazione sono:

- `GET /api/v1/manifest`;
- `GET /api/v1/export/{entity}?limit=...&cursor=...`.

Le entità, i campi, i tipi e le chiavi sono caricati dalla whitelist
versionata `shared/entity-schema.json`. L'ordine del manifest è:
`cittadino`, `patologia`, `patologia_cronica`, `patologia_mortale`,
`ospedale`, `ricovero`, `patologia_ricovero`, `progressivo_ricovero`.

Richiedono `Authorization: Bearer ...`. La configurazione arriva soltanto
dall'ambiente:

- `REMOTE_DB_DSN`, con DSN `mysql:`; se manca `charset`, viene aggiunto
  `utf8mb4`;
- `REMOTE_DB_USER` e `REMOTE_DB_PASSWORD`;
- `REMOTE_API_SECRET`;
- `REMOTE_CURSOR_SECRET`;
- `REMOTE_CURSOR_TTL_SECONDS`, facoltativo, predefinito a 900 secondi.

La sorgente di produzione usa soltanto PDO e query `SELECT` preparate sulle
tabelle in whitelist. La paginazione usa l'intera chiave primaria, inclusa la
tupla delle chiavi composte; il cursore opaco contiene la tupla tipizzata ed è
autenticato con HMAC. La sorgente fixture vive sotto `tests` e non viene
caricata dal front controller.

Non è richiesto Composer. I test isolati richiedono PHP CLI:

```text
php tests/HealthResponseTest.php
php tests/PatologiaCanonicalizerTest.php
php tests/PatologiaApiTest.php
```

Il runner condiviso avvia anche un server PHP temporaneo senza opzione
`router` e verifica via HTTP `GET /health`, incluso il Content-Type.
