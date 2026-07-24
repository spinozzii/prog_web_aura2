# Attività del progetto

## AUTORIZZATA

Nessuna.

## BACKLOG

- [ ] **T02 - Prima sezione verticale: Patologia**
  - manifest remoto;
  - export paginato e deterministico;
  - inoltro tramite servlet;
  - import transazionale e ripetibile in PostgreSQL;
  - verifica conteggio e digest su una fixture.

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

- [ ] **T01.2 - Inizializzazione Git e collegamento GitHub**
  - verificato che `https://github.com/spinozzii/prog_web_aura2.git` fosse vuoto;
  - inizializzato Git sul ramo `main` solo in questa cartella e configurato `origin`;
  - verificati i file ammessi e l'esclusione di `target`, cache, configurazioni locali e credenziali;
  - creato e pubblicato il checkpoint iniziale senza force push;
  - verificati `origin`, tracking di `main`, coincidenza dei commit e working tree pulito;
  - T02 non avviata.

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

## BLOCCATE

Nessuna.
