# Drive Aura 51

## Manuale di installazione e verifica offline

Secondo progetto di Programmazione Web - scelta B - Versione candidata:
31 luglio 2026

Questo pacchetto migra i dati del Servizio Sanitario dal servizio PHP remoto a
PostgreSQL locale. Il percorso applicativo è:

`PHP remoto -> servlet Java/Tomcat -> Django -> PostgreSQL`.

Il controllo rapido offline usa una piccola sorgente contrattuale in locale.
Attraversa la servlet, Django e PostgreSQL reali, ma non sostituisce la prova
massiva PHP/PDO già eseguita.

## 1. Prerequisiti

Usare Windows con PowerShell 5.1 o successivo e software già installato:

1. Python 3.12 x64 completo di `venv`;
2. Java 8 o successivo per Tomcat 9;
3. Java 17 o successivo per Tomcat 11;
4. Tomcat 9 oppure Tomcat 11, non Tomcat 10;
5. PostgreSQL da 14 a 18, avviato e raggiungibile.

Non servono Internet, Maven, Composer, Node.js, IDE o compilazione Java.
L'utente PostgreSQL deve poter creare un database. Tenere a portata di mano i
percorsi di `python.exe`, della directory Java, di Tomcat e della cartella
`bin` di PostgreSQL.

Controllare le versioni:

```powershell
& 'C:\Python312\python.exe' --version
& 'C:\Program Files\Java\jdk-17\bin\java.exe' -version
& 'C:\apache-tomcat-11\bin\version.bat'
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' --version
```

## 2. Estrarre e controllare il pacchetto

**Importante:** estrarre direttamente in `C:\DriveAura51`. PowerShell 5.1 può
fallire durante `Expand-Archive` se la directory padre è molto lunga; nessuno
script può prevenire un errore già avvenuto in questa fase.

1. Mettere ZIP e file `.sha256` nella stessa cartella e aprire PowerShell.
2. Confrontare il checksum esterno prima di estrarre lo ZIP.
3. Estrarre lo ZIP nella cartella nuova `C:\DriveAura51`.
4. Aprire PowerShell nella cartella `drive-aura-51-offline`.
5. Abilitare gli script soltanto per la sessione corrente e verificare gli
   hash interni prima di inserire segreti.

```powershell
$expected = (Get-Content '.\drive-aura-51-offline.zip.sha256' -Raw).Split()[0]
$actual = (Get-FileHash '.\drive-aura-51-offline.zip' -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $expected) { throw 'Checksum ZIP non valido' }
Set-ExecutionPolicy -Scope Process Bypass
.\installer\Test-PackageIntegrity.ps1
```

Attendere `Integrità pacchetto valida`. Se il controllo fallisce, eliminare
la copia estratta e ripartire dallo ZIP originale.
Il primo script controlla anche il budget dei percorsi prima di traversare o
copiare file. Se è insufficiente, chiede di riestrarre in `C:\DriveAura51` e
si ferma senza spostare o cancellare nulla.

## 3. Impostare i segreti

Impostare i valori soltanto nella sessione PowerShell. Non modificare i file
del pacchetto e non passare segreti come parametri ai processi. Disabilitare
prima il salvataggio della cronologia della sessione:

```powershell
if (Get-Module PSReadLine) { Set-PSReadLineOption -HistorySaveStyle SaveNothing }
$env:POSTGRES_PASSWORD = '<password-postgresql>'
$env:DJANGO_SECRET_KEY = '<stringa-casuale-almeno-32-caratteri>'
$env:LOCAL_API_SECRET = '<segreto-locale-almeno-12-caratteri>'
$env:REMOTE_API_SECRET = '<segreto-remoto-almeno-12-caratteri>'
$env:BRIDGE_API_SECRET = '<segreto-bridge-almeno-12-caratteri>'
```

Usare valori distinti e chiudere la sessione al termine. I segreti restano
nell'ambiente dei processi e non entrano nell'archivio, nello stato installato,
nei log o nella cronologia PowerShell persistente.

## 4. Configurare e verificare

