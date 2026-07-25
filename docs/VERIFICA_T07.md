# Verifica T07 - resilienza e dataset massivo

## Scopo

Questa verifica copre il percorso reale completo:

```text
MariaDB -> PHP/PDO -> servlet Java/Tomcat -> Django -> PostgreSQL
```

La sorgente è il dataset massivo del Progetto 1, usato in sola lettura e
ripristinato in un MariaDB portatile locale. I processi di prova hanno usato
soltanto segreti locali temporanei nell'ambiente; non è stato usato Altervista
e non sono stati registrati payload contenenti dati personali.

## Ambiente osservato

La prova del 25 luglio 2026 ha usato:

- MariaDB 12.3.2;
- PHP 8.3.32 con `pdo_mysql`;
- Java 23, con il core compilato per Java 8;
- Tomcat 11.0.24 e Tomcat 9.0.120;
- Python 3.12.10;
- Django 5.2.16 e psycopg 3.3.4;
- PostgreSQL 18.4.

I runtime erano installazioni portatili o locali di collaudo. Le porte erano
esposte soltanto su loopback.

## Sorgente consegnabile

Il pacchetto `database/drive-aura-51-source-v2.zip` contiene schema, seed,
manifest e istruzioni di ripristino, senza credenziali o configurazioni
locali. La dimensione osservata è 407.251 byte e il suo SHA-256 è:

```text
65204bc3b87b2e01a8a12f4a228dd93ad93d865348e1595efb901c6766d51d38
```

Il manifest del pacchetto fissa anche i file sorgente:

| File | Byte | SHA-256 |
|---|---:|---|
| `schema.sql` | 4.721 | `f1f162683f987a3f7fae98eba8ef830b03418baf57fe60026c406ca1797d2ada` |
| `seed_massivo.sql` | 2.469.421 | `0d90404c2cc754d1df5078c04b15a39c941f4070d0ba6f2664f54c3c78bc3972` |

`scripts/build-source-dump.ps1` rigenera il pacchetto e rifiuta una sorgente
con checksum o conteggi diversi. Le istruzioni complete sono in
`database/README_SOURCE_DUMP.md`.

## Identità, conteggi e digest

Il manifest PHP/PDO letto dal MariaDB massivo ha prodotto:

```text
datasetId = 75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39
```

Con lotti da 100 righe, il risultato atteso e osservato è:

| Entità | Righe | Lotti | SHA-256 canonico |
|---|---:|---:|---|
| `cittadino` | 3.200 | 32 | `308b6ef1e27d1d6087b52ed0168856b1d8420b1262c7a6bcf1b550c244f77f70` |
| `patologia` | 200 | 2 | `3173f4a9db15ebdf33223cba36f1860cdb730695716e428865868691bd420c27` |
| `patologia_cronica` | 143 | 2 | `17de8da61d5469e012058ce10d667e1e9a8442acab744bd9c64529814a927f2b` |
| `patologia_mortale` | 81 | 1 | `f96723546479571cd2b78d9ded97676443e561c7766b365c8e2517fbe244183d` |
| `ospedale` | 30 | 1 | `fa37fd03a5f4eeee9f02fb682b00053862cde09ccbf25fe1583635fc9fe04963` |
| `ricovero` | 12.000 | 120 | `ff1640d12101c1df35a3c484dd3c541e26bf58a68b63fc42c68aba5ac46105ca` |
| `patologia_ricovero` | 20.492 | 205 | `357043b4bf2e5fec2f461038b3bbce5e546a2d82f8b1d635105709504ea574ed` |
| `progressivo_ricovero` | 30 | 1 | `687077ef4989a82595a3570b388829bbcb1bf51813fc0dfeaf83eee9fac7d653` |
| **Totale** | **36.176** | **364** | |

Il comando Django:

```powershell
python .\local-django\manage.py audit_migration `
  --migration-id '<migrationId>'
