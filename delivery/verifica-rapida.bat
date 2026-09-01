@echo off
setlocal DisableDelayedExpansion
cd /d "%~dp0"

if /I "%~1"=="--help" goto :help

where powershell.exe >NUL 2>NUL
if errorlevel 1 (
  echo ERRORE: Windows PowerShell 5.1 o successivo non e' disponibile.
  echo Aprire il manuale PDF e installare o abilitare PowerShell prima di riprovare.
  exit /b 1
)

echo.
echo Drive Aura 51 - verifica rapida offline
echo.
echo Avviare questo file dalla cartella estratta del pacchetto.
echo Verranno richiesti soltanto percorsi e credenziali del PostgreSQL locale.
echo I quattro segreti applicativi della prova sintetica sono generati in memoria
echo e non vengono salvati. Non serve il token Altervista per questa verifica.
echo.
echo Per sicurezza scegliere due nomi di database PostgreSQL che non esistono gia'.
echo Il programma si ferma se trova un database esistente: non cancella dati.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Test-PackageIntegrity.ps1"
set "integrityCode=%ERRORLEVEL%"
if not "%integrityCode%"=="0" (
  echo.
  echo Integrita' del pacchetto non valida. Non proseguire con la configurazione.
  exit /b %integrityCode%
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer\Start-QuickVerification.ps1"
set "exitCode=%ERRORLEVEL%"
if not "%exitCode%"=="0" (
  echo.
  echo Verifica non completata. Leggere il messaggio sopra e la sezione "Risolvere i problemi" del manuale.
) else (
  echo.
  echo Verifica rapida completata.
)
exit /b %exitCode%

:help
echo Uso: verifica-rapida.bat
echo Avvia la verifica offline guidata. Non salva segreti e non cancella database.
exit /b 0
