# Requisiti consolidati

## 1. Fonti

Fonti normative:

1. `../PW - Linee Guida Progetto #2 (2).pdf`;
2. schema e dataset del Progetto 1 in
   `../../../progetto 1/drive-aura-51-servizio-sanitario`;
3. indicazioni del docente riportate nella review conservata con il Progetto 1.

In caso di conflitto prevalgono le linee guida del Progetto 2. Un'ambiguità non
deve essere risolta riducendo silenziosamente lo scope.

## 2. Scelta progettuale

È adottato il caso B: sviluppo di web-service per migrare i dati usati nel
Progetto 1 da un database remoto a un database locale PostgreSQL.

Sono obbligatori:

1. web-service remoto in PHP sul sito Altervista del Progetto 1;
2. servlet Java intermedia;
3. web-service locale in Python/Django;
4. database PostgreSQL locale.

La servlet deve interrogare il servizio remoto e inviare i dati al servizio
locale. Una migrazione che aggira la servlet non soddisfa il requisito.

## 3. Dati da migrare

La migrazione comprende l'intero stato applicativo utile del Progetto 1:

- `cittadino`;
- `ospedale`;
- `patologia`;
- `patologia_cronica`;
- `patologia_mortale`;
- `ricovero`;
- `patologia_ricovero`;
- `progressivo_ricovero`.

Devono essere preservati:

- valori e tipi logici;
- chiavi primarie semplici e composte;
- chiavi esterne;
- unicità del direttore sanitario;
- associazioni tra ricoveri e patologie;
- appartenenza indipendente ai sottoinsiemi cronica e mortale;
- progressivo del ricovero per ospedale;
- precisione dei costi e date senza variazioni di fuso orario.

Il database locale non deve contenere duplicati o righe orfane.

## 4. Servizio PHP remoto

Il servizio remoto deve:

- essere compatibile con Altervista, PHP e PDO MySQL/MariaDB;
- leggere soltanto il database;
- esporre un manifest del dataset;
- esportare una sola entità per richiesta;
- usare una whitelist di entità e campi;
- applicare paginazione deterministica e limite massimo del lotto;
- restituire JSON UTF-8 versionato;
- usare query preparate;
- non esporre credenziali o errori interni;
- richiedere un segreto configurabile;
- permettere la verifica di conteggi e digest.

Il servizio non deve introdurre Composer o dipendenze server non disponibili
su Altervista.

## 5. Servlet Java intermedia

La servlet deve:

- essere eseguibile su Tomcat 9 o Tomcat 11 con l'artefatto corretto;
- interrogare il servizio PHP remoto via HTTP;
- inoltrare ogni lotto al servizio Django locale;
- rispettare l'ordine delle dipendenze;
- propagare un identificativo univoco della migrazione;
- mantenere checkpoint e stato;
- applicare timeout e retry limitati;
- interrompersi su errori non recuperabili;
- mostrare uno stato sintetico e verificabile;
- non collegarsi direttamente ai database;
- non richiedere Maven, Gradle o IDE sulla macchina del docente.

## 6. Servizio Django locale

Il servizio locale deve:

- usare Python 3.12 e Django 5.2 LTS;
- ricevere esclusivamente lotti conformi al contratto;
- validare autenticazione, versione, entità, schema e tipi;
- inserire in PostgreSQL;
- rispettare l'ordine e i vincoli referenziali;
- usare una transazione per lotto;
- essere idempotente rispetto a migrazione, entità e lotto;
- registrare conteggi, digest, errori e completamento;
- offrire una verifica finale;
- non mostrare stack trace o segreti;
- non usare SQLite nel flusso consegnato.

SQLite può essere usato soltanto per test unitari isolati che non pretendano di
validare il comportamento PostgreSQL.

## 7. Affidabilità

Il trasferimento deve:

- usare lotti, non una singola risposta contenente tutto il database;
- avere ordine stabile;
- rilevare un dataset remoto cambiato durante la migrazione;
- consentire un rilancio senza duplicazioni;
- non dichiarare successo in presenza di lotti mancanti;
- confrontare conteggi e digest per ogni entità;
- verificare i vincoli e i progressivi dopo l'importazione;
- produrre messaggi comprensibili nei casi avversi.

## 8. Sicurezza

- Nessun segreto nel codice o nel repository.
- I tre servizi devono autenticare le chiamate applicative.
- Gli endpoint di importazione devono accettare solo richieste locali o
  correttamente autenticate.
- I nomi di tabella, ordinamento e campi non devono provenire liberamente
  dall'input.
- Le risposte non devono contenere query, stack trace o percorsi.
- I log non devono registrare segreti o interi payload.

## 9. Installazione e verifica

- Configurazione e avvio da riga di comando.
- Nessun IDE.
- Non assumere software diverso da Python, Java, PostgreSQL e Tomcat indicati
  nelle linee guida.
- Non assumere versioni precise senza rilevarle.
- Dipendenze Django installabili offline in un ambiente locale.
- WAR Java già compilati.
- Procedura completa e prova di verifica entro cinque minuti.
- Errori di prerequisiti devono indicare cosa manca e come correggerlo.
- Il progetto deve essere accessibile in locale.

## 10. Consegna

La consegna deve includere:

- tutto il codice adeguatamente commentato;
- dump del database sorgente;
- manuale sintetico in PDF per un utente generico;
- documento di circa una pagina in PDF sulle scelte progettuali;
- configurazioni di esempio senza segreti;
- dipendenze offline e WAR necessari;
- test o comando di verifica;
- archivio privo di credenziali, cache e file di sviluppo.

L'email deve:

- avere oggetto con prefisso `[PW26]`;
- contenere nome del gruppo e indicazione del secondo progetto;
- dichiarare nel testo la scelta B;
- includere tutti i membri del gruppo in CC.

## 11. Valutazione

- massimo indicato: 8 punti entro il 31 luglio;
- dopo il 31 luglio: massimo 7,5 punti;
- penalità di 0,5 punti per email non conforme;
- penalità di 0,5 punti per installazione/verifica oltre cinque minuti;
- penalità di 0,5 punti se il docente deve chiedere chiarimenti perché il
  manuale non consente la verifica.

