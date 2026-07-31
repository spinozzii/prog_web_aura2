# Verifica T11 - audit finale

> Evidenza storica del 30 luglio 2026. Il candidato corrente e il verdetto
> aggiornato sono documentati in `docs/VERIFICA_T11_1.md`.

Data dell'audit: 30 luglio 2026.

## Esito

Il candidato soddisfa i requisiti verificabili localmente, il piano di test e
le linee guida originali del secondo progetto. Resta non verificata soltanto
la pubblicazione effettiva del PHP su Altervista, esclusa dall'autorizzazione
di T11 e indicata come tale nella checklist. T11 è pronto per la revisione
Work.

L'audit non ha distribuito il componente PHP su Altervista, non ha usato
credenziali remote, non ha inviato email e non ha creato tag o release.

## Ambito controllato

Sono stati riletti e confrontati:

- le 15 pagine delle linee guida originali;
- `docs/REQUISITI.md`, `docs/CHECKLIST_PROFESSORE.md` e
  `docs/PIANO_TEST.md`;
- codice PHP, core e adattatori Java, servizio Django e migrazioni;
- fixture, schema condiviso, dump massivo ed evidenze T02.2/T03/T07/T09;
- installer, verificatore, WAR, wheelhouse, configurazioni e archivio;
- manuale e documento delle scelte, sia come PDF esterni sia dentro lo ZIP.

Il percorso applicativo resta:

```text
PHP/PDO → servlet Java/Tomcat → Django → PostgreSQL
```

La servlet non contiene driver di database e non accede direttamente né a
MariaDB/MySQL né a PostgreSQL.

## Difetti trovati e corretti

La revisione statica ha rimosso i percorsi permissivi rimasti dalle verticali
iniziali:

- il servizio Django operativo richiede `DJANGO_SECRET_KEY` e PostgreSQL;
  SQLite è confinato a `health_service/test_settings.py`;
- importazione, finalizzazione e stato richiedono sempre l'inizializzazione
  globale e i checkpoint completi, senza percorso alternativo T02.2;
- il servizio PHP accetta in ripresa un cursore scaduto soltanto se HMAC,
  entità e dataset sono ancora validi; l'uso ordinario continua a rispettare
  la scadenza;
- la servlet accetta HTTP remoto soltanto su loopback, richiede HTTPS fuori
  loopback e vincola Django a un URL locale;
- risposte, log e configurazioni restano privi di segreti e payload completi.

### Errore Tomcat 11 del tentativo 002

Il tentativo `002` non era fermo nella readiness. Tomcat aveva fallito il
connettore prima di diventare pronto:

```text
Http11NioProtocol
  → NioEndpoint/Poller
  → WEPollSelectorImpl/PipeImpl
  → Unable to establish loopback connection
  → Invalid argument: connect
```

La causa osservata è l'apertura del selector NIO tramite la socket loopback
in questo ambiente Windows/AppX, non il WAR o la porta HTTP. Il configuratore
genera ora esplicitamente il connettore
`org.apache.coyote.http11.Http11Nio2Protocol`. I log finali dei due Tomcat
mostrano `http-nio2-127.0.0.1-*`, avvio, shutdown valido e nessuna ricorrenza
dell'errore loopback.

### PowerShell padre che restava appeso

Nel tentativo `002`, i processi figli rimasti attivi conservavano gli handle
di stdout/stderr. Inoltre, il fallback basato su CIM non era disponibile nel
contesto AppX e interrompeva la pulizia. Il processo PowerShell padre poteva
quindi restare in attesa anche dopo l'errore.

La correzione comprende:

- wrapper `.bat` con redirezione eseguita nel processo figlio e stdin `NUL`;
- avvio dei comandi esterni con Win32 `CreateProcess` sospeso e assegnazione
  preventiva a un Job Object con `KILL_ON_JOB_CLOSE`;
- output ed errore in file temporanei chiudibili, senza attesa illimitata su
  pipe asincrone;
- inventario processi via Toolhelp, senza dipendenza da CIM;
- arresto limitato alla radice registrata e ai suoi discendenti, dopo verifica
  di PID, percorso eseguibile e istante di creazione;
- cleanup in `finally`, code diagnostiche dei log e controllo finale delle
  porte;
