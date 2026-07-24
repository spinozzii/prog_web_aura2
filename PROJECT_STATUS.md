# Stato del progetto

## Stato corrente

La scelta B è approvata: migrazione tramite servizio PHP remoto, servlet Java
intermedia e servizio Django locale verso PostgreSQL.

T00, T01, T01.1, T01.2, T02.1 e T02.2 sono completate. Le precedenti
T03-T06 sono accorpate in T03, ora in revisione dopo l'estensione della
verticale a tutte le entità. Non esiste alcuna attività autorizzata.

## Fatti e decisioni verificati

- Il caso B richiede PHP remoto, servlet Java intermedia, Python/Django locale
  e PostgreSQL.
- Django 5.2.16 è fissato per Python 3.12.
- Tomcat 9 usa `javax.servlet` e Java 8+, Tomcat 11 usa `jakarta.servlet` e
  Java 17+; la logica Java comune resta separata dagli adattatori.
- Il Progetto 1 è una fonte in sola lettura e non è stato coinvolto.
- `origin` è `https://github.com/spinozzii/prog_web_aura2.git` e `main` segue
  `origin/main`.

## Esito T02.1

- `docs/CONTRATTO_DATI.md` definisce il contratto eseguibile di `patologia`:
  ordine dei campi, serializzazione JSON compatta, UTF-8 senza BOM, escape,
  slash invariati, ordinamento per `cod`, LF finale e SHA-256.
- La fixture `tests/fixtures/patologia-canonical.json` include record leggibili
  con accenti, virgolette, barra rovesciata, newline, slash e criticità 1/5.
  Il digest previsto è
  `53f27d16f82cdf36bbdb1bd28b61bc6cf7f7057d5cc135a66c2bd9105cc27b83`.
- PHP, Java core compatibile Java 8 e Python implementano ognuno una sola
  funzione di canonicalizzazione e digest senza nuove dipendenze applicative.
- Il runner completo con PHP 8.3.32, Python 3.12.13/Django 5.2.16 e Java ha
  superato salute e canonicalizzazione in tutti e tre i linguaggi.
- Senza runtime nel PATH il runner fallisce; `-AllowPartial` termina con
  riepilogo esplicito degli skip.
- `mvn clean package` con Maven 3.9.16 ha superato la compilazione Java e ha
  prodotto entrambi i WAR Tomcat 9 e Tomcat 11.
- Gli endpoint `/health` non sono stati modificati. Non sono stati implementati
  manifest, export, orchestrazione, importazione, PostgreSQL o accesso ai dati.

La revisione Work ha ripetuto con successo il runner completo, la build Maven
e la verifica del ramo GitHub. È stato rilevato un caso limite non coperto:
PHP restituisce un `LF` per una lista vuota, mentre Java e Python restituiscono
zero byte. La fixture principale e il digest dichiarato sono corretti; la
normalizzazione del caso vuoto è obbligatoria come primo punto di T02.2.

## Esito T02.2