Adattare i quattro percorsi. Il comando crea
`..\drive-aura-51-runtime`, un ambiente virtuale, un `CATALINA_BASE` isolato
e il WAR corretto. Prepara due database distinti: il database operativo resta
vuoto e pronto per i dati reali; il database di verifica riceve la fixture
sintetica da 22 righe e 22 lotti.

```powershell
.\installer\Configure-DriveAura.ps1 `
  -PythonPath 'C:\Python312\python.exe' `
  -JavaHome 'C:\Program Files\Java\jdk-17' `
  -TomcatHome 'C:\apache-tomcat-11' `
  -PostgresBin 'C:\Program Files\PostgreSQL\18\bin' `
  -PostgresUser 'postgres' `
  -PostgresDatabase 'drive_aura_51' `
  -VerificationDatabase 'drive_aura_51_verify'
```

Il comando non modifica il Tomcat installato: copia solo la configurazione
necessaria sotto `..\drive-aura-51-runtime\tomcat-base`. L'installazione
Python usa sette wheel locali con `--no-index` e `--require-hashes`. Se
`-VerificationDatabase` è omesso, il nome viene derivato aggiungendo
`_verify` al database operativo.

I timeout PostgreSQL predefiniti sono: connessione 10 s (1-60), lock 10000 ms
(100-120000), query 120000 ms e transazione inattiva 120000 ms
(1000-600000). Le quattro variabili `POSTGRES_*_TIMEOUT_*` documentate nel
README Django permettono di modificarli con soli interi negli intervalli.

L'esito corretto termina con:

```text
PASS: verifica sintetica; righe=22; lotti=22; dataset=199452...418a7.
PASS: configurazione completata in ... secondi.
```

La prova pulita del 25 luglio 2026 ha usato Python 3.12.10 x64, Java 23.0.2,
Tomcat 11.0.24 e PostgreSQL 18.4 con autenticazione SCRAM. Con rete resa
indisponibile e pacchetto estratto in un percorso con spazi, configurazione e
verifica sono terminate in 43,290 secondi misurati dal configuratore e 43,571
secondi wall-clock. La stessa prova con Tomcat 9.0.120 è terminata in 38,822
secondi. La verifica completa ha un watchdog predefinito di 180 secondi,
configurabile con `-VerificationTimeoutSeconds` fra 60 e 240 secondi. In caso
di errore o timeout mostra le code dei log, arresta soltanto l'albero di
processi registrato e verifica che le porte siano state liberate.

## 5. Cosa verifica il comando

Il configuratore controlla:

- versione e architettura di Python;
- compatibilità fra Java, Tomcat 9/11 e WAR;
- disponibilità e autenticazione PostgreSQL;
- hash del pacchetto, delle wheel, dei WAR e del dump;
- installazione Django/psycopg senza rete;
- migrazioni Django e database dedicato;
- salute della sorgente sintetica, della servlet e di Django;
- readiness PostgreSQL;
- migrazione delle otto entità, digest, vincoli e idempotenza;
- arresto dei processi avviati dal controllo.

La verifica rapida usa dati sintetici leggibili. La migrazione massiva usa il
servizio PHP reale e 36.176 righe; è separata perché richiede il database
remoto configurato.

## 6. Avviare con il servizio PHP reale

Preparare prima il componente remoto seguendo `ALTERVISTA.md`. Impostare nella
stessa sessione i cinque segreti della sezione 3; il valore di
`REMOTE_API_SECRET` deve coincidere con il segreto configurato nel servizio
PHP remoto.

Il PHP remoto usa per default 3 s per connettersi via PDO (intervallo 1-30) e
8 s per ogni query (1-120). Sono limiti distinti dal timeout PHP/web server;
configurare `REMOTE_DB_CONNECT_TIMEOUT_SECONDS` e
`REMOTE_DB_QUERY_TIMEOUT_SECONDS` nella `.htaccess` privata.

```powershell
.\installer\Start-DriveAura.ps1 `
  -StatePath '..\drive-aura-51-runtime\install-state.json' `
  -RemoteApiUrl 'https://ACCOUNT.altervista.org/drive-aura-api/remote-php/public'
