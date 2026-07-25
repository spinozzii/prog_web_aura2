# Attività del progetto

## AUTORIZZATA

Nessuna.

## BACKLOG

- [ ] **T11 - Audit finale e pacchetto di consegna**
  - audit statico, test automatici e prova end-to-end;
  - verifica dei cinque minuti;
  - controllo codice commentato, dump, PDF e contenuto dell'archivio;
  - bozza email conforme alle linee guida.

## IN REVISIONE

- [ ] **T09 - Pacchetto offline, installazione sotto cinque minuti e PDF**
  - creare un pacchetto di consegna candidato che includa sorgenti necessari,
    configurazioni di esempio, dump/checksum, dipendenze Python offline con
    hash, WAR precompilati Tomcat 9/11, script e documenti finali;
  - il computer del docente non deve richiedere Internet, Maven, Composer,
    Node.js, IDE o compilazione Java;
  - implementare un configuratore PowerShell non interattivo o guidato che
    rilevi Python 3.12, Java, Tomcat e PostgreSQL, rifiuti versioni
    incompatibili e non richieda privilegi amministrativi non necessari;
  - creare un ambiente virtuale locale e installare Django/psycopg soltanto
    dalla wheelhouse offline verificata tramite hash;
  - creare/configurare il database PostgreSQL, applicare le migrazioni,
    selezionare e distribuire il WAR corretto e produrre configurazioni locali
    senza salvare segreti nel repository o nell'archivio;
  - includere un verificatore che controlli salute dei tre componenti,
    readiness PostgreSQL e una migrazione sintetica, distinguendo chiaramente
    la verifica rapida dalla migrazione massiva;
  - preparare istruzioni separate e realistiche per pubblicare il PHP su
    Altervista, senza effettuare la distribuzione;
  - eseguire da una copia pulita del pacchetto una prova offline cronometrata:
    installazione, configurazione e verifica devono concludersi entro cinque
    minuti; documentare ambiente, versioni, comandi, tempi e problemi;
  - testare casi avversi: Python/Java/Tomcat/PostgreSQL mancanti o
    incompatibili, porta occupata, database non raggiungibile, archivio o hash
    alterato, segreto mancante e assenza di rete;
  - scrivere un manuale sintetico per utente generico e un documento di circa
    una pagina sulle scelte progettuali, coerenti soltanto con procedure
    realmente provate;
  - generare i due PDF finali usando il workflow PDF previsto e verificarli
    visivamente pagina per pagina: nessun testo tagliato, sovrapposizione,
    carattere corrotto o pagina superflua;
  - verificare che l'archivio non contenga cache, log, `target`, credenziali,
    runtime temporanei o file estranei e che contenga tutto il necessario;
  - mantenere runner completo, test, migrazioni e `mvn clean package`;
  - aggiornare `TASKS.md` e `PROJECT_STATUS.md`, spostare T09 in
    `IN REVISIONE`, creare un commit e pubblicarlo su `origin/main`;
  - verificare commit locale/remoto e working tree pulito, quindi fermarsi
    senza iniziare T11.

## COMPLETATE

- [x] **T00 - Preparazione e direzione iniziale**
  - scelta B consolidata;
  - requisiti, architettura, contratto dati, decisioni, rischi e test definiti;
  - workflow Work-Codex e struttura operativa predisposti.

- [x] **T01 - Scheletri avviabili e contratti di salute**
  - create le strutture minime di `remote-php`, `bridge-servlet` e `local-django`;
  - implementato `GET /health` uniforme con `apiVersion`, `service` e `status`;
  - separati `bridge-servlet/core`, adattatore Tomcat 9/`javax` e adattatore Tomcat 11/`jakarta`;
  - aggiunti test automatici isolati del contratto e comando PowerShell;
  - revisione Work conclusa il 24 luglio 2026 dopo le correzioni T01.1.

- [x] **T01.1 - Correzioni della revisione T01**
  - fissato Django 5.2.16 e verificato su Python 3.12.13;
  - corretto l'header Django e verificato `application/json; charset=utf-8`;
  - verificato il routing PHP `/health` via HTTP senza router speciale;
  - verificati runner rigoroso, modalità `-AllowPartial` e runner completo;
  - superato `mvn clean package` con produzione dei due WAR;
  - T02 confermata non avviata.

- [x] **T01.2 - Inizializzazione Git e collegamento GitHub**
  - repository remoto verificato inizialmente vuoto;
  - inizializzato `main` soltanto in questa cartella e configurato `origin`;
  - pubblicato il checkpoint iniziale senza force push;
  - verificati esclusioni, tracking, working tree pulito e coincidenza fra commit locale e remoto `b400d5229a924b46f9c4debbf079d9d8417aa38f`;
  - revisione Work conclusa il 24 luglio 2026.

- [x] **T02.1 - Contratto eseguibile e digest condiviso di Patologia**
  - fissata la rappresentazione canonica e aggiunta la fixture UTF-8 condivisa;
  - implementate e verificate canonicalizzazione e SHA-256 in PHP, Java 8 e
    Python/Django;
  - digest condiviso verificato:
    `53f27d16f82cdf36bbdb1bd28b61bc6cf7f7057d5cc135a66c2bd9105cc27b83`;
  - runner completo e build dei due WAR superati;
  - commit locale e GitHub verificati su
    `30b34233b63b016743a572fe35128e7fe85e3617`;
  - il caso limite della sequenza vuota è una correzione obbligatoria iniziale
    di T02.2.

- [x] **T02.2 - Prima migrazione verticale completa di Patologia**
  - realizzati manifest/export PHP, orchestratore Java, adattatori Tomcat
    9/11 e importazione transazionale Django/PostgreSQL;
  - verificati sicurezza, cursori, digest, rollback, conflitti e idempotenza;
  - osservata la verticale reale MariaDB → PHP/PDO → Tomcat → Django →
    PostgreSQL con tre pagine/lotti e stato `completed`;
  - runner completo, 18 test Django, build dei due WAR e migrazioni superati;
  - commit locale e GitHub verificati su
    `fc90d808857caf156fa929a157faf745d8a0570f`;
  - revisione Work conclusa senza correzioni bloccanti.

- [x] **T03 - Estensione verticale a tutte le entità rimanenti**
  - estesi schema, PHP, Java e Django alle otto entità complessive;
  - preservati PK/FK, chiavi composte, univocità, date, decimali e progressivi;
  - runner completo, 25 test Django, migrazioni e build dei due WAR superati;
  - osservata verticale reale sulle otto entità e rilancio idempotente con
    entrambi gli adattatori Tomcat;
  - commit locale e GitHub verificati su
    `d86d474a700f168421f00286b0336eeea64aec25`;
  - revisione Work conclusa senza correzioni bloccanti.

- [x] **T07 - Resilienza e migrazione del dataset massivo reale**
  - migrate realmente 36.176 righe in 364 lotti attraverso i quattro livelli;
  - verificati retry, checkpoint, interruzione/ripresa, errori definitivi e
    rilancio idempotente con entrambi i WAR;
  - verificati conteggi, digest, PK, FK, unicità, domini e progressivi;
  - prodotto dump sorgente con SHA-256
    `65204bc3b87b2e01a8a12f4a228dd93ad93d865348e1595efb901c6766d51d38`;
  - runner completo, 33 test Django, migrazioni e build dei WAR superati;
  - commit locale e GitHub verificati su
    `2c0e52b34c711873fdf92533bff9beec6d3b6878`;
  - revisione Work conclusa senza correzioni bloccanti.

## BLOCCATE

Nessuna.
