# Attività del progetto

## AUTORIZZATA

Nessuna.

## BACKLOG

Nessuna.

## IN REVISIONE

- [ ] **T13.2 - Valutazione rapida del ripristino completo Altervista**
  - nuova autorizzazione applicata senza avviare la migrazione Django/PostgreSQL;
  - phpMyAdmin espone il solo database applicativo `my_motorizzami`, con le
    esatte otto tabelle sanitarie; schema, motori InnoDB e tabelle sono quindi
    compatibili con un futuro ripristino circoscritto dal seed ufficiale;
  - l'export SQL completo richiesto prima di un import non ha prodotto un file
    locale verificabile nel collaudo a scadenza finita; resta disponibile il
    backup T13.1, deliberatamente limitato alle tre tabelle allora coinvolte,
    ma non e' sufficiente per sovrascrivere tutte le otto tabelle;
  - per non effettuare una sostituzione irreversibile senza rollback completo
    dimostrabile non e' stata eseguita alcuna query DDL/DML o importazione;
  - Altervista resta pubblicato ma non allineato a T07: usare per la consegna
    il pacchetto offline e `origin/consegna`; non configurare la servlet verso
    il remoto finche' non si ottengono backup completo verificato e HTTPS con
    certificato valido.

- [ ] **T13.1 - Bonifica minima del database Altervista**
  - creato prima di qualsiasi possibile DML un export SQL gzip verificato,
    conservato fuori dal repository e limitato alle tre tabelle coinvolte;
  - riconfermati gli hash delle fonti ufficiali e confrontati set di PK e
    contenuti senza registrare dati personali;
  - identificate con certezza la PK extra `OSP-011/442` di `ricovero` e la PK
    figlia `OSP-011/442/PAT-049`, entrambe assenti dal seed e collegate tra
    loro; nessuna PK attesa risulta mancante;
  - rilevate però anche la PK comune `OSP-007/161` con la sola colonna
    `paziente_cssn` divergente e tre valori `prossimo_cod` con delta `+1` per
    `OSP-011`, `OSP-021` e `OSP-024`;
  - la rimozione autorizzata delle sole due righe extra lascerebbe quindi
    `ricovero`, `progressivo_ricovero` e il `datasetId` non conformi a T07: per
    evitare una bonifica parziale irreversibile non è stata eseguita alcuna
    query di scrittura;
  - riconfermati HTTP 200 su health, HTTP 401 sul manifest anonimo e HTTP 200
    sul manifest autenticato; conteggi e digest remoti sono rimasti invariati;
  - verificata nel pannello la voce HTTPS: il protocollo è disattivato e
    l'attivazione richiede identificazione telefonica dell'utente; il test TLS
    continua a restituire `ERR_CERT_AUTHORITY_INVALID`, senza bypass;
  - diagnostici pubblici rimossi; vecchio sito, Progetto 1, `dist`, database e
    branch `consegna` sono rimasti invariati.

- [ ] **T13 - Completamento pubblicazione Altervista**
  - implementato e pubblicato il caricatore PHP a whitelist con precedenza
    ambiente e fallback sul file server-only `remote-php/config/local.php`;
  - verificato HTTP 403 sulla directory `config` prima di inserirvi valori
    reali; il file effettivo resta ignorato da Git e il repository contiene
    soltanto l'esempio senza segreti;
  - ripristinato l'accesso database dal pannello, invalidando la password
    precedentemente esposta senza modificare dati o schema; Altervista usa la
    password locale facoltativa vuota;
  - verificati `/health` HTTP 200, manifest anonimo HTTP 401 e manifest
    autenticato HTTP 200 con tutte le otto entità;
  - rilevati due scostamenti bloccanti nel database remoto: `ricovero` 12.001
    anziché 12.000 e `patologia_ricovero` 20.493 anziché 20.492; nessuna riga è
    stata modificata e la migrazione massiva non è stata avviata;
  - HTTPS resta non validabile per `ERR_CERT_AUTHORITY_INVALID`; non è stato
    introdotto alcun bypass TLS;
  - rimossi i diagnostici pubblici; `public` contiene soltanto `.htaccess`,
    `index.php` e `health`, mentre il vecchio sito, il Progetto 1 e il branch
    `consegna` sono rimasti invariati;
  - superati 6 test PHP, lint di 23 file, runner rigoroso Java/PHP/Django e
    build temporanea del pacchetto con 119 payload; il candidato `dist` non è
    stato rigenerato;
  - in attesa della revisione Work e di un'eventuale nuova autorizzazione per
    riconciliare i due record eccedenti e risolvere HTTPS.

