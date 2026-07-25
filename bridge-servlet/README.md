# Servlet Java intermedia

## Struttura

- `core`: contratto salute privo di dipendenze Servlet;
- `tomcat9`: adattatore sottile `javax.servlet`, Java 8;
- `tomcat11`: adattatore sottile `jakarta.servlet`, Java 17.

Entrambi gli adattatori espongono `GET /health` e restituiscono:

```json
{"apiVersion":"1.0","service":"bridge-servlet","status":"ok"}
```

Le API Servlet sono dipendenze `provided`, fissate rispettivamente a Servlet
4.0.1 e 6.1.0: servono alla costruzione degli artefatti, non alla macchina del
docente, che riceverà WAR precompilati in T09. Il test del core, privo di
Maven, viene eseguito con `tests/run-health-contracts.ps1`.

Entrambi gli adattatori espongono anche `POST /api/v1/migrations` e
`GET /api/v1/migrations/{migrationId}`. L'endpoint `POST` accetta `{}` oppure
un oggetto con `apiVersion` e un `migrationId` UUID canonico; l'endpoint `GET`
propaga lo stato e i checkpoint persistenti validati. Il core Java 8:

1. legge manifest ed export PHP;
2. valida lo schema condiviso, l'ordine delle otto entità, cursori, chiavi
   composte, conteggi, digest e `datasetId`;
3. apre o riprende la migrazione dallo stato confermato da Django;
4. inoltra e finalizza i lotti Django un'entità alla volta;
5. ritenta soltanto operazioni idempotenti per errori temporanei ammessi;
6. rilegge il manifest prima di restituire il riepilogo verificato.

Configurazione d'ambiente obbligatoria:

- `REMOTE_API_URL`, `LOCAL_API_URL`;
- `REMOTE_API_SECRET`, `LOCAL_API_SECRET`, `BRIDGE_API_SECRET`.

Sono facoltativi `BRIDGE_BATCH_SIZE`, `BRIDGE_CONNECT_TIMEOUT_MS`,
`BRIDGE_READ_TIMEOUT_MS`, `BRIDGE_MAX_RETRIES` (predefinito `2`, massimo `5`)
e `BRIDGE_RETRY_DELAY_MS` (predefinito `100`, massimo `10000` millisecondi).
Nessun segreto è memorizzato nel WAR.
