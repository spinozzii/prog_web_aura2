# Verifica della pubblicazione Altervista

Data iniziale: 4 agosto 2026. Aggiornamento finale: 20 agosto 2026.

## Esito

**OPERATIVA E CONFORME — HTTPS valido, dataset T07 coincidente e verticale
reale completata.**

Il servizio PHP è pubblicato all'indirizzo:

`https://motorizzami.altervista.org/drive-aura-api/remote-php/public`

Il limite iniziale è risolto: l'account non propaga le direttive `SetEnv` a
PHP, ma il caricatore usa configurazione server-only fuori da `public`.
L'identificazione richiesta dal provider è stata completata manualmente
dall'utente; HTTPS presenta ora un certificato valido. Il collaudo finale ha
restituito:

- `GET /health`: HTTPS 200 diretto, senza redirect, `service=remote-php` e
  `status=ok`;
- `GET /api/v1/manifest` senza Bearer: HTTP 401 `UNAUTHORIZED`;
- la stessa richiesta con Bearer corretto: HTTP 200, otto entità, conteggi e
  digest identici a T07.

L'endpoint è quindi utilizzabile come sorgente remota reale della servlet.
La verifica standard della consegna resta il percorso offline, più semplice e
ripetibile per il docente; Altervista è un'integrazione reale opzionale.

## Evidenza finale T15

### HTTPS, routing e protezione

Il pannello Altervista dichiara HTTPS attivo. Il certificato è stato validato
senza bypass TLS. Entrambe le forme `/health` e `/health/` rispondono in HTTPS
con 200; la forma senza slash non emette più il precedente redirect verso
HTTP. La correzione Apache usa `DirectorySlash Off`,
`RewriteOptions AllowNoSlash` e instrada entrambe le forme al front controller.

La cartella pubblica contiene soltanto `.htaccess`, `health/` e `index.php`.
Non sono presenti diagnostici o file con segreti. Gli accessi diretti a
`config/` e ai file privati restituiscono 403.

### Backup e riallineamento del database

Prima di qualunque modifica è stato esportato da phpMyAdmin un backup SQL
completo delle otto tabelle. Il file, conservato fuori dal repository, è stato
aperto, ispezionato e ripristinato in un MariaDB isolato:

- dimensione: 2.495.836 byte;
- SHA-256:
  `fd8ef3b3153ca742ccd765b039e0b76046171fd32f73236c4b075d5acec7d8a3`;
- conteggi ripristinati: 3.200/200/143/81/30/12.001/20.493/30.

Il backup ha confermato che il database remoto contiene soltanto le otto
tabelle sanitarie. Il confronto semantico ha inoltre rilevato l'assenza di
cinque vincoli `CHECK`; per questo non è stato usato un semplice seed su uno
schema potenzialmente divergente. È stato importato una sola volta un rebuild
limitato alle otto tabelle, composto dallo schema e dal seed ufficiali del
Progetto 1, verificati byte per byte. phpMyAdmin ha completato 148 query in
3,122 secondi. Nessuna tabella estranea è stata modificata e i vincoli sono
rimasti attivi nello schema finale.

### Manifest finale

| Entità | Righe | Digest SHA-256 |
|---|---:|---|
| `cittadino` | 3.200 | `308b6ef1e27d1d6087b52ed0168856b1d8420b1262c7a6bcf1b550c244f77f70` |
| `patologia` | 200 | `3173f4a9db15ebdf33223cba36f1860cdb730695716e428865868691bd420c27` |
| `patologia_cronica` | 143 | `17de8da61d5469e012058ce10d667e1e9a8442acab744bd9c64529814a927f2b` |
| `patologia_mortale` | 81 | `f96723546479571cd2b78d9ded97676443e561c7766b365c8e2517fbe244183d` |
| `ospedale` | 30 | `fa37fd03a5f4eeee9f02fb682b00053862cde09ccbf25fe1583635fc9fe04963` |
| `ricovero` | 12.000 | `ff1640d12101c1df35a3c484dd3c541e26bf58a68b63fc42c68aba5ac46105ca` |
| `patologia_ricovero` | 20.492 | `357043b4bf2e5fec2f461038b3bbce5e546a2d82f8b1d635105709504ea574ed` |
| `progressivo_ricovero` | 30 | `687077ef4989a82595a3570b388829bbcb1bf51813fc0dfeaf83eee9fac7d653` |

Il totale è 36.176 righe e il `datasetId` coincide con T07:
`75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39`.

### Verticale reale e idempotenza

Da un PostgreSQL 18 vuoto è stata osservata la verticale completa:

`Altervista HTTPS -> PHP/PDO -> servlet Tomcat 11 -> Django -> PostgreSQL`.

