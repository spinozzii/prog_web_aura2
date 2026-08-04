# Verifica T11.1 - attese finite e consegnabilità

Data: 31 luglio 2026.

## Verdetto

**CONSEGNABILE** per tutti i requisiti verificabili localmente.

Non risultano attese indefinite conosciute nei percorsi operativi o di test.
Runner, test, database reali, installer, entrambi i WAR, pacchetto e PDF sono
stati verificati con scadenze esterne finite. L'unico requisito non osservato
nel suo ambiente definitivo è la pubblicazione PHP su Altervista, esclusa
dall'autorizzazione; il componente e le istruzioni restano predisposti.

Aggiornamento del 4 agosto 2026: la prova Altervista successivamente
autorizzata ha rilevato il blocco `SetEnv` documentato in
`docs/VERIFICA_ALTERVISTA.md`. Il verdetto sopra resta quindi limitato al
pacchetto e alle prove locali e non certifica il servizio remoto operativo.

## Correzioni dell'audit Work

| Rischio | Correzione ed evidenza |
|---|---|
| `WaitForExit()` illimitato | sostituito con attese da 2 s/300 ms e chiusura secondaria da 1,5 s; identità verificata prima del cleanup, `Dispose()` in `finally`; percorsi normale e timeout passano |
| processi esterni del runner | Java, PHP e Django passano dal wrapper limitato con Job Object; i due server PHP hanno readiness da 5 s e cleanup per PID, eseguibile e istante di creazione |
| PostgreSQL senza timeout | aggiunti limiti configurabili per connessione, lock, statement e transazione inattiva; valori non validi rifiutati all'avvio |
| PHP/PDO senza timeout | separati timeout di connessione e limite query; rilevamento fail-closed di MariaDB/MySQL, senza inviare sintassi non supportata |
| Maven con zero test | Surefire 3.5.4 esegue realmente i tre contratti del core e il modulo fallisce se non trova test |
| percorsi Windows lunghi | controllo preventivo con limite prudenziale 248 caratteri e indicazione `C:\DriveAura51`; nessuno spostamento o cancellazione automatica |
| traceback del probe sintetico | soppressi soltanto reset, abort e broken pipe attesi prima della richiesta HTTP; gli errori diversi restano visibili; regressione automatica superata |

Il parser MariaDB usa la versione immediatamente precedente a `-MariaDB`:
una stringa con suffisso di distribuzione non può più far scegliere per errore
la versione del sistema operativo.

## Timeout scelti

### Django/PostgreSQL 14-18

| Variabile | Default | Intervallo |
|---|---:|---:|
| `POSTGRES_CONNECT_TIMEOUT_SECONDS` | 10 s | 1-60 s |
| `POSTGRES_LOCK_TIMEOUT_MS` | 10000 ms | 100-120000 ms |
| `POSTGRES_STATEMENT_TIMEOUT_MS` | 120000 ms | 1000-600000 ms |
| `POSTGRES_IDLE_TRANSACTION_TIMEOUT_MS` | 120000 ms | 1000-600000 ms |

Sono ammessi soltanto interi ASCII positivi. I tre limiti server vengono
applicati come opzioni di sessione libpq; `connect_timeout` resta distinto.
Un `DatabaseError` produce 503 pubblico senza host, password, query o stack
trace. La transazione esegue rollback prima che il percorso di resilienza
registri un errore recuperabile.

### PHP/PDO

| Variabile | Default | Intervallo |
|---|---:|---:|
| `REMOTE_DB_CONNECT_TIMEOUT_SECONDS` | 3 s | 1-30 s |
| `REMOTE_DB_QUERY_TIMEOUT_SECONDS` | 8 s | 1-120 s |

`PDO::ATTR_TIMEOUT` limita soltanto la connessione. Il limite query è
`SET STATEMENT max_statement_time=... FOR SELECT` su MariaDB 10.1.1+ e
`MAX_EXECUTION_TIME` su MySQL 5.7.8+. Versioni o driver non riconosciuti
ricevono `SOURCE_TIMEOUT_UNSUPPORTED`. Il timeout PHP/web server è documentato
come terzo livello indipendente.

### Processi, HTTP e suite

- wrapper esterni: limiti individuali da 1 a 300 s e chiusura dell'intero Job
  Object in timeout;