```

ha riletto i record PostgreSQL, ricalcolato tutti gli otto digest e il
`datasetId` e li ha trovati uguali al manifest e al registro persistente.
L'output contiene soltanto metadati, conteggi e digest.

## Migrazione da PostgreSQL vuoto

La prima migrazione massiva è partita da un PostgreSQL vuoto ed è passata
attraverso il WAR Tomcat 11:

- stato finale: `completed`;
- righe: 36.176;
- lotti: 364;
- tempo restituito dall'orchestratore: 76,306 s;
- durata del comando completo, inclusi salute, manifest e stato: 79,610 s.

Tomcat 11 è stato quindi arrestato e lo stesso `migrationId` è stato rilanciato
attraverso il WAR Tomcat 9:

- stato finale: `completed`;
- tempo restituito dall'orchestratore: 5,743 s;
- durata del comando completo: 9,150 s;
- conteggi di dominio, otto registri di entità e 364 lotti invariati.

Il secondo passaggio ha quindi riusato lo stato già confermato senza inserire
duplicati.

## Interruzione, retry e ripresa

La prova di resilienza ha usato un secondo PostgreSQL vuoto, Tomcat 9 e due
proxy HTTP locali deterministici:

- una sola scadenza del timeout sul primo export remoto;
- una sola risposta HTTP 503 sul primo lotto inviato a Django.

Entrambi gli errori temporanei sono stati ritentati entro il limite
configurato. Prima dell'interruzione sono stati osservati 18.154 record e 183
lotti confermati. Un lotto già in volo è stato poi confermato da Django,
portando il checkpoint persistente effettivo a 18.254 record e 184 lotti.
Dopo l'arresto della servlet, il WAR Tomcat 9 è stato riavviato e ha ricevuto
lo stesso `migrationId`.

La ripresa è partita dal cursore sorgente e dalla sequenza persistiti, non
dall'inizio:

- stato finale: `completed`;
- righe finali: 36.176;
- lotti finali: 364;
- tempo restituito dall'orchestratore dopo il riavvio: 37,438 s;
- durata del comando completo di ripresa: 40,744 s.

Il proxy di collaudo consuma il corpo della richiesta quando inietta una
risposta e chiude esplicitamente la connessione. Questo evita di lasciare byte
HTTP pendenti o una connessione riutilizzabile in stato ambiguo. I suoi log
contengono soltanto metodo, percorso, modalità e numero del tentativo; non
contengono header, segreti o payload.

## Errori definitivi e idempotenza

Sono stati osservati anche i seguenti casi avversi:

| Caso | Esito osservato |
|---|---|
| Dataset modificato tra manifest ed export, migrazione con suffisso `004` | HTTP 409 definitivo, zero righe importate, nessun retry |
| Digest di pagina alterato, migrazione con suffisso `005` | HTTP 502 definitivo, zero righe importate, nessun retry |
| Primo invio di un lotto, migrazione con suffisso `006` | HTTP 201, `idempotent: false` |
| Ripetizione identica dello stesso lotto | HTTP 200, `idempotent: true` |
| Stessa identità di lotto con contenuto discordante | HTTP 409, `BATCH_CONFLICT` |

Il cambio dataset e il digest errato sono rimasti distinti dagli errori
temporanei e hanno marcato lo stato come non recuperabile. Il registro Django
ha conservato l'ultimo errore sintetico senza memorizzare il payload.

## Controlli PostgreSQL

`database/t07-verify-postgresql.sql` è stato eseguito sulla migrazione
completa. Ha confermato gli otto conteggi, stato globale `completed`, otto run
di entità e 364 lotti. Tutti i contatori di violazione erano zero:

- duplicati delle PK semplici o composte;
- FK orfane;
- direttori sanitari duplicati;
- criticità, durata o costo fuori dominio;
- ricoveri senza patologia;
- ospedali senza progressivo valido;
- progressivi diversi da `MAX(ricovero.cod) + 1`.

## Verifiche automatiche e artefatti

Sono stati rieseguiti:

```powershell
.\tests\run-health-contracts.ps1
python .\local-django\manage.py test health_service
python .\local-django\manage.py check
python .\local-django\manage.py makemigrations --check --dry-run
mvn -f .\bridge-servlet\pom.xml clean package
```

Il runner rigoroso si è concluso senza skip; i 33 test Django sono passati,
`check` non ha segnalato problemi e non risultano migrazioni mancanti. Maven
ha prodotto entrambi gli artefatti. Nell'ultima esecuzione il runner ha
richiesto 4,719 s, i test Django interni 0,624 s e Maven 4,879 s; i tempi
escludono l'avvio del processo PowerShell/Maven.

```text
bridge-servlet/tomcat9/target/bridge-tomcat9-0.1.0.war   71.356 byte
bridge-servlet/tomcat11/target/bridge-tomcat11-0.1.0.war 71.371 byte
```

## Limiti effettivi

La prova dimostra migrazione massiva, integrità, idempotenza e ripresa con
runtime locali portatili. Non comprende:

- distribuzione o misure su Altervista;
- installatore e dipendenze offline per il docente;
- prova di installazione pulita entro cinque minuti;
- manuale o documento PDF finale.

Questi elementi non fanno parte di T07. L'esito qui registrato non equivale
all'approvazione della revisione dell'attività.
