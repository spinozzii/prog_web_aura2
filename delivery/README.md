# Drive Aura 51 - Pacchetto offline

Questo archivio consegna il secondo progetto, scelta B. Contiene i sorgenti dei
tre servizi, due WAR precompilati, dipendenze Python offline, dump sorgente,
configuratore, verificatore e documenti PDF.

La macchina locale non deve avere Internet, Maven, Composer, Node.js, un IDE o
un compilatore Java. Deve avere:

- Windows con PowerShell 5.1 o successivo;
- Python 3.12 x64 completo di `venv`;
- Java 8+ con Tomcat 9, oppure Java 17+ con Tomcat 11;
- PostgreSQL da 14 a 18 già avviato.

Leggere prima `pdf/manuale-drive-aura-51.pdf`. Non inserire segreti nei file
del pacchetto: impostarli soltanto nella sessione PowerShell.

## Estrarre in una radice corta

Estrarre direttamente in `C:\DriveAura51`. PowerShell 5.1 può fallire già
durante `Expand-Archive` se la directory padre è molto lunga. Gli script di
integrità e configurazione controllano subito il budget dei percorsi e, se non
è sufficiente, chiedono di riestrarre in `C:\DriveAura51`; non spostano né
cancellano file. Questo controllo protegge le copie e l'installazione, ma non
può prevenire un errore avvenuto prima, mentre lo ZIP viene estratto.

## Controllo immediato

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\installer\Test-PackageIntegrity.ps1
```

## Configurazione

1. Copiare `config\secrets.example.ps1` fuori dall'archivio oppure impostare
   le cinque variabili indicate direttamente nella sessione.
2. Adattare i percorsi mostrati in `config\parameters.example.ps1`.
3. Eseguire il configuratore. Per impostazione predefinita crea l'ambiente
   locale in una cartella sorella, applica le migrazioni e svolge la prova
   sintetica completa in un database di verifica separato. Il database
   operativo resta vuoto.

La prova sintetica trasferisce 22 righe mediante una sorgente contrattuale
loopback, servlet reale, Django reale e PostgreSQL reale. Non sostituisce la
migrazione massiva da PHP/PDO, già collaudata separatamente.

Per il servizio PHP remoto leggere `ALTERVISTA.md`. Le istruzioni non
effettuano alcuna pubblicazione automatica.