- readiness dei contratti: 5 s; richieste HTTP singole: 2-60 s secondo il
  percorso;
- verifica installer: 180 s predefiniti, configurabili fra 60 e 240 s;
- prove pulite: watchdog esterno di 300 s;
- test lock PostgreSQL: watchdog esterno di 30 s e join interno massimo 5+2 s.

## Prove automatiche

| Controllo | Esito osservato |
|---|---|
| runner rigoroso | PASS nell'ultimo rilancio in 8,3 s wall-clock; Java, PHP e 29 test Django, con una sola integrazione PostgreSQL separata |
| runtime assenti, rigoroso | exit code 1 sul primo runtime mancante |
| runtime assenti, `-AllowPartial` | exit code 0, tre `SKIP` e riepilogo esplicito |
| PHP | 21 file superano `php -l`; cinque comandi test, quattro PASS e integrazione reale opt-in indicata come SKIP nel giro isolato |
| Django isolato | 29 test in 0,679 s, 28 PASS e una prova PostgreSQL opt-in |
| controlli Django | `check` senza problemi; `makemigrations --check --dry-run` senza modifiche |
| PostgreSQL reale | migrazioni 0001-0003 applicate su PostgreSQL 18.4; `migrate --check` PASS |
| Maven | `clean test`: 3 test, 0 errori; `clean package`: 3 test e due WAR |
| asserzione Java falsa temporanea | build non riuscita con 1 failure su 3; la copia temporanea è stata rimossa e il repository non è stato alterato |
| installer | 31 casi avversi PASS; ultimo rilancio in 11,8 s wall-clock |
| mock remoto | 6 test PASS in 0,640 s, inclusa la chiusura anticipata del probe senza traceback |

La prova PostgreSQL con `lock_timeout=500 ms` ha restituito 503 in 0,723 s
sotto watchdog: zero righe e zero lotti, sequenza/cursore invariati e stato
iniziale coerente. Dopo la registrazione recuperabile, lo stesso lotto è stato
ripreso una sola volta e lo stato è tornato `running` con checkpoint 1.

La prova PDO reale su MariaDB 12.3.2 ha interrotto `SELECT SLEEP(3)` in
1,005 s con limite di 1 s. Una connessione loopback irraggiungibile è terminata
entro la scadenza e la risposta pubblica non conteneva DSN, utente, password,
query o percorsi.

## Audit statico delle attese

La scansione ha incluso PowerShell, Python, PHP e Java, escludendo `target`,
cache, runtime e artefatti. La guardia AST analizza gli script operativi e di
test e fallisce su un `WaitForExit()` senza argomenti; non sono presenti
`Wait-Process`.

- i `while` PowerShell usano deadline UTC oppure uno stack che decresce;
- gli sleep sono fissi, dentro una deadline o dentro un processo figlio
  governato dal Job Object;
- i retry Java hanno `maxRetries` e timeout di connessione/lettura;
- i loop Java di parsing avanzano l'indice, quelli su stream dipendono da file
  finiti o dal read timeout HTTP;
- paginazione e fixture avanzano cursore/indice in modo monotono;
- i test di paginazione PHP e Python hanno anche un massimo derivato dal
  conteggio atteso e falliscono esplicitamente se il cursore non termina;
- `urlopen`, PDO, psycopg e tutte le richieste PowerShell hanno un limite
  esplicito o una scadenza del livello sottostante.

## Prove pulite finali

Il candidato finale è stato estratto in due directory nuove e corte. La rete è
stata resa indisponibile al processo con proxy irraggiungibili, `pip --no-index`
e wheel con hash; le prove sono state eseguite in sequenza su database e porte
distinti.

| Variante | Configuratore | Wall-clock | Verifica | Risultato |
|---|---:|---:|---:|---|
| Tomcat 11.0.24 / Java 23.0.2 | 42,083 s | 42,732 s | 10,266 s | 22 righe, 22 lotti, repeat idempotente |
| Tomcat 9.0.120 / Java 23.0.2 | 42,733 s | 43,334 s | 11,047 s | 22 righe, 22 lotti, repeat idempotente |

Entrambi i database operativi sono rimasti a zero righe. Entrambi i database
di verifica hanno 22 righe, 22 lotti e una migrazione `completed`. I log non
contengono errori loopback o traceback; registri processo e listener delle
otto porte sono assenti dopo il cleanup.

