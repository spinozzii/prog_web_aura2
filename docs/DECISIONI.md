# Registro delle decisioni

## Decisioni approvate

### D01 - Scelta B

Il Progetto 2 sviluppa la migrazione tramite web-service. Non viene riscritta
l'intera interfaccia del Progetto 1.

Motivazione: riuso del database e del deployment esistenti, scope più
circoscritto e obiettivo distinto dal primo progetto.

### D02 - PostgreSQL locale

Il database di destinazione è PostgreSQL, non MongoDB.

Motivazione: il modello sorgente è relazionale, contiene chiavi composte,
vincoli univoci e associazioni che PostgreSQL preserva direttamente.

### D03 - Migrazione completa

Si migrano le otto tabelle elencate in `docs/CONTRATTO_DATI.md`, compresi
sottoinsiemi e progressivi.

Motivazione: "i dati usati per il primo progetto" viene interpretato come stato
applicativo completo, non come campione parziale.

### D04 - API JSON versionata

I componenti comunicano con JSON UTF-8 e `apiVersion`.

Motivazione: contratto esplicito, verificabile nei tre linguaggi e semplice da
ispezionare.

### D05 - Lotti e paginazione keyset

L'export usa lotti e ordine di chiave primaria; il cursore pubblico è opaco.

Motivazione: il dataset è troppo grande per una sola risposta e la keyset
pagination è deterministica senza dipendere da offset crescenti.

### D06 - Django 5.2 LTS

Si usa Django 5.2 LTS su Python 3.12. La patch esatta viene fissata dopo i test
e distribuita offline.

Motivazione: compatibilità ufficiale con Python 3.12 e supporto LTS. Le
limitazioni sulle relazioni verso chiavi composte vengono isolate nel livello
di persistenza e nei vincoli SQL PostgreSQL.

### D07 - Due adattatori Servlet

La logica Java condivisa non importa API Servlet. Due moduli sottili producono:

- WAR Tomcat 9 con `javax.servlet` e bytecode Java 8;
- WAR Tomcat 11 con `jakarta.servlet` e bytecode Java 17.

Motivazione: Tomcat 9 e 11 usano namespace e requisiti Java incompatibili.

### D08 - Installazione offline

Il docente non deve compilare Java né scaricare dipendenze Python. Il pacchetto
include WAR precompilati e dipendenze Python offline con versioni e hash.

Motivazione: limite di cinque minuti e software disponibile non garantito oltre
quanto dichiarato.

### D09 - Importazione idempotente

Migrazione, entità e sequenza identificano un lotto; il digest distingue una
ripetizione valida da un conflitto. Ogni lotto è transazionale.

Motivazione: retry e ripresa non devono creare duplicati o stato ambiguo.

### D10 - Sicurezza configurabile

Le chiamate usano segreti configurabili esterni al repository. Il servizio PHP
è in sola lettura e tutte le entità/campi sono in whitelist.

Motivazione: l'endpoint remoto non deve trasformarsi in un accesso pubblico
indiscriminato al database.

### D11 - Separazione dal Progetto 1

Il codice del Progetto 2 resta in questa cartella. Il Progetto 1 è letto come
fonte e non viene modificato durante lo sviluppo.

Motivazione: evitare regressioni e mantenere consegne e cronologia separate.

### D12 - Prima sezione verticale

Dopo gli scheletri, la prima migrazione completa usa `patologia`.

Motivazione: tabella piccola, indipendente e sufficiente per validare l'intero
percorso PHP-Servlet-Django-PostgreSQL prima delle relazioni complesse.

## Decisioni aperte

- sistema operativo esatto da supportare nella prova del docente;
- percorso e modalità di avvio del Tomcat installato;
- patch esatta di Django 5.2 e pacchetto PostgreSQL Python;
- limite iniziale dei lotti dopo misure su Altervista;
- formato del dump sorgente e sua eventuale compressione;
- comando unico definitivo di configurazione/avvio/verifica;
- URL pubblico definitivo del servizio PHP.

## Modello per nuove decisioni

### DXX - Titolo

- Data:
- Stato: proposta / approvata / superata;
- Contesto:
- Decisione:
- Motivazione:
- Conseguenze:

