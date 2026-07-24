# Verifica T03 - verticale completa

## Scopo

Questa procedura verifica il percorso reale:

```text
MariaDB/MySQL -> PHP/PDO -> Tomcat/servlet -> Django -> PostgreSQL
```

Usa la fixture controllata T03 e non legge o modifica Progetto 1, non
distribuisce su Altervista e non usa il futuro dataset massivo.

## Preparazione

La sorgente si prepara in un database MariaDB di prova già selezionato
caricando:

```text
database/t03-fixture-mariadb.sql
```

Il file crea le otto tabelle e 22 righe complessive coerenti con
`tests/fixtures/t03-dataset.json`. Il servizio PHP richiede nell'ambiente:

```text
REMOTE_DB_DSN
REMOTE_DB_USER
REMOTE_DB_PASSWORD
REMOTE_API_SECRET
REMOTE_CURSOR_SECRET
```

Django richiede un database PostgreSQL vuoto e:

```text
DJANGO_SECRET_KEY
LOCAL_API_SECRET
POSTGRES_DB
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_HOST
POSTGRES_PORT
```

Applicare le migrazioni reali prima dell'avvio:

```powershell
python .\local-django\manage.py migrate --noinput
python .\local-django\manage.py runserver 127.0.0.1:8000 --noreload
```

Il processo Tomcat deve ricevere:

```text
REMOTE_API_URL
LOCAL_API_URL
REMOTE_API_SECRET
LOCAL_API_SECRET
BRIDGE_API_SECRET
```

Impostare inoltre `JAVA_HOME` o `JRE_HOME` quando non è già definito. Per
esercitare ogni confine di pagina della fixture è possibile usare
`BRIDGE_BATCH_SIZE=1`. I segreti restano esclusivamente nell'ambiente dei
processi.

## Test e build

Dalla radice:

```powershell
.\tests\run-health-contracts.ps1
mvn -f .\bridge-servlet\pom.xml clean package
```

Il runner esegue i vettori condivisi in PHP, Java core `--release 8` e
Python/Django. Senza un runtime o un test termina con errore; `-AllowPartial`
permette gli skip soltanto mostrando un riepilogo esplicito.

La build deve produrre:

```text
bridge-servlet/tomcat9/target/bridge-tomcat9-0.1.0.war
bridge-servlet/tomcat11/target/bridge-tomcat11-0.1.0.war
```

## Comando end-to-end

Dopo l'avvio di PHP, Django e del WAR appropriato:

```powershell
$env:BRIDGE_API_SECRET = '<segreto locale>'
.\scripts\verify-full-migration.ps1 `
  -RemoteBaseUrl 'http://127.0.0.1:8081' `
  -LocalBaseUrl 'http://127.0.0.1:8000' `
  -BridgeBaseUrl 'http://127.0.0.1:8080/bridge' `
  -MigrationId '11111111-1111-4111-8111-111111111111'
```

Il comando verifica i tre `/health`, avvia la migrazione e accetta soltanto
un risultato `completed` con tutte le otto entità nell'ordine contrattuale,
digest validi e verifica aggregata positiva. `-Repeat` rilancia lo stesso
identificativo sul medesimo WAR; lo stesso `MigrationId` può anche essere
usato dopo avere sostituito il WAR per provare l'altro adattatore.

## Esito osservato il 24 luglio 2026

Runtime portabili usati:

- MariaDB 12.3.2;
- PHP 8.3.32 con `pdo_mysql`;
- Java 23, core compilato con `--release 8`;
- Tomcat 11.0.24 e Tomcat 9.0.120;
- Python 3.12.10, Django 5.2.16 e psycopg 3.3.4;
- PostgreSQL 18.4.

Verifiche isolate:

- runner rigoroso completo finale: `4,897 s`;
- 25 test Django: tutti superati; `manage.py check` senza problemi;
- `makemigrations --check --dry-run`: nessuna migrazione mancante;
- `mvn clean package`: `5,395 s` di tempo Maven;
- WAR Tomcat 9: `57.405` byte;
- WAR Tomcat 11: `57.422` byte;
- runner senza runtime: errore; con `-AllowPartial`: tre skip e riepilogo.

Il manifest PHP letto da MariaDB ha restituito il `datasetId` atteso:

```text
1994520ec6762723e7c1b32a9d8b40d8f4028f2c137a0aaa950298da680418a7
```

Il primo passaggio, attraverso Tomcat 11 e con lotti da una riga, ha
finalizzato 22 righe e 22 lotti in `2,643 s`. La query diretta PostgreSQL ha
confermato:

| Entità | Righe |
|---|---:|
| `cittadino` | 3 |
| `patologia` | 4 |
| `patologia_cronica` | 2 |
| `patologia_mortale` | 2 |
| `ospedale` | 2 |
| `ricovero` | 3 |
| `patologia_ricovero` | 4 |
| `progressivo_ricovero` | 2 |

Sono risultati nulli:

- duplicati delle due PK composte;
- FK orfane;
- direttori sanitari duplicati;
- ricoveri senza patologia;
- ospedali senza progressivo;
- progressivi diversi da `MAX(cod) + 1`.

PostgreSQL ha conservato le date civili, i costi `0.00`, `1234.50` e `99.99`,
l'accento UTF-8 e i caratteri sottoposti a escape. Il registro conteneva otto
run `completed`, 22 lotti e un solo `datasetId`.

Tomcat 11 è stato quindi arrestato e lo stesso `migrationId` è stato
rilanciato attraverso il WAR Tomcat 9. Il secondo passaggio ha restituito
ancora 22 righe e 22 lotti in `2,027 s`; i conteggi PostgreSQL sono rimasti
otto run, 22 lotti e 22 righe di dominio, dimostrando il rilancio idempotente.
Tutti i processi e le porte temporanee sono stati infine arrestati.

## Limiti

La prova è end-to-end reale ma usa la fixture piccola e runtime portabili
temporanei. Non sostituisce:

- la migrazione del dataset massivo del Progetto 1, riservata a T08;
- l'installatore e la prova pulita entro cinque minuti, riservati a T09;
- la distribuzione remota su Altervista.