La migrazione ha concluso 36.176 righe in 364 lotti, stato `completed`, in
117,637 secondi applicativi e 122,139 secondi wall-clock. L'audit indipendente
ha confermato gli otto digest, zero duplicati PK, zero FK orfane, univocità,
domini e progressivi. Il rilancio con lo stesso `migrationId` è terminato
idempotentemente in 2,748 secondi. Lo stesso stato è stato poi riletto e
rilanciato tramite il WAR Tomcat 9 in 3,089 secondi, seguito da un secondo
rilancio idempotente in 3,002 secondi.

Non sono stati registrati payload personali o segreti. Il Progetto 1 è
rimasto in sola lettura e il vecchio sito Altervista non è stato cancellato.

### Candidato di consegna aggiornato

Manuale e scelte progettuali sono stati rigenerati, renderizzati e controllati
su tutte le pagine: A4, 3+1 pagine, senza tagli, sovrapposizioni o caratteri
corrotti. Il nuovo ZIP misura 12.862.977 byte e ha SHA-256
`4805ac6632e38c51985b0b628dc3f719fc10b0f4f4c4177746bfa9dd10fa79c7`.
L'integrità è stata riconfermata da una nuova estrazione in percorso corto:
121 entry/119 payload, 2 WAR, 7 wheel e 2 PDF, senza segreti, cache, log,
`target` o runtime temporanei.
La suite installer finale ha superato 32/32 casi, compresa la regressione per
un processo che termina durante la verifica di identità del cleanup.

## Configurazione server-only

Il codice risolve ciascuna delle otto chiavi autorizzate con questa precedenza:

1. variabile d'ambiente, se presente;
2. `drive-aura-api/remote-php/config/local.php`, soltanto per le chiavi
   mancanti.

Il repository contiene solo `remote-php/config/local.php.example`, privo di
valori reali. `local.php` è ignorato da Git, non è stato creato nel checkout e
non appartiene al candidato offline.

Sul server è stato caricato prima `remote-php/config/.htaccess`. Un file di
prova innocuo nella stessa directory ha restituito HTTP 403 tramite URL
diretto; il file è stato rimosso prima di creare `local.php`. Dopo la
configurazione, una richiesta diretta allo stesso `local.php` ha riconfermato
HTTP 403. Il `.htaccess` sotto `public` contiene ora soltanto le regole di
routing e nessuna direttiva `SetEnv` con credenziali.

I segreti API e cursore sono lunghi, casuali e distinti. Nessun valore reale è
stato registrato nella documentazione, nei log o nel repository.

## Stato storico T13: rotazione dell'accesso database

La configurazione era stata inizialmente caricata come normale file pubblico
`htaccess`; la password allora presente deve quindi essere considerata
compromessa. Con l'autorizzazione T13 è stato eseguito dal pannello Altervista
`Ripristina accesso`, che ha confermato il ripristino e ha invalidato la
password precedente. L'account accetta l'accesso locale con password
facoltativa vuota, valore usato dal file server-only.

Il ripristino non ha modificato dati o schema. Non sono state eseguite query
di scrittura, importazioni o migrazioni.

## Stato storico T13: conteggi osservati

| Entità | Atteso | Osservato | Esito |
|---|---:|---:|---|
| `cittadino` | 3.200 | 3.200 | conforme |
| `patologia` | 200 | 200 | conforme |
| `patologia_cronica` | 143 | 143 | conforme |
| `patologia_mortale` | 81 | 81 | conforme |
| `ospedale` | 30 | 30 | conforme |
| `ricovero` | 12.000 | 12.001 | **una riga eccedente** |
| `patologia_ricovero` | 20.492 | 20.493 | **una riga eccedente** |
| `progressivo_ricovero` | 30 | 30 | conforme |

Il manifest autenticato è quindi strutturalmente corretto, ma il database
Altervista non coincide con il dataset massivo verificato in T07. Come
richiesto, il collaudo si è fermato senza modificare o cancellare righe e
senza avviare la migrazione massiva.

## Preflight T13.1 della bonifica minima

Prima di qualunque possibile query di scrittura è stato esportato da
phpMyAdmin `drive-aura-t13-1-precleanup.sql.gz`, limitato a struttura e dati di
`ricovero`, `patologia_ricovero` e `progressivo_ricovero`. Il backup è
conservato fuori dal repository, è apribile e misura 338.342 byte; SHA-256:

`c6228ba14a60264626635efcd478ce5eb409ca064fbaac5cf25ed52af4876ad9`

Il flusso decompresso misura 2.170.951 byte e ha SHA-256
`1e73aedb67a3f6812e5f1d4efc729522460a8f267ff44bda8affbedf98251a9a`.
Non ne sono stati registrati payload o valori personali.