- [ ] **T12 - Branch GitHub minimale di consegna**
  - salvata e pubblicata l'autorizzazione Work su `main` nel commit
    `2b86cb85887883b288898b993d286c496351f796`;
  - pubblicato `origin/consegna` sul commit orfano
    `2e67fcebe01f090e175b74b7ca79405e39b13c77`, senza genitori e con una sola
    revisione nella propria cronologia;
  - il tree remoto contiene esattamente `drive-aura-51-offline.zip` e
    `drive-aura-51-offline.zip.sha256` alla radice, senza `.gitignore` o altri
    file;
  - ZIP remoto e sorgente `dist` coincidono byte per byte: 12.855.976 byte,
    SHA-256
    `1019d2cc3f08d5c07e81b129bf786355b5ccd5471dba7d0ad0fa1fbcd6d5442c`;
  - sidecar remoto byte-identico, con digest e nome del file corretti;
  - riconfermati 117 file/115 payload, 2 WAR, 7 wheel e 2 PDF, senza segreti,
    cache, log, `target`, runtime o configurazioni locali; i 109 payload
    appartenevano al candidato storico T11 e non al candidato T11.1 richiesto;
  - `main` è rimasto il repository tecnico completo e il Progetto 1 è rimasto
    invariato; nessuna email è stata inviata, non sono state create pull
    request, release o distribuzioni e non sono stati creati tag;
  - in attesa della revisione Work.

- [ ] **T11.1 - Correzione attese indefinite e verifica finale di consegnabilità**
  - eliminate le attese indefinite note: processi esterni limitati, cleanup
    per identità e guardia AST contro `WaitForExit()` senza timeout;
  - aggiunti e validati timeout PostgreSQL per connessione, lock, query e
    transazioni inattive, con prova reale di rollback e ripresa;
  - aggiunti timeout PDO distinti per connessione/query, rilevamento
    MariaDB/MySQL fail-closed e prova reale di query lenta/host irraggiungibile;
  - Maven esegue tre test Java reali e una falsa asserzione temporanea rende la
    build non riuscita;
  - reso evidente `C:\DriveAura51` e verificato il rifiuto preventivo dei
    percorsi troppo lunghi;
  - superati runner, 21 lint PHP, 5 comandi test PHP, 29 test Django, controlli
    PostgreSQL, 31 casi installer, 6 test mock e build dei due WAR;
  - superate prove finali offline in 42,732 s con Tomcat 11 e 43,334 s con
    Tomcat 9, entrambe con 22 righe/22 lotti, idempotenza e cleanup;
  - candidato riproducibile: 12.855.976 byte, 117 entry/115 payload, SHA-256
    `1019d2cc3f08d5c07e81b129bf786355b5ccd5471dba7d0ad0fa1fbcd6d5442c`;
  - PDF A4 di 3+1 pagine rigenerati e controllati visivamente; Progetto 1
    invariato, nessuna distribuzione, email, release o tag;
  - rapporto `docs/VERIFICA_T11_1.md`: verdetto tecnico `CONSEGNABILE`;
  - in attesa della revisione Work.

- [ ] **T11 - Audit finale e pacchetto di consegna**
  - eseguito l'audit conclusivo rispetto a requisiti, checklist, piano test e
    linee guida originali;
  - corretti i percorsi applicativi permissivi, il connettore Tomcat 11, i
    timeout, la gestione degli handle e l'identità persistente dei processi;
  - superati runner rigoroso/`-AllowPartial`, test PHP/Java/Django, controlli
    PostgreSQL, 27 casi installer e `mvn clean package`;
  - superate prove pulite offline con Tomcat 9 e Tomcat 11 in meno di un
    minuto ciascuna, con 22 righe/22 lotti, idempotenza e cleanup;
  - riconfermate le evidenze massive di 36.176 righe/364 lotti, otto digest,
    resilienza, PK/FK, unicità, domini e progressivi;
  - verificati due build ZIP riproducibili, 111 entry/109 payload, hash e
    assenza di cache, log, `target`, segreti o file estranei;
  - rigenerati e controllati visivamente il manuale A4 di tre pagine e il
    documento A4 di una pagina;
  - completati checklist, rapporto `docs/VERIFICA_T11.md` e bozza email, senza
    distribuzione Altervista, invio, tag o release;
  - candidato T11, ora storico: 12.842.104 byte, SHA-256
    `0184e28030d54518778307efcc0f5f11d8f0c1ab11c540b4ce3aab1286e15bea`;
  - in attesa della revisione Work.

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

- [x] **T09 - Pacchetto offline, installazione sotto cinque minuti e PDF**
  - prodotto pacchetto offline con wheel, WAR, dump, installer e documenti;
  - superata prova pulita in 43,571 secondi wall-clock e 16 casi avversi;
  - verificati archivio, hash, PDF e assenza di artefatti o credenziali;
  - commit pubblicato su `6dcddceebf29181d2d02fe17cd5b0fae99278d3c`.

- [x] **T09.1 - Allineamento tempo del manuale e rigenerazione pacchetto**
  - allineati manuale e PDF ai tempi verificati 43,290/43,571 secondi;
  - rigenerato pacchetto da 12.833.734 byte con SHA-256
    `8008964dfbe07c8158194e4923e3877fcb1c544f8f079174f8d14e029d7a6eae`;
  - PDF interno ed esterno coincidenti con SHA-256
    `38a63b806b1271fdf530d574ecbc32b268dad6af3b12b151acf63df9dc3d4fc7`;
  - commit locale e GitHub verificati su
    `987a4c12db5de84f409cebdde58b3934924e42ff`;
  - revisione Work conclusa senza ulteriori correzioni.

## BLOCCATE

Nessuna.
