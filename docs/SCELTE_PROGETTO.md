# Drive Aura 51 - Scelte progettuali

Il progetto adotta il caso B: migrazione completa del database del Servizio
Sanitario da MariaDB/MySQL remoto a PostgreSQL locale. Il percorso imposto
rimane `PHP/PDO -> servlet Java/Tomcat -> Django -> PostgreSQL`; la servlet
coordina chiamate HTTP e non accede ai database.

## Contratto e integrità

Le otto entità condividono uno schema dichiarativo con ordine, campi, tipi,
chiavi semplici e composte, relazioni e vincoli. Il PHP esporta una sola
entità per richiesta, con query PDO preparate, whitelist e paginazione keyset.
I cursori sono opachi, firmati HMAC e legati a dataset ed entità. Ogni record
ha una rappresentazione JSON canonica UTF-8; conteggi e SHA-256 permettono di
rilevare dati mancanti, alterati o cambiati durante l'esportazione.

## Orchestrazione e persistenza

Il core Java compatibile con Java 8 contiene trasporto, validazione e
orchestrazione. Due adattatori sottili producono WAR distinti: `javax.servlet`
per Tomcat 9 e `jakarta.servlet` per Tomcat 11. L'ordine delle dipendenze non
arriva dall'input. Timeout e retry sono limitati alle operazioni idempotenti e
agli errori temporanei; autenticazione, schema, dataset e digest non validi
sono fallimenti definitivi.

Django 5.2.16 e psycopg 3.3.4 applicano ogni lotto in una transazione
PostgreSQL. Il registro usa migrazione, entità e sequenza; lo stesso digest è
un rilancio valido, un contenuto diverso è un conflitto. Checkpoint e dati
avanzano atomicamente. Dopo un riavvio la servlet legge lo stato autorevole da
PostgreSQL e riprende dal cursore confermato. La finalizzazione verifica tutte
le entità, i digest, le FK, l'unicità del direttore, le associazioni e i
progressivi prima dello stato `completed`.

## Installazione offline

La consegna non richiede Internet, Maven, Composer, Node.js, IDE o
compilazione Java. Include due WAR precompilati, sette wheel Windows x64 con
versioni e hash, dump sorgente verificabile e configurazioni senza segreti. Il
configuratore PowerShell accetta Python 3.12 x64, PostgreSQL 14-18 e soltanto
Tomcat 9 o 11 con Java compatibile. Crea un ambiente virtuale, installa con
`pip --no-index --require-hashes`, prepara un database operativo e un database
separato per la prova sintetica e usa un `CATALINA_BASE` locale, senza
modificare il Tomcat installato. I segreti restano nell'ambiente dei processi.

## Verifica

Il controllo rapido offline usa la fixture condivisa come sorgente
contrattuale loopback e trasferisce 22 righe in 22 lotti attraverso Tomcat,
Django e PostgreSQL reali; controlla salute, readiness, digest, vincoli e
rilancio idempotente. Questa prova non viene presentata come collaudo PHP: la
verticale PHP/PDO e la migrazione massiva di 36.176 righe sono state osservate
separatamente con entrambi i WAR. Il pacchetto finale è costruito da allowlist,
ha checksum complessivo e rifiuta cache, log, runtime, credenziali e artefatti
di sviluppo.
