# Attività del progetto

## AUTORIZZATA

Nessuna.

## BACKLOG

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

- [ ] **T03 - Estensione verticale a tutte le entità rimanenti**
  - introdotti schema e fixture condivisi per tutte le otto entità, con campi,
    tipi, domini, ordine, chiavi, FK, unicità, byte canonici e digest globali;
  - generalizzati manifest, export PHP/PDO, keyset su tuple complete, cursori
    HMAC e controllo del dataset senza duplicare la logica per entità;
  - aggiunti modelli e migrazioni PostgreSQL, inclusa la FK composta reale,
    registri per entità/lotto, transazioni, rollback, ordine e idempotenza;
  - esteso il core Java 8 alle otto entità, mantenendo sottili e funzionanti
    entrambi gli adattatori Tomcat 9/`javax` e Tomcat 11/`jakarta`;
  - coperti ordine, PK composte, date, decimali, FK, unicità, digest/conteggi,
    rollback, associazioni, progressivi, dataset globale e rilancio;
  - runner rigoroso completo e 25 test Django superati; migrazioni pulite;
    `mvn clean package` superato con produzione di entrambi i WAR;
  - osservata la verticale reale MariaDB → PHP/PDO → Tomcat 11 → Django →
    PostgreSQL su 22 righe/lotti; verificati conteggi, digest e vincoli;
  - osservato il rilancio idempotente dello stesso `migrationId` via Tomcat 9,
    senza duplicare run, lotti o dati;
  - documentata la prova in `docs/VERIFICA_T03.md`; Progetto 1, Altervista,
    dataset massivo, resilienza T07, installatore e PDF non sono stati avviati.

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

## BLOCCATE

Nessuna.
