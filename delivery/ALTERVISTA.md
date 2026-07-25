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

Se l'hosting rifiuta la direttiva `SetEnv`, interrompere la configurazione:
non inserire segreti in `index.php` e non rendere pubblico un file di
credenziali. Verificare dal pannello Altervista il metodo supportato per
variabili d'ambiente prima di proseguire.

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
