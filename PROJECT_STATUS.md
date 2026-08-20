# Stato del progetto

## Stato corrente

La scelta B è approvata: migrazione tramite servizio PHP remoto, servlet Java
intermedia e servizio Django locale verso PostgreSQL.

T00, T01, T01.1, T01.2, T02.1, T02.2, T03, T07, T09 e T09.1 sono
completate. T11 e T11.1 hanno concluso gli audit tecnici e sono in revisione
Work. Il verdetto T11.1 `CONSEGNABILE` resta riferito al pacchetto e alle prove
locali; T13 ha reso operativo il servizio PHP su Altervista, ma ha rilevato
due conteggi remoti non conformi e un certificato HTTPS non valido.

T12 ha pubblicato su GitHub il branch orfano `consegna`. T14 ha rigenerato il
candidato di consegna, che contiene esclusivamente i due allegati indicati
nella bozza email; `main` resta il repository tecnico completo.

T13, T13.1 e T13.2 sono in revisione Work e `AUTORIZZATA` è `Nessuna`. Il fallback
server-only ha risolto il blocco `SetEnv`; health, autenticazione e manifest
sono raggiungibili. T13.1 ha provato che la sola rimozione delle due righe
eccedenti non renderebbe il dataset conforme: esistono anche una riga comune
divergente e tre progressivi diversi dal seed. Nessun DML è stato eseguito.
L'endpoint non deve essere usato dalla servlet finché dataset e HTTPS non
vengono riconciliati con una nuova autorizzazione.

## Esito T14 - bonifica candidato di consegna

- eliminate dal pacchetto le istruzioni obsolete `SetEnv` nel file pubblico
  `.htaccess`; `delivery/ALTERVISTA.md` e il manuale prescrivono ora soltanto
  `remote-php/config/local.php` server-only, fuori da `public`, protetto e non
  tracciato;
- la prova standard è dichiarata offline e locale. Altervista è opzionale e
  non può essere usato dalla servlet finale finché dataset/digest T07 e
  certificato HTTPS valido non sono entrambi disponibili;
- il riferimento storico al manifest `503` in T11.1 è distinto dallo stato
  T13 aggiornato: health 200, manifest anonimo 401 e autenticato 200, con
  endpoint comunque escluso per database divergente e TLS non valido;
- nuovo candidato `dist/drive-aura-51-offline.zip`: 12.861.964 byte,
  SHA-256 `c4b042067784ea5ceb30d21cd5d836dd55e70eb6397628d417d1fa75aa3a4732`,
  sidecar coerente, 120 entry/118 payload, 2 WAR, 7 wheel e 2 PDF;
- `Test-PackageIntegrity.ps1` è passato da una nuova estrazione in percorso
  corto; le quattro pagine PDF A4 sono state renderizzate e controllate, senza
  tagli, sovrapposizioni, caratteri corrotti, margini irregolari o pagine
  superflue. Il branch `consegna` deve essere aggiornato con i soli due file.

## Esito T13.2 - valutazione ripristino completo Altervista

- phpMyAdmin mostra un unico database applicativo, `my_motorizzami`, con
  esattamente le otto tabelle del progetto sanitario; l'importazione del seed
  ufficiale sarebbe quindi circoscritta, senza coinvolgere tabelle estranee;
- il confronto T13.1 conferma che lo schema già presente è coerente con la
  fonte; il seed ufficiale reinizializzerebbe i dati in transazione, ma prima
  richiede un backup completo nuovo e verificabile di tutte le otto tabelle;
- il tentativo di export dal pannello è stato limitato nel tempo e non ha
  creato un nuovo file locale verificabile. Il backup T13.1, esterno al repo,
  copre soltanto tre tabelle e non è un rollback completo del ripristino;
- nessun import, DDL o DML è stato eseguito. Il database resta non conforme a
  T07 nei record/digest già documentati; il pacchetto offline e il branch
  `consegna` restano l'unica consegna pronta e verificata;