Le fonti ufficiali in sola lettura sono state riconfermate prima del
confronto:

- `database/schema.sql`: 4.721 byte, SHA-256
  `f1f162683f987a3f7fae98eba8ef830b03418baf57fe60026c406ca1797d2ada`;
- `database/seed_massivo.sql`: 2.469.421 byte, SHA-256
  `0d90404c2cc754d1df5078c04b15a39c941f4070d0ba6f2664f54c3c78bc3972`.

Il preflight remoto ha verificato tre tabelle InnoDB, zero trigger, PK e FK
coincidenti con lo schema. La differenza bidirezionale delle chiavi tecniche
ha prodotto:

- nessuna PK attesa mancante;
- una sola PK `ricovero` extra: `OSP-011/442`;
- una sola PK `patologia_ricovero` extra: `OSP-011/442/PAT-049`, collegata
  esattamente al ricovero extra;
- impronta delle 12.000 PK `ricovero` attese:
  `674b75cb873e43d67754db152acfdeb99295f6c0f1df005f196c4acb08877089`;
- impronta delle 20.492 PK `patologia_ricovero` attese:
  `413927b0c132dd299eaf70a3269f8ce50a1292811a4088a88f35f5f30ffa6970`.

La coppia extra è dunque identificata con certezza come additiva e assente
dal seed. Il confronto completo del backup ha però rilevato anche differenze
che non sono cancellazioni autorizzate:

- `ricovero` `OSP-007/161`: stessa PK del seed, sola colonna
  `paziente_cssn` divergente, senza registrare i valori;
- `progressivo_ricovero` `OSP-011`, `OSP-021` e `OSP-024`: `prossimo_cod`
  maggiore di uno rispetto al seed; per `OSP-021` e `OSP-024` il valore è già
  incoerente con `MAX(cod) + 1` prima di qualunque bonifica.

Il digest canonico di `patologia_ricovero`, escludendo la sola associazione
extra, coincide con T07. Quello di `ricovero`, escludendo il solo ricovero
extra, resta invece
`cabd23298f00f6623c91e3a3abc08fc2e1a33fa7b42f87e27e395ee15a1e393b`
e non coincide con T07. Anche il digest dei progressivi resta divergente. Il
`datasetId` ipotetico dopo le sole due cancellazioni sarebbe
`31846d6dd14eb3ecb8a4b8ed4caf9d6c447fc38dc9a94ac042ed418c14362a66`,
non quello atteso da T07
`75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39`.

Per questo la rimozione delle sole due righe avrebbe corretto i conteggi ma
lasciato il dataset non conforme. L'autorizzazione consentiva esclusivamente
quelle cancellazioni, non la sostituzione di una riga comune né tre update dei
progressivi: **non è stata eseguita alcuna query DML e il database è rimasto
invariato**.

### Manifest finale osservato, database invariato

| Entità | Righe | Digest osservato | Digest T07 |
|---|---:|---|---|
| `cittadino` | 3.200 | `308b6ef1e27d1d6087b52ed0168856b1d8420b1262c7a6bcf1b550c244f77f70` | coincide |
| `patologia` | 200 | `3173f4a9db15ebdf33223cba36f1860cdb730695716e428865868691bd420c27` | coincide |
| `patologia_cronica` | 143 | `17de8da61d5469e012058ce10d667e1e9a8442acab744bd9c64529814a927f2b` | coincide |
| `patologia_mortale` | 81 | `f96723546479571cd2b78d9ded97676443e561c7766b365c8e2517fbe244183d` | coincide |
| `ospedale` | 30 | `fa37fd03a5f4eeee9f02fb682b00053862cde09ccbf25fe1583635fc9fe04963` | coincide |
| `ricovero` | 12.001 | `de0fcb874311c842e7786e4131473c3d1fcdc24c796551c4b0c8ab7d150d386c` | diverso |
| `patologia_ricovero` | 20.493 | `617b7c37f672dfecb2f68066a57bb45336846f1a6744978a39fb8322c97f483e` | diverso |
| `progressivo_ricovero` | 30 | `39239408ac69ff84a95cfd07a2b382dd6faca8e9734f34d976088f43f996ad42` | diverso |

Il `datasetId` finale osservato è
`abf6a61af736c0bb5d721dbc199f33aa39b48d7656f9ca4221cbb91619904cd8`.
Nello stesso collaudo `/health` ha restituito ancora HTTP 200 `status=ok`, il
manifest anonimo HTTP 401 e quello autenticato HTTP 200 con otto entità.

## Stato storico T13.1: HTTPS

