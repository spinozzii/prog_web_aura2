# Verifica della pubblicazione Altervista

Data: 4 agosto 2026.

## Esito

**PARZIALMENTE OPERATIVA — API corretta, dataset remoto e HTTPS non conformi.**

Il servizio PHP è pubblicato all'indirizzo:

`http://motorizzami.altervista.org/drive-aura-api/remote-php/public`

Il limite iniziale è risolto: l'account non propaga le direttive `SetEnv` a
PHP, ma il nuovo caricatore usa il file server-only e permette alle API di
raggiungere autenticazione e database. Il collaudo osservato ha restituito:

- `GET /health`: HTTP 200, `service=remote-php`, `status=ok`;
- `GET /api/v1/manifest` senza Bearer: HTTP 401 `UNAUTHORIZED`;
- la stessa richiesta con Bearer corretto: HTTP 200 e otto entità.

La pubblicazione non è però approvabile come sorgente della servlet: due
conteggi eccedono di una riga il dataset atteso e l'URL HTTPS non supera la
validazione del certificato.

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

## Rotazione dell'accesso database

La configurazione era stata inizialmente caricata come normale file pubblico
`htaccess`; la password allora presente deve quindi essere considerata
compromessa. Con l'autorizzazione T13 è stato eseguito dal pannello Altervista
`Ripristina accesso`, che ha confermato il ripristino e ha invalidato la
password precedente. L'account accetta l'accesso locale con password
facoltativa vuota, valore usato dal file server-only.

Il ripristino non ha modificato dati o schema. Non sono state eseguite query
di scrittura, importazioni o migrazioni.

## Conteggi osservati

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

## HTTPS

Il tentativo su
`https://motorizzami.altervista.org/drive-aura-api/remote-php/public/health`
ha restituito `ERR_CERT_AUTHORITY_INVALID`. Nel pannello già autenticato non è
stata trovata un'opzione HTTPS/SSL o certificato nelle funzioni disponibili.

Non è stato usato alcun bypass della verifica TLS. Finché il provider non
espone un certificato valido, l'endpoint non deve essere configurato nella
servlet né usato per una migrazione reale.

## Pulizia e confini verificati

Al termine la cartella pubblica contiene soltanto:

```text
.htaccess
health/
index.php
```

Non sono presenti `htaccess`, `manifest-test.php`,
`manifest-local-test.php`, `route-check.html` o altri diagnostici pubblici.
La directory `config` contiene soltanto il diniego `.htaccess` e il file
server-only `local.php`; la directory `src` contiene il nuovo
`RuntimeConfig.php` e il `PdoEntitySource.php` aggiornato, senza file di prova.

Il vecchio sito non è stato cancellato. Il Progetto 1 è rimasto in sola
lettura, il branch `consegna` non è stato modificato e il database non è stato
alterato. Non è stata lanciata la migrazione massiva.

## Verifiche locali

- PHP 8.3.32: sei comandi di test superati; il test PDO d'integrazione ha
  prodotto lo skip previsto quando non richiesto;
- lint PHP: 23 file su 23 validi;
- runner rigoroso: contratti Java e PHP superati, 29 test Django superati con
  uno skip previsto, system check senza problemi;
- i due script PowerShell di packaging modificati superano il parser;
- una build in copia temporanea ha superato l'integrità con 119 payload,
  2 WAR, 7 wheel e 2 PDF;
- il candidato `dist` e il branch orfano `consegna` non sono stati rigenerati
  o modificati.

## Limite residuo e prossimo passo

Il fallback di configurazione è funzionante e non espone segreti. Restano due
blocchi esterni al codice pubblicato:

1. identificare, con una nuova autorizzazione, le due righe eccedenti e
   decidere se correggere il database o aggiornare la sorgente ufficiale;
2. ottenere o attivare un certificato HTTPS valido sul dominio Altervista.

Fino ad allora lo stato remoto resta parzialmente operativo e non va usato
per la migrazione completa.