- HTTP resta osservato come `200` health, `401` manifest anonimo e `200`
  manifest autenticato. HTTPS non viene modificato: il pannello richiede
  identificazione telefonica e il certificato resta non validabile.

## Esito verifica Altervista del 4 agosto 2026

- Base URL osservato:
  `http://motorizzami.altervista.org/drive-aura-api/remote-php/public`.
- Il codice risolve le otto chiavi da ambiente e poi dal file server-only
  `remote-php/config/local.php`. Il file reale è ignorato e non tracciato;
  l'esempio contiene soltanto placeholder.
- Prima di inserire valori reali è stato verificato HTTP 403 su un file
  innocuo sotto `config`; lo stesso diniego è stato riconfermato direttamente
  su `local.php`. Le sonde sono state rimosse.
- La password precedentemente esposta è stata invalidata con `Ripristina
  accesso` dal pannello. Altervista permette la password locale vuota; dati e
  schema non sono stati modificati.
- `GET /health` ha restituito HTTP 200 con `service=remote-php` e `status=ok`;
  il manifest anonimo ha restituito HTTP 401 `UNAUTHORIZED` e quello
  autenticato HTTP 200 con otto entità.
- Conteggi conformi: `cittadino` 3.200, `patologia` 200,
  `patologia_cronica` 143, `patologia_mortale` 81, `ospedale` 30 e
  `progressivo_ricovero` 30. Conteggi non conformi: `ricovero` 12.001 invece
  di 12.000 e `patologia_ricovero` 20.493 invece di 20.492.
- Il database non è stato corretto e la migrazione massiva non è stata
  avviata. Il vecchio sito, il Progetto 1 e `origin/consegna` sono rimasti
  invariati.
- Il `public` contiene soltanto `.htaccess`, `index.php` e `health`; il file
  Apache pubblico contiene solo routing e non sono rimasti diagnostici o
  segreti raggiungibili via URL.
- HTTPS continua a fallire con `ERR_CERT_AUTHORITY_INVALID`; non è stato usato
  alcun bypass TLS. Il pannello espone l'attivazione, ma la pagina dichiara
  HTTPS disattivato e richiede prima l'identificazione telefonica dell'utente.
- Superati sei test PHP, lint di 23 file, runner rigoroso Java/PHP/Django e
  build di packaging in copia temporanea con 119 payload. `dist` e il branch
  `consegna` non sono stati rigenerati o modificati.
- Rapporto completo: `docs/VERIFICA_ALTERVISTA.md`.

## Esito T13.1 - preflight bonifica Altervista

- Prima di qualunque possibile modifica è stato scaricato un export SQL gzip
  delle sole tabelle `ricovero`, `patologia_ricovero` e
  `progressivo_ricovero`. Il backup, conservato fuori dal repository, misura
  338.342 byte, è apribile e ha SHA-256
  `c6228ba14a60264626635efcd478ce5eb409ca064fbaac5cf25ed52af4876ad9`.
- Gli hash ricalcolati di `schema.sql` e `seed_massivo.sql` coincidono con T07.
  Il server usa InnoDB, non ha trigger sulle tre tabelle e conserva PK/FK
  conformi allo schema.
- Tutte le 12.000 PK `ricovero` e le 20.492 PK `patologia_ricovero` attese
  sono presenti. Le sole PK additive sono `OSP-011/442` e la relativa
  `OSP-011/442/PAT-049`; l'associazione è collegata esattamente al parent.
- Il confronto completo, senza registrare valori personali, ha però trovato
  anche `ricovero` `OSP-007/161` divergente nella sola colonna
  `paziente_cssn` e `prossimo_cod` con delta `+1` per `OSP-011`, `OSP-021` e
  `OSP-024`.
