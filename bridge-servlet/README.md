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

Entrambi gli adattatori espongono anche `POST /api/v1/migrations`. L'endpoint
accetta `{}` oppure un oggetto con `apiVersion` e un `migrationId` UUID
canonico. Il core Java 8:

1. legge manifest ed export PHP;
2. valida lo schema condiviso, l'ordine delle otto entità, cursori, chiavi
   composte, conteggi, digest e `datasetId`;
3. inoltra e finalizza i lotti Django un'entità alla volta;
4. restituisce il riepilogo verificato per entità e aggregato.

Configurazione d'ambiente obbligatoria:

- `REMOTE_API_URL`, `LOCAL_API_URL`;
- `REMOTE_API_SECRET`, `LOCAL_API_SECRET`, `BRIDGE_API_SECRET`.

Sono facoltativi `BRIDGE_BATCH_SIZE`, `BRIDGE_CONNECT_TIMEOUT_MS` e
`BRIDGE_READ_TIMEOUT_MS`. Nessun segreto è memorizzato nel WAR.