Il tentativo su
`https://motorizzami.altervista.org/drive-aura-api/remote-php/public/health`
ha restituito `ERR_CERT_AUTHORITY_INVALID`. Nel pannello già autenticato la
ricerca funzioni ha ora individuato
`HTTPS - Attiva il protocollo HTTPS`: la pagina dichiara il protocollo
disattivato e richiede identificazione mediante numero telefonico prima di
procedere. Non è stato inserito né richiesto alcun numero e non è stata
modificata l'impostazione dell'account.

Non è stato usato alcun bypass della verifica TLS. Finché il provider non
espone un certificato valido, l'endpoint non deve essere configurato nella
servlet né usato per una migrazione reale.

## Stato storico T13.1: pulizia e confini verificati

Al termine la cartella pubblica contiene soltanto:

```text
.htaccess
health/
index.php
```

Non sono presenti `htaccess`, `manifest-test.php`,
`manifest-local-test.php`, `route-check.html`, `t131-check.html` o altri
diagnostici pubblici.
La directory `config` contiene soltanto il diniego `.htaccess` e il file
server-only `local.php`; la directory `src` contiene il nuovo
`RuntimeConfig.php` e il `PdoEntitySource.php` aggiornato, senza file di prova.

Il vecchio sito non è stato cancellato. Il Progetto 1 è rimasto in sola
lettura, il branch `consegna` non è stato modificato e il database non è stato
alterato. Non è stata lanciata la migrazione massiva.

## Verifiche locali precedenti

- PHP 8.3.32: sei comandi di test superati; il test PDO d'integrazione ha
  prodotto lo skip previsto quando non richiesto;
- lint PHP: 23 file su 23 validi;
- runner rigoroso: contratti Java e PHP superati, 29 test Django superati con
  uno skip previsto, system check senza problemi;
- il giro T13.1 ha riconfermato gli stessi sei comandi PHP, il lint dei 23
  file e il runner rigoroso usando esclusivamente runtime portatili locali;
- i due script PowerShell di packaging modificati superano il parser;
- una build in copia temporanea ha superato l'integrità con 119 payload,
  2 WAR, 7 wheel e 2 PDF;
- il candidato `dist` e il branch orfano `consegna` non sono stati rigenerati
  o modificati.

## Limite storico prima di T15

Il fallback di configurazione è funzionante e non espone segreti. Restano due
blocchi esterni al codice pubblicato:

1. autorizzare una riconciliazione completa, non limitata alle due righe
   extra: ripristino dal seed della riga comune divergente, correzione dei tre
   progressivi e cancellazione figlio-padre della coppia extra;
2. completare dal pannello l'identificazione telefonica richiesta per
   attivare HTTPS e poi validare il certificato.

Fino ad allora lo stato remoto resta parzialmente operativo e non va usato
per la migrazione completa.

## Valutazione rapida T13.2 del 4 agosto 2026

La nuova autorizzazione ha richiesto di verificare se fosse possibile un
ripristino sicuro e circoscritto dell'intero dataset. phpMyAdmin espone il
solo database applicativo `my_motorizzami`: contiene esattamente le otto
tabelle sanitarie, tutte InnoDB, senza tabelle estranee da preservare. Lo
schema era già stato confrontato in T13.1 con la fonte ufficiale; il seed
ufficiale è quindi il meccanismo adatto per reinizializzare i dati, senza
modificare Progetto 1.

Prima dell'import era però necessario un nuovo backup completo, esterno al
repository e verificabile. Il comando di export phpMyAdmin è stato inviato con
una scadenza di 20 secondi per il rilevamento del download e un controllo
locale successivo: non è comparso alcun nuovo file scaricato. Il backup T13.1
resta integro ma copre volutamente soltanto `ricovero`,
`patologia_ricovero` e `progressivo_ricovero`; non è un rollback sufficiente
per un seed che reinizializza tutte le otto tabelle.

Di conseguenza non è stata eseguita alcuna importazione né query DDL/DML. Il
database remoto resta nello stato e con i digest già riportati sopra. La
consegna verificata resta il pacchetto offline pubblicato anche sul branch
orfano `consegna`; Altervista è un'integrazione aggiuntiva non usabile dalla
servlet finché non sono disponibili un backup completo verificato, dataset
allineato e certificato HTTPS valido. Nessun workaround HTTPS è stato tentato.

I controlli locali proporzionati non hanno modificato il codice: sei test PHP
sono passati (l'integrazione PDO ha prodotto lo skip previsto) e il lint ha
validato 23 file. Il runner condiviso ha superato i contratti Java e PHP; la
parte Django non è stata rieseguita perché il runtime portatile disponibile
punta a una dipendenza temporanea non leggibile. Questo limite locale non
incide sui file PHP né sul pacchetto, già verificati in T11.1.
