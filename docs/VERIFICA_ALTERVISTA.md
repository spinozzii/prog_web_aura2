# Verifica della pubblicazione Altervista

Data: 4 agosto 2026.

## Esito

**BLOCCATA — il servizio PHP non riceve le variabili `SetEnv`.**

Il servizio è pubblicato all'indirizzo osservato:

`http://motorizzami.altervista.org/drive-aura-api/remote-php/public`

`GET /health` risponde HTTP 200 con il contratto atteso:

```json
{"apiVersion":"1.0","service":"remote-php","status":"ok"}
```

`GET /api/v1/manifest` senza token non arriva invece al controllo di
autenticazione: risponde HTTP 503 con `SERVICE_NOT_CONFIGURED`, indicando che
il segreto del cursore non è disponibile nel processo PHP. Il manifest
autenticato e i suoi conteggi non sono quindi stati dichiarati verificati.

## Configurazione controllata

Nel caricamento iniziale la configurazione era stata nominata `htaccess`,
senza il punto iniziale, ed era quindi un normale file pubblico anziché una
configurazione Apache. Il file è stato rinominato `.htaccess`; al termine il
file ordinario `htaccess` non è più presente nel `public`.

Il sorgente `.htaccess` salvato dal pannello contiene, nell'ordine richiesto,
le otto variabili seguenti, tutte non vuote e prive di placeholder:

1. `REMOTE_DB_DSN`;
2. `REMOTE_DB_USER`;
3. `REMOTE_DB_PASSWORD`;
4. `REMOTE_API_SECRET`;
5. `REMOTE_CURSOR_SECRET`;
6. `REMOTE_CURSOR_TTL_SECONDS`;
7. `REMOTE_DB_CONNECT_TIMEOUT_SECONDS`;
8. `REMOTE_DB_QUERY_TIMEOUT_SECONDS`.

I segreti API e cursore sono stati ruotati con valori casuali lunghi e
distinti. Nessun valore è stato copiato nella documentazione o nel repository.
Le direttive `DirectoryIndex`, `RewriteEngine` e `RewriteRule` sono rimaste
presenti.

Una richiesta eseguita nel vero contesto Apache ha però confermato che
`getenv()` non riceve neppure `REMOTE_API_SECRET`. Una pagina diagnostica
senza segreti, con timeout HTTP di 10 secondi, ha riconfermato in parallelo:

- health: HTTP 200 e `status=ok`;
- manifest anonimo: HTTP 503 e `SERVICE_NOT_CONFIGURED` sul segreto cursore.

Il pannello PHP osservato permette di modificare `.htaccess`, ma non espone
un gestore separato di variabili d'ambiente. La configurazione è quindi
conservata correttamente, ma il metodo `SetEnv` non è operativo per PHP su
questo account.

## Pulizia e confini

Sono stati rimossi dal `public`:

- `manifest-test.php`;
- `manifest-local-test.php`;
- `manifest-local-test.php.php`;
- `test.php`;
- la pagina effimera `route-check.html`.

Al termine il `public` contiene soltanto `.htaccess`, `index.php` e la
directory `health`. Non è stata eseguita alcuna query di migrazione, non è
stato modificato il database Altervista, il vecchio sito non è stato
cancellato e il Progetto 1 è rimasto in sola lettura.

Poiché il file iniziale senza punto era pubblicamente indirizzabile, la
password del database deve essere considerata esposta e va ruotata dal
pannello prima dell'attivazione definitiva. La rotazione non è stata eseguita
per rispettare il divieto di modificare il database.

Il tentativo HTTPS automatizzato non ha superato la validazione del
certificato (`ERR_CERT_AUTHORITY_INVALID`). Prima di configurare la servlet va
quindi abilitato o verificato un URL HTTPS con certificato valido.

## Conteggi attesi ma non osservati

Il manifest autenticato dovrà essere rieseguito e confrontato con:

| Entità | Righe attese |
|---|---:|
| `cittadino` | 3.200 |
| `patologia` | 200 |
| `patologia_cronica` | 143 |
| `patologia_mortale` | 81 |
| `ospedale` | 30 |
| `ricovero` | 12.000 |
| `patologia_ricovero` | 20.492 |
| `progressivo_ricovero` | 30 |

## Soluzione proposta

Serve una modifica separatamente autorizzata e minima:

1. aggiungere al front controller un caricatore a whitelist per un file
   server-only `remote-php/config/local.php`, già escluso da Git;
2. collocare il file fuori da `public` e negarne esplicitamente l'accesso HTTP;
3. verificare il diniego HTTP prima di inserirvi i valori reali;
4. caricare il file manualmente soltanto su Altervista, senza includerlo nel
   repository o nel pacchetto pubblico;
5. ruotare la password database e mantenere distinti i segreti API/cursore;
6. abilitare un certificato HTTPS valido;
7. ripetere health, 401 anonimo e manifest autenticato con otto entità e
   conteggi attesi.

Non va inserito alcun segreto in `index.php`. Una `.user.ini` non deve essere
considerata equivalente a un gestore di variabili d'ambiente senza una prova
specifica del provider.