- Eliminando offline soltanto la coppia extra, il digest di
  `patologia_ricovero` torna conforme, ma quello di `ricovero` resta
  `cabd23298f00f6623c91e3a3abc08fc2e1a33fa7b42f87e27e395ee15a1e393b`
  e i progressivi restano discordanti. Il `datasetId` ipotetico sarebbe
  `31846d6dd14eb3ecb8a4b8ed4caf9d6c447fc38dc9a94ac042ed418c14362a66`,
  non quello T07.
- Poiché l'autorizzazione consentiva soltanto due cancellazioni, una bonifica
  parziale non avrebbe soddisfatto l'obiettivo. Non è stata eseguita alcuna
  query DML: conteggi, digest e `datasetId` remoti sono rimasti invariati.
- Verifica finale invariata: health HTTP 200 `status=ok`, manifest anonimo
  HTTP 401, manifest autenticato HTTP 200 con otto entità. Il `datasetId`
  osservato resta
  `abf6a61af736c0bb5d721dbc199f33aa39b48d7656f9ca4221cbb91619904cd8`.
- La funzione HTTPS esiste, ma richiede identificazione telefonica; il
  protocollo risulta disattivato e il test continua a fallire con
  `ERR_CERT_AUTHORITY_INVALID`. Nessun bypass o cambio account è stato fatto.
- Il diagnostico temporaneo è stato rimosso; vecchio sito, Progetto 1,
  `dist`, database e `origin/consegna` sono rimasti invariati.

## Esito T12

- L'autorizzazione Work è stata salvata e pubblicata su `main` nel commit
  `2b86cb85887883b288898b993d286c496351f796` prima di creare il branch di
  consegna.
- `origin/consegna` punta al commit
  `2e67fcebe01f090e175b74b7ca79405e39b13c77`. `rev-list --parents` non
  riporta genitori e la cronologia contiene un solo commit: il branch è
  realmente orfano e non eredita alcuna revisione da `main`.
- Il tree Git remoto contiene, entrambi alla radice, esattamente:
  `drive-aura-51-offline.zip` e `drive-aura-51-offline.zip.sha256`. Non sono
  presenti `.gitignore`, README, documenti, directory o file aggiuntivi.
- Il blob ZIP remoto è `3c3f14908cdd71f10bc98c5600d39fc51288fe2b` e
  quello del sidecar è `0076bae35bed53bfaccf32d9c1f7ad64006ccef4`;
  coincidono con gli object ID calcolati sui due file in `dist`, quindi il
  confronto byte per byte è superato.
- Lo ZIP estratto dal riferimento remoto misura 12.855.976 byte, si apre e ha
  SHA-256
  `1019d2cc3f08d5c07e81b129bf786355b5ccd5471dba7d0ad0fa1fbcd6d5442c`.
  Il sidecar remoto è byte-identico e riporta lo stesso digest seguito dal
  nome `drive-aura-51-offline.zip`.
- La nuova estrazione corta ha superato `Test-PackageIntegrity.ps1`: 117 file
  totali, 115 payload nel manifest, 2 WAR, 7 wheel e 2 PDF. Scansioni di
  denylist e 104 file testuali non hanno trovato segreti, cache, log,
  `target`, runtime o configurazioni locali.
- Il valore di 109 payload appartiene al candidato storico T11 da 12.842.104
  byte. Il candidato T11.1 identificato in modo univoco dalla dimensione e
  dall'hash richiesti contiene 115 payload; per questo non è stato rigenerato
  né modificato.
- La pubblicazione del ramo orfano non ha cambiato checkout, indice, file o
  cronologia di `main`. Il Progetto 1 è rimasto invariato. Non sono state
  inviate email, non sono state create pull request, release o distribuzioni
  Altervista e non sono stati creati tag.

## Revisione Work successiva a T11

La revisione del commit
`406b9976a2236f7fbb091e417309ba312dccf66a` ha riconfermato runner completo,
25 test Django, build Maven dei due WAR, integrità del candidato e 27 casi
installer. Sono rimasti da correggere prima della consegna:

