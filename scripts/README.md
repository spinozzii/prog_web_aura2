# Configurazione e verifica

Questa cartella conterrà gli strumenti da riga di comando per:

- rilevare prerequisiti e versioni;
- configurare l'ambiente locale;
- installare dipendenze Python offline;
- preparare PostgreSQL;
- selezionare e distribuire il WAR corretto;
- avviare, verificare e arrestare i servizi;
- misurare la procedura completa.

I comandi definitivi devono essere indipendenti da un IDE e provati da una
copia pulita. Non aggiungere comandi fittizi al manuale.

T02.2 aggiunge `verify-patologia-migration.ps1`: controlla i tre endpoint di
salute e accetta la verticale soltanto dopo la finalizzazione verificata di
`patologia`. Il comando usa URL espliciti e legge `BRIDGE_API_SECRET`
dall'ambiente; non installa runtime e non contiene credenziali.

T03 aggiunge `verify-full-migration.ps1`: verifica l'ordine e il risultato
aggregato delle otto entità e accetta un `MigrationId` esplicito. L'opzione
`-Repeat` prova il rilancio idempotente. Il precedente comando Patologia resta
un alias compatibile e avvia ora la verticale completa, che include
`patologia`.

T07 aggiunge `verify-mass-migration.ps1`: verifica anche manifest massivo,
conteggi, digest, stato persistente e totale di 36.176 righe. Accetta un
timeout fino a 3.600 secondi e `-Repeat` per il rilancio idempotente:

```powershell
$env:REMOTE_API_SECRET = '<segreto locale>'
$env:BRIDGE_API_SECRET = '<segreto locale>'
.\scripts\verify-mass-migration.ps1 `
  -RemoteBaseUrl 'http://127.0.0.1:8081' `
  -LocalBaseUrl 'http://127.0.0.1:8000' `
  -BridgeBaseUrl 'http://127.0.0.1:8080/bridge' `
  -MigrationId '00000000-0000-4000-8000-000000000001' `
  -TimeoutSeconds 1800
```

`t07-fault-proxy.py` è un proxy di collaudo esclusivamente loopback. Può
iniettare un solo timeout, ritardo, stato HTTP o digest alterato sul percorso
scelto. Non registra header o corpi; quando inietta una risposta consuma il
corpo in ingresso e chiude la connessione. Va avviato come processo separato
con stdout e stderr distinti e arrestato usando il PID verificato.

`build-source-dump.ps1` genera il pacchetto descritto da
`database/README_SOURCE_DUMP.md`; non modifica il Progetto 1 e rifiuta
checksum o conteggi inattesi. Gli esiti reali T07 sono in
`docs/VERIFICA_T07.md`.

T09 aggiunge:

- `build-offline-package.ps1`, builder allowlist del candidato con manifest,
  checksum, ZIP deterministico, estrazione e verifica;
- `generate-delivery-pdfs.py`, generatore ReportLab del manuale e delle
  scelte progettuali.

Il configuratore operativo è consegnato in `delivery/installer`; gli esiti
cronometrati e le verifiche PDF sono in `docs/VERIFICA_T09.md`.
