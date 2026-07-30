# Verifica T02.2 - verticale Patologia

## Scopo

Questa procedura verifica soltanto il percorso:

```text
PHP/PDO MySQL-MariaDB -> servlet Java -> Django -> PostgreSQL
```

Non distribuisce nulla su Altervista, non legge o modifica Progetto 1 e non
installa i componenti della consegna finale.

## Configurazione d'ambiente

Il servizio PHP richiede:

```text
REMOTE_DB_DSN
REMOTE_DB_USER
REMOTE_DB_PASSWORD
REMOTE_API_SECRET
REMOTE_CURSOR_SECRET
```

Il DSN deve iniziare con `mysql:`. La tabella sorgente è la whitelist fissa
`patologia(cod, nome, criticita)`.

Django richiede:

```text
DJANGO_SECRET_KEY
LOCAL_API_SECRET
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_HOST
POSTGRES_PORT
```

Con PostgreSQL raggiungibile:

```powershell
python local-django/manage.py migrate
python local-django/manage.py runserver 127.0.0.1:8000 --noreload
```

La servlet richiede:

```text
REMOTE_API_URL
LOCAL_API_URL
REMOTE_API_SECRET
LOCAL_API_SECRET
BRIDGE_API_SECRET
```

Sono facoltativi `BRIDGE_BATCH_SIZE`, `BRIDGE_CONNECT_TIMEOUT_MS` e
`BRIDGE_READ_TIMEOUT_MS`. Si distribuisce uno solo dei WAR, coerente con il
Tomcat disponibile:

- `bridge-servlet/tomcat9/target/bridge-tomcat9-0.1.0.war`;
- `bridge-servlet/tomcat11/target/bridge-tomcat11-0.1.0.war`.

I segreti devono restare nell'ambiente del processo e non vanno scritti nei
file del repository o nella riga di comando.

## Verifiche isolate e build

Da PowerShell, nella radice del progetto:

```powershell
.\tests\run-health-contracts.ps1
mvn -f .\bridge-servlet\pom.xml clean package
```

Il runner è rigoroso: se un runtime o un test manca termina con errore.
`-AllowPartial` consente gli skip e stampa il riepilogo esplicito. Nei test
Django isolati il runner usa il modulo dedicato
`health_service.test_settings`;
questo non è e non viene dichiarato come collaudo PostgreSQL.

## Verifica verticale

Dopo avere applicato le migrazioni Django, avviato i tre servizi e distribuito
il WAR:

```powershell
$env:BRIDGE_API_SECRET = '<segreto fornito fuori dal repository>'
.\scripts\verify-patologia-migration.ps1 `
  -RemoteBaseUrl 'http://127.0.0.1:8081' `
  -LocalBaseUrl 'http://127.0.0.1:8000' `
  -BridgeBaseUrl 'http://127.0.0.1:8080/bridge'
```

Il comando controlla i tre `/health`, avvia `POST /api/v1/migrations` sulla
servlet e accetta il risultato soltanto se stato, conteggio, digest e vincoli
sono stati finalizzati positivamente da Django/PostgreSQL.

L'endpoint di avvio accetta `{}` oppure:

```json
{"apiVersion":"1.0","migrationId":"11111111-1111-4111-8111-111111111111"}
```

Fornire lo stesso `migrationId` permette di verificare l'idempotenza dei lotti
già confermati; contenuti diversi con la stessa identità producono conflitto.

## Esito osservato

Il 24 luglio 2026 sono stati eseguiti:

- runner rigoroso completo con Java 23/core `--release 8`, PHP 8.3.32 e
  Python 3.12.10 con Django 5.2.16;
- 18 test Django isolati, inclusi JSON rigoroso, indisponibilità database,
  rollback, idempotenza, conflitti, finalizzazione incompleta e sequenza vuota;
- `mvn clean package`, con entrambi i WAR prodotti;
- controllo della modalità rigorosa senza runtime e di `-AllowPartial` con
  riepilogo esplicito.

La prova verticale reale è stata eseguita con server portabili, senza
installazione di sistema:

- MariaDB 12.3.2 con tre righe controllate e accesso PHP tramite
  `pdo_mysql`;
- Tomcat 11.0.24 con il WAR `jakarta`;
- Tomcat 9.0.120 con il WAR `javax`;
- PostgreSQL 18.4;
- `BRIDGE_BATCH_SIZE=1`, quindi tre pagine e tre lotti osservati.

Il primo avvio, attraverso Tomcat 11, ha completato la migrazione
`439e224f-5687-414b-9c85-ad602e337d7b` con:

```text
rowCount=3
batchCount=3
digest=1a0c031432423ef5812f87e7c2e7b712c87c95538c935bd2f2e17b54c9e22612
status=completed
```

La query diretta PostgreSQL ha confermato tre righe `patologia`, un solo
registro `migration_run`, tre sequenze `migration_batch` (`0`, `1`, `2`) e
criticità minima/massima `1`/`5`. Lo stesso `migrationId` è stato rilanciato
prima sul medesimo adattatore e poi su Tomcat 9: entrambi i rilanci hanno
restituito `completed` e i conteggi sono rimasti `3/1/3`, confermando
l'idempotenza osservata.

Sono stati inoltre osservati `401` per Bearer errato su PHP e sulla servlet.
Al termine tutti i processi e le porte temporanee sono stati arrestati.

Questa è una verticale reale sui quattro livelli richiesti, ma usa un
MariaDB temporaneo con dati controllati: non è una distribuzione Altervista,
non coinvolge Progetto 1 e non sostituisce la futura prova sul dataset
massivo.