- `delivery/tests/Test-Installer.ps1` usa un `WaitForExit()` senza timeout;
- Django/PostgreSQL non configura scadenze esplicite per connessione, query e
  lock, quindi una risorsa bloccata può trattenere una richiesta;
- PHP/PDO non esplicita limiti di connessione e query compatibili con la
  sorgente MySQL/MariaDB;
- Surefire termina con successo ma rileva zero test Java, benché i contratti
  siano eseguiti dal runner PowerShell;
- PowerShell 5.1 può fallire l'estrazione dello ZIP da un percorso Windows
  molto lungo; il manuale suggerisce già `C:\DriveAura51`, ma serve una
  diagnosi esplicita e verificabile.

Non sono stati rilevati errori nei digest, nell'idempotenza, nei vincoli,
nell'autenticazione o nella struttura del pacchetto. La correzione deve restare
proporzionata a un progetto universitario e ai requisiti già presenti, senza
ampliare l'architettura.

## Esito T11.1

- `WaitForExit()` è sempre limitato; la suite verifica percorso normale,
  timeout, identità del processo, cleanup, rilascio handle e una guardia AST.
- Il runner limita tutti i processi Java/PHP/Python e i server temporanei;
  nessuna attesa PowerShell operativa o di test nota resta senza deadline,
  contatore o progresso monotono.
- Django applica timeout configurabili: connessione 10 s, lock 10 s, statement
  120 s e transazione inattiva 120 s per default. Una prova PostgreSQL 18.4
  con lock da 500 ms ha confermato 503, rollback, checkpoint invariato e
  ripresa recuperabile.
- PHP/PDO usa 3 s per la connessione e 8 s per ogni query per default, con
  rilevamento fail-closed MariaDB/MySQL. MariaDB 12.3.2 ha interrotto una query
  lenta in 1,005 s; connessione irraggiungibile ed errori pubblici sono rimasti
  limitati e sanitizzati.
- Surefire 3.5.4 esegue tre contratti reali; una falsa asserzione nella sola
  copia temporanea ha reso la build non riuscita. `mvn clean package` ha
  prodotto i WAR Tomcat 9/11.
- Runner rigoroso, errore senza runtime, `-AllowPartial`, 21 lint PHP, cinque
  comandi test PHP, 29 test Django, migrazioni PostgreSQL, 31 casi installer e
  sei test del mock remoto sono passati.
- Le prove pulite finali del pacchetto sono terminate in 42,732 s wall-clock
  con Tomcat 11 e 43,334 s con Tomcat 9. Entrambe hanno verificato 22 righe/22
  lotti, repeat idempotente, database operativo vuoto, log puliti e cleanup.
- Il candidato riproducibile misura 12.855.976 byte, contiene 117 entry/115
  payload e ha SHA-256
  `1019d2cc3f08d5c07e81b129bf786355b5ccd5471dba7d0ad0fa1fbcd6d5442c`.
  Tutti i payload coincidono con le sorgenti; scansioni pacchetto e tracking
  non rilevano segreti, cache, log, `target` o ambienti locali.
- Il manuale A4 di tre pagine e le scelte A4 di una pagina sono stati
  rigenerati, renderizzati a 144 dpi e controllati visivamente senza difetti.
- Il dump massivo è stato ricostruito con lo stesso hash e 36.176 righe. Le
  modifiche non alterano contratto, canonicalizzazione, schema, orchestrazione
  o persistenza, quindi la migrazione massiva T07 non è stata ripetuta.
- Il Progetto 1 è pulito e invariato. Il cluster PostgreSQL temporaneo T11.1 è
  stato arrestato dopo verifica di PID, percorso, istante e command line.
- Rapporto completo: `docs/VERIFICA_T11_1.md`.

## Fatti e decisioni verificati

- Il caso B richiede PHP remoto, servlet Java intermedia, Python/Django locale
  e PostgreSQL.
