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

## Esito reale aggiornato al 20 agosto 2026

Sull'account verificato il pannello conserva le direttive `SetEnv`, ma PHP non
le riceve tramite `getenv()`. Il fallback server-only è stato quindi pubblicato
e collaudato. Il servizio finale usa:

`https://motorizzami.altervista.org/drive-aura-api/remote-php/public`

Il certificato HTTPS è valido, health risponde 200 diretto senza redirect, il
manifest anonimo risponde 401 e quello autenticato risponde 200 con otto
entità.

La password presente nell'iniziale file pubblico `htaccess` è stata invalidata
tramite il ripristino accesso del pannello, senza modificare dati o schema. Il
file pubblico ora contiene soltanto il routing; i segreti API e cursore sono
stati ruotati e il file server-only è protetto da un diniego HTTP 403
verificato prima di inserirvi valori reali. Tutti i diagnostici sono stati
rimossi.

Prima del riallineamento è stato creato e verificato un backup completo fuori
dal repository. Le sole otto tabelle sanitarie sono state ricostruite dallo
schema e dal seed ufficiali. Il manifest finale espone 36.176 righe, gli otto
conteggi e digest T07 e il `datasetId`
`75f461f906b5a6a4ed1252218ea2db664d8f929ba68403760474ff2f4d199e39`.
La verticale reale Altervista-PHP/Tomcat/Django/PostgreSQL ha completato 364
lotti; il rilancio con lo stesso `migrationId` è idempotente. Entrambi i WAR
Tomcat 9 e Tomcat 11 sono stati verificati.

Il fallback adottato è un caricatore applicativo a whitelist per il file
server-only `remote-php/config/local.php`, escluso da Git, collocato fuori da
`public` e protetto da accesso HTTP. L'ambiente ha precedenza e il diniego HTTP
va verificato prima di inserire valori reali. `GET /health` resta indipendente
dalla configurazione e dal database. Dettagli ed evidenze osservate sul server
sono in `docs/VERIFICA_ALTERVISTA.md`.

Il pacchetto offline include queste istruzioni corrette, ma **non** include il
file `local.php` reale. La verifica standard resta offline e locale; l'endpoint
Altervista è una sorgente reale opzionale, utile soltanto con rete disponibile
e con il Bearer fornito separatamente. Non inserire mai file reali, segreti o
diagnostici in un archivio, nel repository o sotto `public`.

## Controllo senza esporre segreti

Impostare il segreto soltanto nella sessione PowerShell e non stamparlo:

```powershell
$remote = 'https://motorizzami.altervista.org/drive-aura-api/remote-php/public'
Invoke-RestMethod "$remote/health"
$headers = @{ Authorization = "Bearer $env:REMOTE_API_SECRET" }
Invoke-RestMethod "$remote/api/v1/manifest" -Headers $headers
```

Il primo comando deve restituire `service=remote-php` e `status=ok`. Il
manifest deve dichiarare otto entità, 36.176 righe, gli otto digest T07 e il
`datasetId` riportato sopra. Un Bearer assente o errato deve ricevere HTTP 401.

Usare soltanto HTTPS con certificato valido nell'URL configurato per la
servlet. Non stampare manifest completi nei log di produzione e non eseguire
CRUD sul Progetto 1 durante la migrazione.
