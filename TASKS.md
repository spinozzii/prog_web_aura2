# Attività del progetto

## AUTORIZZATA

Nessuna.

## BACKLOG

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

- [ ] **T02.2 - Prima migrazione verticale completa di Patologia**
  - corretta la sequenza vuota nei tre linguaggi: zero byte, digest SHA-256
    della sequenza vuota e fixture condivisa di regressione; verificati anche
    i separatori Unicode U+2028/U+2029 con un vettore condiviso;
  - implementati manifest ed export PHP/PDO con autenticazione d'ambiente,
    whitelist, limite, keyset, cursore HMAC, sorgente fixture solo nei test ed
    errori uniformi;
  - implementati schema PostgreSQL, migrazioni Django, registro di run/lotti,
    batch transazionali e idempotenti, conflitti, finalizzazione e stato;
  - implementati core Java 8, trasporto HTTP limitato e due adattatori sottili
    Tomcat 9/`javax` e Tomcat 11/`jakarta`;
  - coperti successo multipagina, vuoto e casi avversi PHP, Java e Django;
    runner rigoroso completo e `-AllowPartial` verificati;
  - superato `mvn clean package`; prodotti entrambi i WAR;
  - osservata la verticale reale su MariaDB, PHP, Tomcat 11, Django e
    PostgreSQL, con tre pagine/lotti, digest finale e registro verificati;
    rilancio idempotente osservato anche attraverso Tomcat 9;
  - Progetto 1 e Altervista non coinvolti, nessuna credenziale inserita e
    nessuna altra entità implementata; T03 non avviata.

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

## BLOCCATE

Nessuna.
