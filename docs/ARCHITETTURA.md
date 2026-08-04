# Architettura tecnica

## 1. Vista d'insieme

```text
┌────────────────────────────── Remoto ──────────────────────────────┐
│ MySQL/MariaDB ← PDO ← Web-service PHP                              │
└───────────────────────────────┬────────────────────────────────────┘
                                │ HTTPS / JSON a lotti
                                ▼
┌────────────────────────────── Locale ──────────────────────────────┐
│ Servlet Java su Tomcat                                             │
│      │                                                             │
│      └── HTTP / JSON ──→ Web-service Django ──→ PostgreSQL          │
└────────────────────────────────────────────────────────────────────┘
```

La servlet è un orchestratore HTTP. Non contiene logica SQL e non accede
direttamente ai database.

## 2. Moduli

### `remote-php`

Responsabilità:

- autenticazione delle richieste;
- lettura del manifest;
- export deterministico di una entità a lotti;
- serializzazione canonica;
- errori HTTP uniformi.

Non contiene codice di importazione e non modifica MySQL.

La configurazione del componente remoto resta esterna al codice. Il loader
risolve ciascuna chiave prima dall'ambiente e, soltanto quando è assente, dal
file server-only `remote-php/config/local.php`; il file accetta esclusivamente
la whitelist prevista per database, autenticazione, cursori e timeout.
`local.php.example` è il solo modello tracciato, mentre `local.php` è ignorato
da Git e non appartiene al pacchetto di consegna.

Il fallback è necessario negli hosting che accettano `SetEnv` ma non lo
propagano a `getenv()`. Il file resta fuori da `public` e la directory
`config` applica un diniego HTTP. Poiché la radice dell'account può comunque
essere pubblica, il deploy deve verificare una risposta 403 o 404 su un file
innocuo nella stessa directory prima di inserire segreti; un esito diverso
interrompe la configurazione. L'endpoint `/health` risponde prima di caricare
questa configurazione e resta indipendente dal database.

### `bridge-servlet`

Responsabilità:

- creazione di un'esecuzione di migrazione;
- lettura del manifest remoto;
- scelta dell'ordine delle entità;
- ciclo sui cursori;
- inoltro dei lotti;
- checkpoint, timeout, retry limitati e stato;
- richiesta di finalizzazione.

La logica condivisa resta indipendente dalle API Servlet. Due moduli sottili
forniscono l'adattamento:

- Tomcat 9: Servlet 4.0, namespace `javax.servlet`, bytecode Java 8;
- Tomcat 11: Servlet 6.1, namespace `jakarta.servlet`, bytecode Java 17.

Il pacchetto finale contiene entrambi i WAR. Il configuratore seleziona quello
compatibile con l'ambiente rilevato.

### `local-django`

Responsabilità:

- autenticazione e validazione del contratto;
- apertura o ripresa di una migrazione;
- persistenza idempotente in PostgreSQL;
- transazioni per lotto;
- registro di lotti e conteggi;
- finalizzazione, controllo digest e vincoli;
- stato di salute e stato della migrazione.

PostgreSQL resta l'autorità dei vincoli. Le relazioni verso chiavi composte non
devono dipendere da API ORM ancora limitate: migrazioni SQL esplicite e un
repository di importazione possono essere usati quando rendono chiavi e FK più
chiare e verificabili.

## 3. Contratto HTTP

Tutte le risposte:

- usano `application/json; charset=utf-8`;
- includono `apiVersion`;
- usano date/ore tecniche ISO 8601 UTC;
- non includono stack trace o segreti;
- hanno codici HTTP coerenti.

### Salute

Ogni componente espone `GET /health`.

Risposta minima:

```json
{
  "apiVersion": "1.0",
  "service": "remote-php",
  "status": "ok"
}
```

Valori di `service`:

- `remote-php`;
- `bridge-servlet`;
- `local-django`.

L'endpoint di salute non accede obbligatoriamente al database. Un controllo
separato di readiness può verificare le dipendenze senza confondere processo
avviato e sistema pronto.

### Manifest remoto

`GET /api/v1/manifest`

Contiene:

- `apiVersion`;
- `datasetId`;
- `generatedAt`;
- ordine delle entità;
- numero di righe per entità;
- digest canonico per entità;
- dimensione massima accettata del lotto.

### Export remoto

`GET /api/v1/export/{entity}?datasetId=...&cursor=...&limit=...`

Contiene:

- `datasetId`;
- `entity`;
- `cursor`;
- `nextCursor`;
- `hasMore`;
- `rowCount`;
- `rows`;
- digest del lotto.

Il cursore è opaco per il chiamante. Il server usa internamente la chiave
primaria completa come paginazione keyset. `datasetId` è obbligatorio: la
prima pagina dell'entità confronta l'identità corrente della sorgente con
quella fissata dal manifest, mentre ogni cursore successivo è firmato e legato
alla stessa identità.

### Avvio della migrazione

`POST /api/v1/migrations` sulla servlet.

La servlet crea un `migrationId`, controlla i servizi, legge il manifest e
inizializza il registro locale o ne legge lo stato persistente e inizia il
flusso. Una seconda richiesta con lo stesso identificativo e dataset riprende
dal checkpoint confermato e non crea duplicazioni.

Il PHP mantiene la scadenza nominale nei cursori, ma un export Bearer
autenticato accetta un checkpoint persistito correttamente firmato anche dopo
la scadenza. Firma, entità e `datasetId` restano obbligatori: un riavvio
tardivo può quindi usare esattamente il cursore autorevole salvato da Django.

### Import locale

`POST /api/v1/migrations/{migrationId}/batches`

Ogni lotto include:

- dataset ed entità;
- identificativo e sequenza del lotto;
- righe;
- digest.

