# Servlet Java intermedia

## Struttura T01

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

Orchestrazione, HTTP remoto e inoltro a Django restano fuori dallo scope T01.
