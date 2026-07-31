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
- `GET /api/v1/export/{entity}?datasetId=...&limit=...&cursor=...`.

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
- `REMOTE_CURSOR_TTL_SECONDS`, facoltativo, predefinito a 900 secondi;
- `REMOTE_DB_CONNECT_TIMEOUT_SECONDS`, facoltativo, predefinito a 3 secondi,
  ammesso da 1 a 30;
- `REMOTE_DB_QUERY_TIMEOUT_SECONDS`, facoltativo, predefinito a 8 secondi,
  ammesso da 1 a 120.

I valori timeout devono essere interi ASCII positivi negli intervalli indicati;
una configurazione vuota, con spazi, decimali o fuori limite viene rifiutata
senza mostrare DSN, credenziali o query. `PDO::ATTR_TIMEOUT` limita la fase di
connessione e non l'esecuzione SQL. Per ogni `SELECT`, dopo aver rilevato
driver e versione, il servizio applica invece il limite nativo verificato:
`SET STATEMENT max_statement_time=... FOR SELECT` su MariaDB 10.1.1+ oppure
l'hint `MAX_EXECUTION_TIME` su MySQL 5.7.8+. Una versione non riconosciuta
fallisce in sicurezza con `SOURCE_TIMEOUT_UNSUPPORTED`; non vengono inviati
comandi SQL ipotetici alla sorgente.

Il timeout PHP o del web server è un terzo limite indipendente, configurato
dall'hosting. Deve essere maggiore del limite query e non viene usato come
sostituto del timeout PDO o del limite MySQL/MariaDB.

La sorgente di produzione usa soltanto PDO e query `SELECT` preparate sulle
tabelle in whitelist. La paginazione usa l'intera chiave primaria, inclusa la
tupla delle chiavi composte; il cursore opaco contiene la tupla tipizzata ed è
autenticato con HMAC. La sorgente fixture vive sotto `tests` e non viene
caricata dal front controller.

La scadenza limita l'uso ordinario del cursore. Un export già autenticato può
però riprendere un checkpoint persistito anche dopo la scadenza nominale:
firma HMAC, entità e `datasetId` devono restare validi e il cursore originale
viene inoltrato invariato a Django. In questo modo un riavvio tardivo non
invalida il checkpoint autorevole.

`datasetId` è obbligatorio per l'export. Alla prima pagina di ogni entità il
servizio ricalcola l'identità globale e rifiuta con `DATASET_CHANGED` una
sorgente diversa dal manifest fissato. Le pagine successive usano il cursore
HMAC già legato a entità e dataset, evitando scansioni globali ripetute; prima
del completamento l'orchestratore rilegge comunque il manifest. Il servizio
resta in sola lettura.

Non è richiesto Composer. I test isolati richiedono PHP CLI:

```text
php tests/HealthResponseTest.php
php tests/PatologiaCanonicalizerTest.php
php tests/PatologiaApiTest.php
php tests/PdoTimeoutPolicyTest.php
php tests/PdoTimeoutIntegrationTest.php
```

L'ultimo test mostra `SKIP` salvo quando `RUN_PDO_TIMEOUT_INTEGRATION=1` e un
MariaDB/MySQL di collaudo sono configurati esplicitamente; non usa mai la
sorgente reale per provocare una query lenta.

Il runner condiviso avvia anche un server PHP temporaneo senza opzione
`router` e verifica via HTTP `GET /health`, incluso il Content-Type.