Il servizio Django convalida e registra il lotto nella stessa transazione dei
dati. Un lotto già completato con lo stesso digest restituisce successo
idempotente; lo stesso identificativo con contenuto diverso restituisce
conflitto.

### Finalizzazione

`POST /api/v1/migrations/{migrationId}/finalize`

Il servizio locale:

- verifica presenza di tutti i lotti;
- confronta conteggi e digest;
- controlla FK, unicità e progressivi;
- marca la migrazione `completed` solo dopo tutti i controlli.

### Stato

`GET /api/v1/migrations/{migrationId}`

Restituisce stato, entità corrente, righe importate, totale previsto, ultimo
errore sintetico e risultato della verifica.

## 4. Stati

Stati minimi:

- `created`;
- `running`;
- `interrupted`;
- `failed`;
- `completed`.

Un errore recuperabile mantiene checkpoint e ultimo lotto confermato. Un errore
di schema, digest o dataset rende l'esecuzione `failed` e richiede intervento o
un nuovo identificativo.

## 5. Ordine delle entità

1. `cittadino`;
2. `patologia`;
3. `patologia_cronica`;
4. `patologia_mortale`;
5. `ospedale`;
6. `ricovero`;
7. `patologia_ricovero`;
8. `progressivo_ricovero`.

L'ordine è definito dal progetto, non accettato liberamente dal client.

La verticale T03 usa `shared/entity-schema.json` come whitelist dichiarativa.
Il servizio PHP associa ogni entità esclusivamente a tabella, campi e chiavi
predefiniti; il core Java applica lo stesso ordine e lo stesso schema senza
SQL; Django associa la definizione ai modelli PostgreSQL e mantiene i vincoli
reali. La logica comune di pagina, cursore, canonicalizzazione, digest,
trasferimento e finalizzazione resta unica per componente.

Il `datasetId` globale deriva dai conteggi e dai digest di tutte le entità. I
lotti e le finalizzazioni sono invece registrati per
`(migration_id, entity)`, così un rilancio completo può riconoscere ogni
passaggio già confermato senza confondere entità diverse.

## 6. Idempotenza

Chiave logica di un lotto:

`(migration_id, entity, batch_sequence)`

Il digest distingue la ripetizione valida da un conflitto. La persistenza dei
dati usa le chiavi naturali del dominio e operazioni compatibili con un
rilancio. La finalizzazione non cancella o sostituisce silenziosamente dati
estranei.

## 7. Resilienza T07

Lo stato globale risiede in PostgreSQL, non nella memoria della servlet. Per
ogni entità il checkpoint conserva almeno:

- stato e conteggio importato;
- prossima sequenza di lotto;
- ultimo cursore sorgente confermato e cursore successivo;
- indicazione `hasMore`;
- digest e conteggio attesi;
- ultimo errore sintetico e sua recuperabilità.

La conferma del lotto e l'avanzamento del checkpoint sono atomici. Se la
servlet viene arrestata dopo che Django ha confermato un lotto, al riavvio lo
stesso `migrationId` legge il valore autorevole da PostgreSQL; se una risposta
è andata persa, la ripetizione dello stesso lotto viene riconosciuta dal
digest.

Il core Java applica timeout e un numero limitato di retry soltanto a
operazioni idempotenti. Errori di trasporto e risposte temporanee come 408,
429, 500, 502, 503 e 504 sono recuperabili entro quel limite. Autenticazione,
contratto, dataset cambiato, digest errato e lotto discordante sono definitivi
e vengono registrati senza retry.

Prima di completare la migrazione, Java rilegge il manifest remoto e confronta
ordine, conteggi, digest e `datasetId`; `generatedAt` è escluso dal confronto
di identità. Django rifiuta inoltre la finalizzazione finché il checkpoint
indica che la sorgente non è esaurita.

Ogni livello operativo ha una scadenza finita. Il runner e l'installer
incapsulano i processi esterni in un job Windows con watchdog; readiness e
richieste HTTP hanno deadline esplicite. Django configura su ogni sessione
PostgreSQL i limiti di connessione, lock, statement e transazione inattiva.
Il PHP distingue il timeout di connessione PDO dal limite server della query,
rilevando MariaDB o MySQL prima di applicare sintassi specifica. Un timeout
database lascia che la transazione Django esegua rollback e viene classificato
come recuperabile dal percorso di resilienza esistente.

## 8. Installazione

Il candidato offline contiene:

- codice sorgente dei tre componenti;
- dipendenze Python offline con hash;
- due WAR precompilati;
- configurazioni di esempio;
- dump sorgente;
- configuratore e verificatore da riga di comando;
- manuale e documento delle scelte in PDF.

Il configuratore PowerShell:

1. rileva Python, Java, Tomcat e PostgreSQL;
2. rifiuta combinazioni incompatibili con un messaggio chiaro;
3. crea un ambiente Python locale;
4. installa le dipendenze senza rete;
5. prepara un database operativo e uno sintetico separati, applica le
   migrazioni e produce lo stato locale senza segreti;
6. seleziona e distribuisce il WAR corretto;
7. avvia o guida l'avvio dei servizi;
8. esegue salute/readiness, una verifica sintetica idempotente e la pulizia
   verificata dei processi.

L'ambiente virtuale e il `CATALINA_BASE` sono creati in una directory sorella
esterna alla radice immutabile del pacchetto. Tomcat 9 seleziona il WAR
`javax`, Tomcat 11 il WAR `jakarta`; Tomcat 10 viene rifiutato.

## 9. Osservabilità

I log usano:

- `migrationId`;
- componente;
- entità e sequenza lotto;
- durata;
- esito e codice errore.

Non registrano:

- segreti;
- credenziali;
- interi payload;
- stack trace nelle risposte;
- dati personali oltre gli identificativi indispensabili al debug locale.