- Django 5.2.16 è fissato per Python 3.12.
- Tomcat 9 usa `javax.servlet` e Java 8+, Tomcat 11 usa `jakarta.servlet` e
  Java 17+; la logica Java comune resta separata dagli adattatori.
- Il Progetto 1 non è stato modificato; schema e dataset sono stati usati
  soltanto in lettura per T07.
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

## Esito T07

- I tre file sorgente del Progetto 1 sono stati usati esclusivamente in
  lettura. `schema.sql` e `seed_massivo.sql` hanno SHA-256
  `f1f162683f987a3f7fae98eba8ef830b03418baf57fe60026c406ca1797d2ada` e
  `0d90404c2cc754d1df5078c04b15a39c941f4070d0ba6f2664f54c3c78bc3972`;
  il Progetto 1 è rimasto pulito e invariato.
- Stato globale e checkpoint per entità sono persistiti in PostgreSQL.
  L'orchestratore riprende da cursore, sequenza e ultima chiave confermati,
  salta le entità completate e ritenta, al massimo due volte per default,
  soltanto richieste idempotenti con errori temporanei.
- Una migrazione reale da PostgreSQL vuoto tramite Tomcat 11.0.24 ha trasferito
  36.176 righe in 364 lotti in `76,306 s`: conteggi
  `3.200/200/143/81/30/12.000/20.492/30`, stato `completed` e dataset
  `75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39`.
- Lo stesso `migrationId` è stato rilanciato tramite Tomcat 9.0.120 in
  `5,743 s` senza nuovi lotti o duplicazioni. La prova interrotta ha fermato
  Tomcat a 18.154 righe/183 lotti; il checkpoint atomico finale era
  18.254/184. Dopo il riavvio, lo stesso `migrationId` ha completato le righe
  restanti in `37,438 s`, tornando a 36.176/364.
- Nella prova di ripresa un timeout remoto e un `503` Django sono stati
  iniettati una sola volta e superati dai retry. Dataset cambiato e digest
  corrotto sono stati rifiutati senza retry come fallimenti definitivi, con
  zero righe importate. Un lotto identico ha restituito `201` e poi `200`
  idempotente; la variante discordante con digest coerente ha restituito
  `409 BATCH_CONFLICT`.
- L'audit SQL fail-fast ha confermato conteggi, PK semplici e composte, FK,
  direttore univoco, domini, associazioni e progressivi
  `MAX(cod) + 1`, tutti senza anomalie. Il ricalcolo indipendente Django ha
  riprodotto il dataset ID e gli otto digest sorgente.
- Il runner rigoroso completo è passato in `4,719 s`, con 33 test Django
  (`0,624 s`) e contratti PHP/Java; `mvn clean package` è passato in
  `4,879 s`, `manage.py check` e `makemigrations --check --dry-run` sono
  passati e i WAR Tomcat 9/11 misurano 71.356/71.371 byte.
- Il dump consegnabile `database/drive-aura-51-source-v2.zip` misura
  407.251 byte, ha SHA-256
  `65204bc3b87b2e01a8a12f4a228dd93ad93d865348e1595efb901c6766d51d38`,
  è rigenerabile in modo deterministico e contiene soltanto SQL, manifest e
  istruzioni di ripristino senza segreti.
- Procedura, tempi, lotti, digest, fault injection e limiti osservati sono
  documentati in `docs/VERIFICA_T07.md`.

## Esito T09

- Il candidato storico T09.1 misurava 12.833.734 byte e aveva
  SHA-256
  `8008964dfbe07c8158194e4923e3877fcb1c544f8f079174f8d14e029d7a6eae`.
  Il manifest verifica 108 file payload; lo ZIP contiene 110 file totali sotto
  un'unica radice.
- Il pacchetto include 78 sorgenti PHP/Java/Django, schema e fixture condivisi,
  7 wheel Windows x64 con hash, i due WAR precompilati, dump/checksum, tre
  configurazioni di esempio, configuratore/verificatore, strumenti e due PDF.
  L'audit non ha trovato cache, log, `target`, runtime, ambienti virtuali,
  credenziali, file IDE o percorsi estranei.