```

Controllare:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8000/health'
Invoke-RestMethod 'http://127.0.0.1:8080/health'
```

Il database indicato da `-PostgresDatabase` è già dedicato e vuoto. Non usare
il database indicato da `-VerificationDatabase`. Avviare la migrazione reale:

```powershell
.\tools\verify-mass-migration.ps1 `
  -RemoteBaseUrl 'https://ACCOUNT.altervista.org/drive-aura-api/remote-php/public' `
  -LocalBaseUrl 'http://127.0.0.1:8000' `
  -BridgeBaseUrl 'http://127.0.0.1:8080' -Repeat
```

Il risultato massivo atteso è `completed`, 36.176 righe e 364 lotti. La durata
della migrazione massiva non fa parte del controllo rapido di installazione.

## 7. Arrestare

```powershell
.\installer\Stop-DriveAura.ps1 `
  -StatePath '..\drive-aura-51-runtime\install-state.json'
```

Attendere `PASS: processi Drive Aura arrestati`. Lo script usa il registro dei
PID creato all'avvio e prova prima l'arresto Tomcat ordinato. Prima di forzare
la chiusura verifica PID, percorso eseguibile e istante di avvio, quindi
arresta soltanto i discendenti appartenenti a quell'albero.

## 8. Risolvere i problemi

### Python non trovato o incompatibile

Sintomo: `Python 3.12 x64 compatibile non trovato`.
Soluzione: installare Python 3.12 x64 completo; l'edizione embeddable non
contiene `venv`.

### Java o Tomcat incompatibile

Sintomo: richiesta Java 17, Tomcat non riconosciuto o Tomcat 10 rifiutato.
Soluzione: abbinare Java 8+ a Tomcat 9 oppure Java 17+ a Tomcat 11 e passare la
directory che contiene `bin\catalina.bat`.

### PostgreSQL non raggiungibile

Sintomo: errore di readiness o autenticazione.
Soluzione: avviare PostgreSQL, controllare host e porta, verificare l'utente e
reimpostare `POSTGRES_PASSWORD` nella sessione.

### Porta occupata

Sintomo: porta Django, Tomcat, arresto o sorgente sintetica occupata.
Soluzione: non terminare il processo segnalato; rilanciare il configuratore con
porte libere, per esempio `-DjangoPort 18000 -TomcatPort 18080
-TomcatShutdownPort 18005 -SyntheticRemotePort 18081`.

### Segreto mancante

Sintomo: `Segreto mancante` oppure HTTP 401.
Soluzione: impostare nuovamente tutte le variabili della sezione 3 nella
stessa finestra PowerShell.

### Wheel, WAR, dump o checksum alterato

Sintomo: errore SHA-256 o integrità.
Soluzione: non usare il file; eliminare la cartella estratta, verificare il
checksum esterno dello ZIP e riestrarre il pacchetto originale.

### Rete assente

Non è un errore per installazione e prova sintetica. Il configuratore non usa
download. La rete serve soltanto quando si collega al PHP Altervista reale.

### Percorso Windows troppo lungo

Sintomo: `Percorso Windows troppo lungo` oppure estrazione incompleta.
Soluzione: non spostare la copia parziale; riestrarre lo ZIP originale
direttamente in `C:\DriveAura51` e rilanciare il controllo di integrità.

### Database di verifica non vuoto

Sintomo: rifiuto delle righe già presenti.
Soluzione: indicare un nuovo nome con `-VerificationDatabase`. Il
configuratore non cancella né sovrascrive dati estranei. Il database operativo
indicato da `-PostgresDatabase` non viene popolato dalla prova rapida.

## 9. Contenuto utile

- `artifacts`: WAR Tomcat 9 e Tomcat 11;
- `wheelhouse`: sette wheel e hash;
- `database`: dump sorgente massivo e checksum;
- `source`: sorgenti PHP, Java e Django;
- `installer`: configuratore, avvio, arresto e verificatore;
- `pdf`: manuale e scelte progettuali.