- rifiuto operativo dei percorsi batch contenenti `%`, disattivazione
  esplicita della delayed expansion e quoting dei metacaratteri.

Il watchdog della verifica è 180 secondi per default, configurabile fra 60 e
240. Il collaudo esterno finale ha imposto 240 secondi, quindi resta sotto il
limite assoluto di cinque minuti. Readiness, comandi esterni, arresto Tomcat,
attesa ordinata e terminazione forzata hanno ciascuno una scadenza finita.

### Identità del processo e JSON

Un primo rilancio Tomcat 9 ha terminato correttamente entro 41,197 secondi con
exit code non zero, facendo emergere una race nel controllo del PID. Windows
PowerShell 5.1 poteva perdere i bit meno significativi dei tick di creazione
quando il valore `Int64`, maggiore di `2^53`, attraversava JSON.

I tick vengono ora salvati come testo decimale invariant e riconvertiti a
`Int64` per il confronto esatto. La regressione esegue un round-trip JSON
reale e verifica che il processo e il suo albero vengano riconosciuti e
arrestati senza possibilità di colpire un PID riutilizzato.

## Prove pulite offline finali

Il medesimo ZIP finale è stato estratto in una directory nuova con spazi.
Ogni prova ha creato un nuovo ambiente virtuale, due database PostgreSQL
dedicati e un `CATALINA_BASE` isolato. Proxy non raggiungibili, variabili pip
ostili, `--no-index` e `--require-hashes` hanno escluso il download.

Ambiente:

- Windows 11 e Windows PowerShell 5.1;
- Python 3.12.10 x64;
- Django 5.2.16 e psycopg 3.3.4 dalle sette wheel locali;
- Java 23.0.2;
- PostgreSQL 18.4 reale su loopback;
- Tomcat 9.0.120 e Tomcat 11.0.24.

| Prova | WAR | Tempo interno | Wall-clock | Esito |
|---|---|---:|---:|---|
| finale Tomcat 9 | `bridge-tomcat9.war` | 44,757 s | 45,619 s | PASS |
| finale Tomcat 11 | `bridge-tomcat11.war` | 45,504 s | 46,427 s | PASS |

Entrambe hanno verificato:

- integrità dei 109 payload;
- rilevamento dei quattro runtime;
- ambiente virtuale e installazione esclusivamente dalla wheelhouse;
- migrazioni Django su PostgreSQL;
- salute della sorgente contrattuale, della servlet e di Django;
- 22 righe in 22 lotti e dataset
  `1994520ec6762723e7c1b32a9d8b40d8f4028f2c137a0aaa950298da680418a7`;
- rilancio dello stesso `migrationId` senza duplicazioni;
- audit PostgreSQL finale;
- shutdown ordinato, rimozione di `processes.json` e zero listener sulle otto
  porte usate dalle due prove.

La sorgente loopback verifica il contratto remoto e la catena locale reale;
non viene presentata come PHP/PDO. La verticale PHP/PDO massiva resta la prova
reale osservata e ricalcolata nella sezione seguente.

## Test automatici e controlli statici

Esiti finali successivi all'ultima modifica:

- runner rigoroso: exit code `0`, 5,676 secondi; contratti Java, PHP e 25 test
  Django superati;
- runner senza runtime: exit code diverso da zero;
- runner senza runtime con `-AllowPartial`: exit code `0`, tre skip e
  riepilogo esplicito;
- mock remoto: 5 test superati in 0,570 secondi;
- installer: 27 casi superati, inclusi runtime mancanti o incompatibili,
  Tomcat non riconosciuto, PostgreSQL non raggiungibile, porta occupata,
  segreto mancante, wheel e archivio alterati, assenza di rete, avvio fallito,
  timeout, figlio orfano, rilascio handle, quoting e round-trip dell'identità;
- PHP: 18 file controllati con `php -l`, zero errori;
- Django/PostgreSQL: `check`, `makemigrations --check --dry-run` e
  `migrate --check` superati su PostgreSQL reale;
- Maven 3.9.16: `mvn clean package` superato in 4,619 secondi e produzione di
  entrambi i WAR;
- contenuto logico dei WAR ricostruiti uguale agli artefatti precompilati; i
  38 file del JAR core coincidono byte per byte al netto dei metadati ZIP;