- Il configuratore Windows PowerShell 5.1 rileva Python 3.12 x64, Java,
  Tomcat 9/11 e client/server PostgreSQL 14-18. Crea runtime e
  `CATALINA_BASE` fuori dalla radice immutabile, installa con
  `--no-index --require-hashes` ignorando la configurazione pip esterna,
  trasmette la password libpq soltanto tramite `PGPASSWORD` temporaneo e non
  persiste segreti.
- La prova dall'archivio finale, estratto in un percorso con spazi e con rete
  resa inutilizzabile, ha usato Python 3.12.10, Java 23.0.2,
  Tomcat 11.0.24 e PostgreSQL 18.4/SCRAM. Ha completato configurazione,
  migrazioni, salute, readiness, 22 righe/22 lotti, rilancio idempotente,
  audit e cleanup in 43,290 s interni e 43,571 s wall-clock.
- Il database operativo è rimasto a zero righe; il database di verifica
  separato contiene le 22 righe attese. Lo stato non contiene segreti,
  `processes.json` è stato rimosso e le quattro porte sono state liberate.
  Tomcat 9.0.120 ha superato la stessa prova con il WAR `javax` in 38,822 s;
  il rilancio Tomcat 11 sulla stessa installazione è terminato in 15,897 s.
- Sono passati 16 casi avversi: runtime mancanti/incompatibili, PostgreSQL non
  raggiungibile, porta occupata, segreto mancante, directory estranea,
  wheel/hash alterati, archivio alterato e assenza di rete. Password SCRAM
  errata/corretta, percorsi con spazi e parser PowerShell 5.1 sono stati
  verificati realmente.
- Il runner rigoroso è passato con contratti Java/PHP, routing PHP dalla
  sottocartella pubblicata e 33 test Django. Senza runtime fallisce; con
  `-AllowPartial` riepiloga gli skip. `manage.py check`,
  `makemigrations --check --dry-run` e `migrate --check` sono passati su
  PostgreSQL reale.
- `mvn clean package` è passato in 5,096 s e ha prodotto entrambi i WAR. I 15
  entry di ciascun WAR e i 47 entry del JAR core coincidono con gli artefatti
  precompilati al netto dei timestamp ZIP.
- Il manuale A4 misura 104.563 byte, ha SHA-256
  `38a63b806b1271fdf530d574ecbc32b268dad6af3b12b151acf63df9dc3d4fc7`
  e occupa 3 pagine; le scelte progettuali misurano 98.110 byte e occupano
  1 pagina. Tutte le pagine sono state
  renderizzate a 144 dpi e ispezionate; non restano testo tagliato,
  sovrapposizioni, caratteri corrotti, pagine vuote o superflue.
- Procedura, ambiente, tempi, casi avversi, hash e limiti sono in
  `docs/VERIFICA_T09.md`. Le istruzioni Altervista sono separate e non è stata
  eseguita alcuna distribuzione remota.

## Esito T09.1

- Il manuale sorgente e il PDF riportano ora i due tempi definitivi della
  prova Tomcat 11: 43,290 s misurati dal configuratore e 43,571 s wall-clock.
  Il valore non supportato è assente dal manuale; il tempo Tomcat 9 resta
  invariato a 38,822 s.
- `manuale-drive-aura-51.pdf` misura 104.563 byte, ha SHA-256
  `38a63b806b1271fdf530d574ecbc32b268dad6af3b12b151acf63df9dc3d4fc7`
  e rimane un PDF A4 di tre pagine. Tutte le pagine sono state renderizzate a
  144 dpi e ispezionate: nessun taglio, sovrapposizione, carattere corrotto,
  margine irregolare o pagina superflua.