## Pacchetto e artefatti

Due build consecutive hanno prodotto byte identici.

```text
dist/drive-aura-51-offline.zip
dimensione = 12.855.976 byte
SHA-256 = 1019d2cc3f08d5c07e81b129bf786355b5ccd5471dba7d0ad0fa1fbcd6d5442c
```

- 117 entry: 115 payload, manifest e checksum interno;
- 116 righe in `SHA256SUMS.txt`;
- tutti i 115 payload coincidono per byte, dimensione e SHA-256 con le
  rispettive sorgenti del repository;
- 84 file testuali controllati: zero chiavi private, token noti, URL con
  credenziali o percorsi `C:\Users`;
- zero cache, log, `target`, ambiente virtuale, file IDE o configurazione
  locale nel pacchetto o fra i file destinati al commit.

| Artefatto | Byte | SHA-256 |
|---|---:|---|
| WAR Tomcat 9 | 71.757 | `7981cf8734bbdd30187951479f260ced7f8713a6500f2234cb3b5326e4fc3d74` |
| WAR Tomcat 11 | 71.772 | `685922d42eb742714fe153cb72f168aae81453eaade4e79c7e2115a5798b5490` |
| dump sorgente | 407.251 | `65204bc3b87b2e01a8a12f4a228dd93ad93d865348e1595efb901c6766d51d38` |
| manuale PDF | 106.217 | `1073fed99da145ab45b8aac19194766acce0380dc0a52c0fb8f59600cb017ee5` |
| scelte PDF | 98.110 | `2ec18d343a31689148a58eb7f88192c8e989409c1b4511360af9b349b2d04e2b` |

Il manuale è A4 di tre pagine; le scelte sono A4 di una pagina. Tutte le
quattro pagine sono state renderizzate a 144 dpi e ispezionate: nessun testo
tagliato o sovrapposto, carattere corrotto, margine irregolare, pagina vuota o
superflua. I PDF non sono cifrati e non contengono form o JavaScript.

## Evidenze massive riconfermate

Le modifiche T11.1 aggiungono limiti operativi ma non cambiano contratto,
canonicalizzazione, schema, ordinamento, orchestrazione, transazioni o logica
di persistenza. Non è stata quindi ripetuta la migrazione massiva T07.

Il dump è stato ricostruito in sola lettura dal Progetto 1 e ha riprodotto lo
stesso SHA-256. Manifest, schema e seed riconfermano 36.176 righe con conteggi
`3200/200/143/81/30/12000/20492/30`. Restano valide le evidenze T07: 364
lotti, dataset
`75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39`,
otto digest coincidenti, checkpoint/ripresa/idempotenza e zero violazioni di
PK, FK, unicità, domini e progressivi. Il Progetto 1 è pulito e invariato.

## Classificazione finale

### Requisiti soddisfatti

- architettura scelta B e percorso obbligatorio;
- migrazione delle otto entità, integrità e resilienza;
- scadenze finite, rollback e ripresa;
- test reali PHP, Java, Django, MariaDB e PostgreSQL;
- installazione offline sotto cinque minuti con entrambi i WAR;
- pacchetto, dump, wheel, sorgenti, configurazioni, PDF e checksum coerenti;
- nessun segreto o artefatto locale tracciato.

### Requisiti soddisfatti con limite dichiarato

- l'assenza di rete è stata verificata a livello di processo con proxy ostili
  e installazione pip strettamente offline, non disabilitando fisicamente la
  scheda di rete;
- la prova rapida usa una sorgente contrattuale loopback; la verticale
  PHP/PDO massiva resta quella realmente osservata e documentata in T07.

### Requisiti non verificabili localmente

- pubblicazione e limiti effettivi dell'account Altervista;
- indirizzi CC e accessibilità degli allegati dopo l'invio dell'email.

### Problemi residui

Nessun problema tecnico bloccante era noto nei percorsi verificati localmente.
La successiva prova Altervista del 4 agosto 2026 ha individuato un limite
dell'ambiente definitivo: le direttive `SetEnv` vengono conservate ma non
raggiungono PHP, quindi health passa e il manifest risponde 503 prima
dell'autenticazione. L'evidenza e il fallback proposto sono in
`docs/VERIFICA_ALTERVISTA.md`. Email, tag e release non sono stati eseguiti.
