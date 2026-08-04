# Caricamento manuale del servizio PHP su Altervista

Questa procedura prepara il componente remoto del caso B. Non è stata eseguita
alcuna distribuzione dal pacchetto e non sono incluse credenziali.

## File da caricare

Creare sullo spazio Altervista una cartella dedicata, per esempio
`drive-aura-api`. Caricare al suo interno, mantenendo i nomi:

```text
drive-aura-api/
  remote-php/
    public/
    src/
  shared/
    entity-schema.json
```

Le cartelle provengono da `source\remote-php` e `source\shared`. Non caricare
test, documenti, dump, WAR o wheel. Il percorso pubblico è
`/drive-aura-api/remote-php/public`; il router supporta questo prefisso.

## Configurazione privata

1. Aprire `remote-php/public/.htaccess` sul server.
2. Conservare le regole `DirectoryIndex` e `RewriteRule` già presenti.
3. Copiare in testa le righe di
   `config/altervista-setenv.example.htaccess`.
4. Sostituire tutti i placeholder soltanto sul server.
5. Usare il database del Progetto 1 e un utente che non richieda permessi di
   scrittura per la prova, se Altervista permette di crearne uno.
6. Usare due segreti casuali distinti per API e cursori.

Lasciare i timeout di esempio a 3 secondi per la connessione PDO e 8 secondi
per ogni `SELECT`, oppure scegliere interi rispettivamente negli intervalli
1-30 e 1-120. Il timeout PHP/web server dell'hosting è distinto: deve essere
più ampio del limite query. `PDO::ATTR_TIMEOUT` limita soltanto la connessione;
il servizio applica il limite query nativo dopo aver rilevato la versione:
`SET STATEMENT` su MariaDB 10.1.1+ e `MAX_EXECUTION_TIME` su MySQL 5.7.8+.
Se l'API risponde `SOURCE_TIMEOUT_UNSUPPORTED`, verificare dal pannello la
versione del database e non aggiungere comandi SQL non supportati.

Se l'hosting rifiuta la direttiva `SetEnv`, interrompere la configurazione:
non inserire segreti in `index.php` e non rendere pubblico un file di
credenziali. Verificare dal pannello Altervista il metodo supportato per
variabili d'ambiente prima di proseguire.

## Esito della prova reale del 4 agosto 2026

Sull'account verificato il pannello conserva le direttive `SetEnv`, ma PHP non
le riceve tramite `getenv()`. Health risponde HTTP 200; il manifest anonimo si
arresta invece con HTTP 503 e `SERVICE_NOT_CONFIGURED` prima
dell'autenticazione e prima dell'accesso al database. Non configurare la
servlet verso questo endpoint finché il blocco non è risolto.

La configurazione era stata inizialmente caricata come file pubblico
`htaccess`: è stata rinominata `.htaccess`, i segreti API/cursore sono stati
ruotati e tutti i diagnostici sono stati rimossi. Poiché anche la credenziale
database era nel file pubblico, va ruotata dal pannello prima dell'uso reale.
La rotazione non è compresa nella prova perché il database non era
autorizzato alle modifiche.

Il fallback proposto è un caricatore applicativo a whitelist per un file
server-only `remote-php/config/local.php`, già escluso da Git, collocato fuori
da `public` e protetto da accesso HTTP. Il diniego HTTP va verificato prima di
inserire valori reali. Questa modifica richiede un'attività separata; non
inserire segreti nel repository né in `index.php`. Dettagli ed evidenze sono
in `docs/VERIFICA_ALTERVISTA.md`.

## Controllo senza esporre segreti

Sostituire `ACCOUNT` nell'URL:

```powershell
$remote = 'https://ACCOUNT.altervista.org/drive-aura-api/remote-php/public'
Invoke-RestMethod "$remote/health"
$headers = @{ Authorization = "Bearer $env:REMOTE_API_SECRET" }
Invoke-RestMethod "$remote/api/v1/manifest" -Headers $headers
```

Il primo comando deve restituire `service=remote-php` e `status=ok`. Il
manifest deve dichiarare otto entità, conteggi e digest. Un Bearer assente o
errato deve ricevere HTTP 401.

Usare soltanto HTTPS nell'URL configurato per la servlet. Non stampare
manifest completi nei log di produzione e non eseguire CRUD sul Progetto 1
durante la migrazione.