- Il candidato ricostruito misura 12.833.734 byte e ha SHA-256
  `8008964dfbe07c8158194e4923e3877fcb1c544f8f079174f8d14e029d7a6eae`.
  Sidecar, manifest e hash interni coincidono; il PDF incluso nello ZIP ha lo
  stesso hash dell'originale in `output/pdf`.
- L'audit dell'archivio ha verificato 108 file payload e 110 entry totali
  sotto un'unica radice, senza duplicati, percorsi pericolosi, cache, log,
  `target`, runtime, ambienti virtuali o credenziali. Alla chiusura di T09.1
  nessun codice applicativo era stato modificato e T11 non era ancora
  iniziato.

## Esito T11

- L'audit ha confrontato codice e consegna con le linee guida originali,
  `docs/REQUISITI.md`, `docs/CHECKLIST_PROFESSORE.md` e
  `docs/PIANO_TEST.md`. La checklist è stata compilata; pubblicazione
  Altervista, CC e accessibilità degli allegati restano non selezionati perché
  non eseguiti.
- Sono stati rimossi i percorsi applicativi permissivi: Django operativo usa
  soltanto PostgreSQL e segreti espliciti, import/finalizzazione richiedono
  inizializzazione e checkpoint completi, URL locale/remoto sono vincolati e
  i cursori di ripresa restano autenticati e legati al dataset.
- Il tentativo Tomcat 11 `002` falliva in
  `WEPollSelectorImpl/PipeImpl` con `Unable to establish loopback connection`
  e `Invalid argument: connect`. Il configuratore usa ora il connettore NIO2;
  i log finali Tomcat 9/11 mostrano `http-nio2` e shutdown ordinato.
- Il blocco del PowerShell padre era causato dagli handle di redirezione
  ereditati dai processi persistenti e da un fallback CIM non disponibile.
  Wrapper figli, Job Object Win32, Toolhelp, timeout, cleanup in `finally` e
  verifica PID/percorso/istante chiudono ora l'intero albero senza coinvolgere
  processi estranei.
- I tick di creazione sono serializzati come testo decimale per evitare la
  perdita di precisione JSON di PowerShell 5.1. La regressione round-trip, il
  timeout, l'avvio fallito, il figlio orfano e il rilascio handle sono inclusi
  nei 27 casi installer superati.
- Il medesimo ZIP finale, da copie pulite e con installazione offline, ha
  completato 22 righe/22 lotti, rilancio idempotente, audit e cleanup con
  Tomcat 9 in 44,757 s interni/45,619 s wall-clock e con Tomcat 11 in
  45,504 s interni/46,427 s wall-clock.
- Il runner rigoroso è passato in 5,676 s con contratti Java/PHP e 25 test
  Django. Senza runtime fallisce; `-AllowPartial` termina con tre skip
  espliciti. Sono passati anche 5 test mock, lint di 18 file PHP, controlli
  Django e migrazioni su PostgreSQL reale.
- `mvn clean package` è passato in 4,619 s e ha prodotto entrambi i WAR; il
  contenuto logico coincide con gli artefatti precompilati.
- Le evidenze massive sono state ricalcolate sul dump byte-identico:
  36.176 righe, 364 lotti, dataset
  `75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39`,
  otto digest coincidenti e zero violazioni PK, FK, unicità, domini,
  associazioni o progressivi.
- Due build consecutive del candidato hanno prodotto 12.842.104 byte e
  SHA-256
  `0184e28030d54518778307efcc0f5f11d8f0c1ab11c540b4ce3aab1286e15bea`.
  L'audit ha verificato 111 entry/109 payload, sidecar e hash interni, senza
  cache, log, `target`, runtime, credenziali o percorsi pericolosi.
- Il manuale finale misura 105.128 byte e ha SHA-256
  `044a319077888a56ce021b520277439314fc0fce88a624b82e8464340829e2c1`;
  le scelte misurano 98.110 byte e hanno SHA-256
  `350ee05ca081d86d9bfb9a2d0af095c03e141e5c1533016f0728a5dbf7a79428`.
  Le quattro pagine A4 sono state renderizzate a 144 dpi e ispezionate senza
  difetti visivi.
