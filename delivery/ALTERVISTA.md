# Caricamento manuale del servizio PHP su Altervista

Questa procedura prepara il componente remoto del caso B. Non è stata eseguita
alcuna distribuzione dal pacchetto e non sono incluse credenziali.

## File da caricare

Creare sullo spazio Altervista una cartella dedicata, per esempio
`drive-aura-api`. Caricare al suo interno, mantenendo i nomi:

```text
drive-aura-api/
  remote-php/
    config/
      .htaccess
    public/
    src/
  shared/
    entity-schema.json
```

Le cartelle provengono dai sorgenti `remote-php` e `shared`. Non caricare
test, documenti, dump, WAR o wheel. Dalla directory `config` caricare soltanto
il `.htaccess` di protezione; il file reale `local.php` va creato
esclusivamente sul server usando `config/local.php.example` come modello. Il
percorso pubblico è
`/drive-aura-api/remote-php/public`; il router supporta questo prefisso.

## Configurazione privata

1. Caricare `remote-php/config/.htaccess` prima di qualunque credenziale.
2. Creare nella stessa directory un file di prova privo di segreti e
   richiederlo tramite URL diretto. Proseguire soltanto se la risposta è 403 o
   404, quindi rimuovere il file di prova.
3. Creare sul server `remote-php/config/local.php` copiando la struttura di
   `remote-php/config/local.php.example` e sostituire tutti i placeholder.
4. Non caricare `local.php` dal computer di sviluppo, non collocarlo sotto
   `public` e non aggiungerlo a Git: il file reale è server-only e non fa
   parte del pacchetto.
5. Usare il database del Progetto 1 e un utente che non richieda permessi di
   scrittura per la prova, se Altervista permette di crearne uno.
6. Usare due segreti casuali distinti per API e cursori.

Le variabili d'ambiente omonime, quando realmente disponibili a PHP, hanno
precedenza chiave per chiave sul file. Il fallback è necessario perché alcuni
account Altervista accettano `SetEnv` nel pannello ma non propagano i valori a
`getenv()`. Non lasciare direttive contenenti segreti in
`remote-php/public/.htaccess`: quel file deve contenere soltanto le regole di
routing.

Lasciare i timeout di esempio a 3 secondi per la connessione PDO e 8 secondi
per ogni `SELECT`, oppure scegliere interi rispettivamente negli intervalli
1-30 e 1-120. Il timeout PHP/web server dell'hosting è distinto: deve essere
più ampio del limite query. `PDO::ATTR_TIMEOUT` limita soltanto la connessione;
il servizio applica il limite query nativo dopo aver rilevato la versione:
`SET STATEMENT` su MariaDB 10.1.1+ e `MAX_EXECUTION_TIME` su MySQL 5.7.8+.
Se l'API risponde `SOURCE_TIMEOUT_UNSUPPORTED`, verificare dal pannello la
versione del database e non aggiungere comandi SQL non supportati.

Se il diniego della directory `config` non produce 403 o 404, interrompere la
configurazione: non inserire segreti in `index.php`, in `.htaccess`, sotto
`public` o in qualunque file raggiungibile via HTTP.

## Esito della prova reale del 4 agosto 2026

Sull'account verificato il pannello conserva le direttive `SetEnv`, ma PHP non
le riceve tramite `getenv()`. Il fallback server-only è stato quindi pubblicato
e collaudato: health risponde HTTP 200, il manifest anonimo HTTP 401 e il
manifest autenticato HTTP 200 con otto entità.

La password presente nell'iniziale file pubblico `htaccess` è stata invalidata
tramite il ripristino accesso del pannello, senza modificare dati o schema. Il
file pubblico ora contiene soltanto il routing; i segreti API e cursore sono
stati ruotati e il file server-only è protetto da un diniego HTTP 403
verificato prima di inserirvi valori reali. Tutti i diagnostici sono stati
rimossi.

Il collaudo ha però osservato 12.001 `ricovero` e 20.493
`patologia_ricovero`, una riga in più per entrambe le entità rispetto al
dataset atteso. HTTPS restituisce inoltre `ERR_CERT_AUTHORITY_INVALID`. Non
configurare la servlet verso questo endpoint, non disabilitare TLS e non
correggere il database senza una nuova autorizzazione.

Il fallback adottato è un caricatore applicativo a whitelist per il file
server-only `remote-php/config/local.php`, escluso da Git, collocato fuori da
`public` e protetto da accesso HTTP. L'ambiente ha precedenza e il diniego HTTP
va verificato prima di inserire valori reali. `GET /health` resta indipendente
dalla configurazione e dal database. Dettagli ed evidenze osservate sul server
sono in `docs/VERIFICA_ALTERVISTA.md`.

Il pacchetto offline include queste istruzioni corrette, ma **non** include il
file `local.php` reale né usa questo endpoint come sorgente della verifica
finale. L'endpoint Altervista attuale è opzionale e resta escluso dalla
servlet finché dataset/digest non coincidono con T07 e HTTPS non espone un
certificato valido. Non inserire mai il file reale, segreti o diagnostici in
un archivio, nel repository o sotto `public`.

## Controllo senza esporre segreti, solo per un endpoint futuro conforme

Questo controllo non va eseguito contro l'endpoint Altervista attuale: è
escluso dalla servlet finale per database divergente e TLS non valido. Dopo la
riconciliazione del dataset e un certificato HTTPS valido, sostituire `ACCOUNT`
nell'URL:

```powershell
$remote = 'https://ACCOUNT.altervista.org/drive-aura-api/remote-php/public'
Invoke-RestMethod "$remote/health"
$headers = @{ Authorization = "Bearer $env:REMOTE_API_SECRET" }
Invoke-RestMethod "$remote/api/v1/manifest" -Headers $headers
```

Il primo comando deve restituire `service=remote-php` e `status=ok`. Il
manifest deve dichiarare otto entità, conteggi e digest. Un Bearer assente o
errato deve ricevere HTTP 401.

Usare soltanto HTTPS con certificato valido nell'URL configurato per la
servlet. Non stampare manifest completi nei log di produzione e non eseguire
CRUD sul Progetto 1 durante la migrazione.