- La sequenza vuota produce ora zero byte e
  `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
  in PHP, Java e Python; `tests/fixtures/patologia-empty.json` è il vettore
  condiviso di regressione. Un secondo vettore verifica inoltre U+2028/U+2029
  come byte UTF-8 non sottoposti a escape nei tre linguaggi.
- PHP espone manifest ed export di `patologia` con Bearer d'ambiente, JSON
  UTF-8, whitelist, massimo 100, paginazione keyset, cursore HMAC con scadenza
  e binding a dataset/entità, doppio controllo del dataset e PDO
  MySQL/MariaDB preparato. La sorgente fixture resta confinata ai test.
- Django 5.2.16 con `psycopg[binary]` 3.3.4 definisce le tabelle PostgreSQL
  `patologia`, `migration_run` e `migration_batch`; valida schema, tipi,
  domini, ordine, conteggi e digest e applica lotti, registro e dati nella
  stessa transazione. Duplicati uguali sono idempotenti, quelli diversi sono
  conflitti e la finalizzazione ricontrolla dati e digest effettivi.
- Il core Java compatibile Java 8 legge manifest e pagine, verifica
  dataset/cursori/ordine/conteggi/digest, inoltra i lotti e convalida la
  finalizzazione con timeout e limiti. Gli adattatori espongono
  `POST /api/v1/migrations` sia su Tomcat 9/`javax` sia su Tomcat
  11/`jakarta`; `/health` è rimasto funzionante.
- Il runner rigoroso completo è passato con PHP 8.3.32, Python 3.12.10,
  Django 5.2.16 e Java 23/core `--release 8`: test PHP, orchestratore Java e
  18 test Django tutti superati. Senza runtime fallisce; `-AllowPartial`
  termina con riepilogo esplicito degli skip.
- `mvn clean package` è passato e ha prodotto
  `bridge-tomcat9-0.1.0.war` e `bridge-tomcat11-0.1.0.war`.
- È stata osservata una prova reale con MariaDB 12.3.2, PHP/PDO, Tomcat
  11.0.24, Django/psycopg e PostgreSQL 18.4: tre righe, tre pagine/lotti,
  digest
  `1a0c031432423ef5812f87e7c2e7b712c87c95538c935bd2f2e17b54c9e22612`
  e stato `completed`. PostgreSQL ha confermato `3` righe, `1` run e `3`
  batch contigui. Il rilancio con lo stesso `migrationId` è rimasto
  idempotente sia su Tomcat 11 sia su Tomcat 9.
- Bearer errato è stato rifiutato via HTTP; casi avversi di cursore, entità,
  limite, digest, sequenza, rollback, duplicato diverso e finalizzazione
  incompleta sono coperti dai test isolati.
- La procedura e l'esito osservato sono in `docs/VERIFICA_T02_2.md`;
  `scripts/verify-patologia-migration.ps1` è il comando ripetibile.

## Esito T03

- `shared/entity-schema.json` definisce le otto entità in ordine vincolante,
  con campi, tipi, limiti, chiavi semplici/composte, FK e unicità.
  `tests/fixtures/t03-dataset.json` contiene 22 righe relazionali, byte
  canonici e digest attesi; il `datasetId` globale verificato è
  `1994520ec6762723e7c1b32a9d8b40d8f4028f2c137a0aaa950298da680418a7`.
- PHP usa una sola pipeline schema-driven per manifest, PDO, pagine keyset,
  canonicalizzazione e digest. Le tuple complete entrano nel cursore HMAC v2;
  query e placeholder sono preparati, l'ordine testuale è binario e il
  dataset globale è ricontrollato prima e dopo ogni pagina.
- Django definisce tutte le tabelle PostgreSQL, incluse le PK composte e una
  FK composta reale da `patologia_ricovero` a `ricovero`. Registra run e lotti
  per entità, applica ogni lotto in transazione e verifica ordine, FK, direttore
  univoco, digest, associazioni, progressivi e `datasetId` globale.
- Il core Java resta compatibile Java 8 e orchestra le otto entità senza
  accesso ai database; il risultato finale espone ordine, conteggi, lotti e
  digest per entità. Gli adattatori Tomcat 9 e Tomcat 11 restano separati e
  gli endpoint `/health` sono invariati.
- Il runner rigoroso completo finale è passato in `4,897 s` con Java 23/core
  `--release 8`, PHP 8.3.32 e Python 3.12.10/Django 5.2.16. Sono passati 25
  test Django; `manage.py check` non ha rilevato problemi e
  `makemigrations --check --dry-run` non ha rilevato modifiche.
- `mvn clean package` è passato in `5,395 s` e ha prodotto i WAR Tomcat 9
  (`57.405` byte) e Tomcat 11 (`57.422` byte). Senza runtime il runner
  rigoroso fallisce; `-AllowPartial` mostra gli skip e il riepilogo.
- È stata osservata la verticale reale con MariaDB 12.3.2, `pdo_mysql`,
  Tomcat 11.0.24, Django/psycopg e PostgreSQL 18.4: 22 righe e 22 lotti,
  otto finalizzazioni e stato `completed` in `2,643 s`.
- L'audit PostgreSQL ha confermato i conteggi `3/4/2/2/2/3/4/2`, nessun
  duplicato delle PK composte, nessuna FK orfana, nessun direttore duplicato,
  una patologia per ogni ricovero e progressivi uguali a `MAX(cod) + 1`.
  Date, decimali a due cifre, accenti e caratteri da sottoporre a escape sono
  rimasti integri.
- Lo stesso `migrationId` è stato rilanciato attraverso Tomcat 9.0.120 in
  `2,027 s`: PostgreSQL è rimasto a otto run, 22 lotti e 22 righe, quindi il
  rilancio è stato realmente idempotente. Tutti i runtime temporanei sono
  stati arrestati.
- Casi avversi di ordine, tuple, cursore, dataset cambiato, data/decimale,
  schema, FK, unicità, digest/conteggio, rollback, associazione e progressivo
  sono coperti dai test. Procedura ed evidenze sono in
  `docs/VERIFICA_T03.md`.

## Limiti residui

- PHP, Django, MariaDB, PostgreSQL e Tomcat usati nel collaudo erano runtime
  portabili temporanei e non sono componenti della consegna.
- La verticale completa ha usato una fixture controllata di 22 righe: non è
  una distribuzione Altervista, non ha coinvolto Progetto 1 e non è la futura
  prova sul dataset massivo.
- Installatore finale, dipendenze offline, dataset massivo e documenti PDF
  restano attività di backlog e non sono stati iniziati.

## Revisione Work T02.2

Il 24 luglio 2026 Work ha verificato nuovamente:

- commit locale, `origin/main` e ramo GitHub coincidenti su
  `fc90d808857caf156fa929a157faf745d8a0570f`;
- runner completo con contratti Java/PHP e 18 test Django;
- `mvn clean package` e produzione dei WAR Tomcat 9 e Tomcat 11;
- `makemigrations --check --dry-run` senza modifiche mancanti;
- assenza di artefatti, cache e credenziali reali dai file tracciati.

T02.2 è approvata senza correzioni bloccanti.

## Prossimo passo

Revisionare T03. Non iniziare T07, T08 o altre attività senza una nuova
autorizzazione esplicita.