- Rapporto e bozza email sono in `docs/VERIFICA_T11.md` e
  `docs/BOZZA_EMAIL_CONSEGNA.md`.

## Limiti residui

- PHP, Django, MariaDB, PostgreSQL e Tomcat usati nel collaudo erano runtime
  portabili temporanei e non sono componenti della consegna.
- La prova massiva è locale: non è una distribuzione Altervista e non usa
  credenziali remote. Il dataset del Progetto 1 è sintetico ed è stato
  consultato soltanto come sorgente in sola lettura.
- Nella prova offline la scheda di rete non è stata disabilitata fisicamente:
  proxy non raggiungibili, configurazione pip ostile e `--no-index` hanno
  impedito l'uso della rete da parte della procedura.
- La verifica rapida T09 usa una sorgente contrattuale loopback e non sostituisce
  il collaudo PHP/PDO massivo già osservato in T07.
- L'email non è stata inviata: destinatari CC e accessibilità degli allegati
  devono essere verificati immediatamente prima della consegna.

## Revisione Work T02.2

Il 24 luglio 2026 Work ha verificato nuovamente:

- commit locale, `origin/main` e ramo GitHub coincidenti su
  `fc90d808857caf156fa929a157faf745d8a0570f`;
- runner completo con contratti Java/PHP e 18 test Django;
- `mvn clean package` e produzione dei WAR Tomcat 9 e Tomcat 11;
- `makemigrations --check --dry-run` senza modifiche mancanti;
- assenza di artefatti, cache e credenziali reali dai file tracciati.

T02.2 è approvata senza correzioni bloccanti.

## Revisione Work T03

Il 25 luglio 2026 Work ha verificato:

- commit locale, `origin/main` e GitHub coincidenti su
  `d86d474a700f168421f00286b0336eeea64aec25`;
- schema condiviso completo per le otto entità;
- runner completo con contratti PHP/Java e 25 test Django;
- migrazioni e vincoli per PK/FK, chiavi composte e progressivi;
- `mvn clean package` e produzione dei due WAR;
- assenza di artefatti, cache e credenziali dai file tracciati.

T03 è approvata senza correzioni bloccanti. Nel Progetto 1 sono disponibili,
in sola lettura, `database/schema.sql` e `database/seed_massivo.sql` con
l'intero dataset atteso; T07 non richiede accesso ad Altervista.

## Revisione Work T07

Il 25 luglio 2026 Work ha verificato:

- commit locale, `origin/main` e GitHub coincidenti su
  `2c0e52b34c711873fdf92533bff9beec6d3b6878`;
- archivio sorgente da 407.251 byte con SHA-256
  `65204bc3b87b2e01a8a12f4a228dd93ad93d865348e1595efb901c6766d51d38`
  e contenuto coerente con il manifest;
- implementazione di checkpoint, resume e retry limitati;
- runner completo con 33 test Django e contratti PHP/Java;
- `mvn clean package` e produzione dei due WAR;
- assenza di cache, credenziali e artefatti temporanei tracciati.

T07 è approvata senza correzioni bloccanti.

## Prossimo passo

Attendere la revisione Work di T13, T13.1 e T13.2. `AUTORIZZATA` è `Nessuna`;
un eventuale ripristino remoto richiede anzitutto un export completo
verificabile fuori dal repository, quindi nuova autorizzazione per importare
il seed ufficiale e ripetere manifest/digest. L'attivazione HTTPS richiede una
scelta e l'identificazione telefonica dell'utente nel pannello. L'email resta
una bozza e non deve essere inviata automaticamente. Non lanciare la
migrazione massiva, non modificare il Progetto 1, non unire o modificare
`consegna` e non creare tag o release.
