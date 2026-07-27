# Verifica T09 - Pacchetto offline e PDF

## Candidato verificato

- archivio: `dist/drive-aura-51-offline.zip`;
- dimensione: 12.833.734 byte;
- SHA-256:
  `8008964dfbe07c8158194e4923e3877fcb1c544f8f079174f8d14e029d7a6eae`;
- payload dichiarato: 108 file;
- contenuto principale: 78 sorgenti, 7 wheel, 2 WAR, dump sorgente,
  configuratore/verificatore, 3 configurazioni di esempio e 2 PDF.

Il verificatore interno ha confrontato manifest, dimensioni e SHA-256 dopo
l'estrazione. La suite ha inoltre alterato una copia del README, una wheel e
il relativo checksum: tutti i casi sono stati rifiutati.

## Ambiente della prova pulita

Prova eseguita il 25 luglio 2026 su Windows:

- Windows PowerShell 5.1;
- Python 3.12.10 x64 completo di `venv`;
- Java 23.0.2;
- Tomcat 11.0.24;
- PostgreSQL 18.4 con autenticazione SCRAM-SHA-256;
- pacchetto estratto in `C:\tmp\drive aura t09 final 001`, quindi in un
  percorso con spazi;
- nessun ambiente virtuale o WAR già predisposto nella copia pulita.

Internet non è stato usato. Per la prova sono stati impostati proxy HTTP/HTTPS
non raggiungibili su `127.0.0.1:9` e valori ostili per `PIP_FIND_LINKS`,
`PIP_INDEX_URL` e `PIP_EXTRA_INDEX_URL`. Il configuratore ha ignorato la
configurazione pip esterna, usato `PIP_CONFIG_FILE=NUL`, `--no-index`,
`--require-hashes` e soltanto la wheelhouse locale. La scheda di rete non è
stata disabilitata fisicamente.

## Esito cronometrato

Il comando documentato nel manuale ha:

1. verificato i 108 file;
2. rilevato i quattro runtime;
3. copiato i sorgenti operativi;
4. creato il virtual environment;
5. installato 7 wheel offline;
6. creato e migrato un database operativo e uno di verifica distinti;
7. creato un `CATALINA_BASE` isolato e distribuito
   `bridge-tomcat11.war`;
8. avviato sorgente sintetica, Django e Tomcat;
9. trasferito 22 righe in 22 lotti;
10. ripetuto la stessa migrazione senza duplicazioni;
11. verificato conteggi, digest e vincoli in PostgreSQL;
12. arrestato i processi e liberato le quattro porte.

Tempo misurato dal configuratore: **43,290 secondi**. Tempo wall-clock del
comando esterno: **43,571 secondi**. Il limite di cinque minuti è rispettato
con oltre quattro minuti di margine.

Il database operativo conteneva 0 righe dopo la prova; quello sintetico 22.
I file di stato non contenevano segreti, `processes.json` era assente e le
porte 18200, 18280, 18205 e 18281 erano nuovamente disponibili.

Una prova completa precedente con Tomcat 9.0.120 ha selezionato
`bridge-tomcat9.war` e terminato in 38,822 secondi. Il rilancio Tomcat 11
sulla stessa installazione ha terminato in 15,897 secondi. Entrambi hanno
confermato 22 righe, 22 lotti e rilancio idempotente.

## Casi avversi

La suite `delivery/tests/Test-Installer.ps1` ha superato 16 casi:

- Python mancante e incompatibile;
- Java mancante, precedente a Java 8 e incompatibile con Tomcat 11;
- Tomcat mancante e Tomcat 10 non supportato;
- PostgreSQL mancante, versione incompatibile e server non raggiungibile;
- porta occupata;
- segreto mancante;
- directory di installazione estranea non vuota;
- wheel/checksum alterato;
- archivio estratto alterato;
- configurazione senza rete.

Una password PostgreSQL errata è stata rifiutata; quella sintetica corretta è
stata trasmessa ai client libpq soltanto tramite `PGPASSWORD` temporaneo. Il
server PostgreSQL raggiunto, non soltanto il client, è stato verificato come
versione supportata.

## Test applicativi e build

- runner rigoroso: contratti Java, PHP, routing PHP in sottocartella e 33 test
  Django superati;
- runner senza runtime: fallimento normale; con `-AllowPartial`: riepilogo
  esplicito degli skip e uscita 0;
- mock remoto: 4 test su 4;
- Django/PostgreSQL: `manage.py check`,
  `makemigrations --check --dry-run` e `migrate --check` superati;
- Maven 3.9.16: `mvn clean package` superato in 5,096 secondi;
- prodotti entrambi i WAR; il contenuto dei 15 entry WAR e dei 47 entry del
  JAR core coincide con gli artefatti precompilati, al netto dei timestamp ZIP.

## PDF

- `manuale-drive-aura-51.pdf`: A4, 3 pagine, 104.563 byte, SHA-256
  `38a63b806b1271fdf530d574ecbc32b268dad6af3b12b151acf63df9dc3d4fc7`;
- `scelte-progettuali-drive-aura-51.pdf`: A4, 1 pagina, 98.110 byte.

Tutte le pagine sono state renderizzate a 144 dpi e ispezionate. La prima
versione del manuale produceva una quarta pagina con un solo punto elenco:
il contenuto è stato ricomposto e la pagina superflua eliminata. La verifica
finale non ha rilevato testo tagliato, sovrapposizioni, caratteri corrotti,
pagine vuote o margini irregolari. L'estrazione testuale ha confermato 7.824 e
2.926 caratteri senza caratteri sostitutivi Unicode.

## Limiti

La prova rapida usa una sorgente contrattuale loopback e verifica il percorso
reale `servlet -> Django -> PostgreSQL`; non viene dichiarata come una nuova
prova PHP/PDO. La verticale PHP/PDO e la migrazione massiva di 36.176 righe
sono documentate separatamente in `docs/VERIFICA_T07.md`. Non è stata eseguita
alcuna distribuzione su Altervista e non sono state usate credenziali remote.
