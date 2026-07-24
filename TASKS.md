# Attività del progetto

## AUTORIZZATA

Nessuna.

## BACKLOG

- [ ] **T02.2 - PHP remoto: manifest ed export di Patologia**
  - configurazione PDO e autenticazione tramite ambiente;
  - manifest e paginazione keyset con cursore opaco;
  - query preparate, whitelist e test HTTP/contratto.

- [ ] **T02.3 - Django/PostgreSQL: importazione di Patologia**
  - schema PostgreSQL e registro dei lotti;
  - validazione, transazione, idempotenza e conflitto digest;
  - finalizzazione e test con PostgreSQL reale.

- [ ] **T02.4 - Servlet e prova verticale di Patologia**
  - lettura manifest ed export PHP;
  - inoltro dei lotti e finalizzazione Django;
  - adattatori Tomcat 9 e 11 e verifica end-to-end del percorso completo.

- [ ] **T03 - Cittadino e sottoinsiemi Patologia**
  - migrare `cittadino`, `patologia_cronica` e `patologia_mortale`;
  - aggiungere validazioni, test di chiavi e casi negativi.

- [ ] **T04 - Ospedale**
  - migrare `ospedale` dopo `cittadino`;
  - preservare FK e univocità del direttore sanitario.

- [ ] **T05 - Ricovero**
  - migrare `ricovero` dopo `cittadino` e `ospedale`;
  - preservare chiave composta, domini e tipi numerici/data.

- [ ] **T06 - Relazioni e progressivi**
  - migrare `patologia_ricovero` e `progressivo_ricovero`;
  - verificare chiavi composte, FK e `MAX(cod) + 1`.

- [ ] **T07 - Orchestrazione completa e resilienza**
  - ordine automatico delle entità;
  - identificativo della migrazione, checkpoint, retry limitati e resume;
  - autenticazione tra servizi, timeout e limiti dei lotti;
  - stato finale verificabile.

- [ ] **T08 - Dataset massivo e dump sorgente**
  - migrazione dell'intero dataset del Progetto 1;
  - confronto di conteggi, digest e vincoli;
  - dump del database di origine per la consegna.

- [ ] **T09 - Installazione ripetibile sotto cinque minuti**
  - configuratore da riga di comando;
  - dipendenze Python offline;
  - WAR precompilati per Tomcat 9 e Tomcat 11;
  - rilevamento runtime e messaggi per i casi avversi;
  - prova cronometrata da copia pulita.

- [ ] **T10 - Manuale e documento delle scelte**
  - manuale sintetico per utente generico;
  - documento di circa una pagina sulle scelte;
  - generazione e verifica dei PDF;
  - istruzioni coerenti con la prova pulita.

- [ ] **T11 - Audit finale e pacchetto di consegna**
  - audit statico, test automatici e prova end-to-end;
  - verifica dei cinque minuti;
  - controllo codice commentato, dump, PDF e contenuto dell'archivio;
  - bozza email conforme alle linee guida.

## IN REVISIONE

- [ ] **T02.1 - Contratto eseguibile e digest condiviso di Patologia**
  - documentata la rappresentazione esatta di `patologia`: ordine `cod`,
    `nome`, `criticita`, JSON compatto, UTF-8, slash non trasformati e LF
    finale per ogni record;
  - aggiunta fixture condivisa con accenti, escape JSON, criticità 1 e 5,
    byte canonici attesi e digest SHA-256;
  - implementate funzioni senza dipendenze in PHP, Java core Java 8 e Python;
  - i test dei tre linguaggi consumano la fixture, riordinano i record e
    verificano byte canonici e digest identici;
  - runner rigoroso e `-AllowPartial` verificati, runner completo superato con
    i runtime temporanei; `mvn clean package` superato con produzione dei due WAR;
  - endpoint `/health` invariati; nessun manifest, export, orchestrazione,
    import o accesso al database implementato;
  - T02.2 non avviata.

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

## BLOCCATE

Nessuna.