- parser PowerShell 5.1 e `git diff --check`: nessun errore;
- revisione statica finale: nessun blocker in PHP, Java, Django o installer.

## Dataset massivo e resilienza

Il dump consegnato è byte-identico a quello della prova T07 e il suo checksum
è stato ricalcolato. Non è stata ripetuta la migrazione costosa già osservata;
sono state riesaminate le evidenze e ricalcolati dump, conteggi, digest e
vincoli.

Dataset:

```text
datasetId = 75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39
```

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

Le evidenze reali riconfermano:

- migrazione da PostgreSQL vuoto tramite Tomcat 11;
- rilancio idempotente tramite Tomcat 9;
- interruzione, checkpoint 18.254/184 e ripresa con lo stesso `migrationId`;
- retry limitati su timeout remoto e HTTP 503 Django;
- rifiuto definitivo di dataset cambiato e digest errato;
- duplicato identico idempotente e duplicato discordante `409`;
- zero violazioni di PK, FK, unicità, domini, associazioni e progressivi
  `MAX(cod) + 1`.

## Archivio e artefatti

Il pacchetto finale è riproducibile: due build consecutive hanno prodotto gli
stessi byte.

```text
dist/drive-aura-51-offline.zip
dimensione = 12.842.104 byte
SHA-256 = 0184e28030d54518778307efcc0f5f11d8f0c1ab11c540b4ce3aab1286e15bea
```

Audit:

- sidecar esterno coincidente;
- 111 entry totali, 109 payload e 110 righe di checksum;
- una sola radice, nessun duplicato o path traversal;
- tutti gli hash e le dimensioni del manifest interno coincidono;
- 79 file sorgente, 7 wheel, 2 WAR e 2 PDF;
- zero cache, log, `target`, runtime, ambiente virtuale, file IDE o file
  estraneo;
- scansione di 98 file testuali: zero credenziali, chiavi private, URL con
  password o percorsi locali ad alto rischio.

Artefatti principali:

| Artefatto | Byte | SHA-256 |
|---|---:|---|
| WAR Tomcat 9 | 71.638 | `0e73c03adc3e279f401a47e6a88cdbe711b7e902c75d9abea9cf77576335b97d` |
| WAR Tomcat 11 | 71.653 | `351be626e9977527a4444e5ec8806b7914c97cb2a4fd7dc30347e9416cba208b` |
| dump sorgente | 407.251 | `65204bc3b87b2e01a8a12f4a228dd93ad93d865348e1595efb901c6766d51d38` |
| manuale PDF | 105.128 | `044a319077888a56ce021b520277439314fc0fce88a624b82e8464340829e2c1` |
| scelte PDF | 98.110 | `350ee05ca081d86d9bfb9a2d0af095c03e141e5c1533016f0728a5dbf7a79428` |

## Verifica visiva PDF

Il manuale è A4, tre pagine; il documento delle scelte è A4, una pagina.
Tutte le quattro pagine sono state nuovamente renderizzate a 144 dpi e
ispezionate. Non sono presenti testo tagliato, sovrapposizioni, caratteri
corrotti, margini irregolari, pagine vuote o pagine superflue. I PDF non sono
cifrati e non contengono form o JavaScript.

Il manuale conserva correttamente i tempi storici T09:

- Tomcat 11: 43,290 secondi interni e 43,571 secondi wall-clock;
- Tomcat 9: 38,822 secondi.

## Consegna e limiti effettivi

`docs/CHECKLIST_PROFESSORE.md` è compilata con le evidenze disponibili.
Pubblicazione Altervista, indirizzi CC e accessibilità degli allegati restano
volutamente non selezionati perché non sono stati eseguiti.
`docs/BOZZA_EMAIL_CONSEGNA.md` contiene oggetto, scelta B, artefatti e
checksum.

Limiti dichiarati:

- nessuna distribuzione Altervista e nessuna prova con credenziali remote;
- la rete fisica non è stata disabilitata: la procedura è stata isolata con
  proxy non raggiungibili e installazione pip strettamente offline;
- i runtime portabili del collaudo non fanno parte della consegna;
- il collaudo rapido usa una sorgente contrattuale loopback; la prova
  PHP/PDO massiva è quella osservata in T07;
- email non inviata, tag e release remoti non creati.
