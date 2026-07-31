# Checklist del docente

Stato verificato nell'audit T11.1 del 31 luglio 2026. Le caselle non selezionate
sono operazioni proprie dell'invio dell'email, che non è stato eseguito.

## Scelta e architettura

- [x] La consegna dichiara esplicitamente il caso B.
- [ ] Il componente remoto PHP è predisposto per il sito del Progetto 1, ma
      la distribuzione Altervista non fa parte del collaudo autorizzato e non
      è stata verificata.
- [x] Il servizio locale è Python/Django.
- [x] Lo strato intermedio è una servlet Java.
- [x] Il percorso reale dei dati è PHP → servlet → Django → PostgreSQL.
- [x] La servlet non accede direttamente ai database.

## Migrazione

- [x] Tutte le otto entità previste vengono migrate.
- [x] Il dataset massivo completo viene trasferito.
- [x] Conteggi sorgente e destinazione coincidono.
- [x] Digest sorgente e destinazione coincidono.
- [x] Chiavi primarie semplici e composte sono preservate.
- [x] Non esistono righe orfane.
- [x] Il direttore sanitario resta obbligatorio e univoco.
- [x] Ogni Ricovero mantiene cittadino, ospedale e patologie.
- [x] I sottoinsiemi cronica e mortale restano indipendenti.
- [x] I progressivi valgono `MAX(cod) + 1`.
- [x] Un rilancio non crea duplicati.
- [x] Un errore intermedio non viene dichiarato come successo.

## Codice

- [x] Tutto il codice sorgente è incluso.
- [x] Le scelte non ovvie sono commentate.
- [x] Non ci sono credenziali o token reali.
- [x] Non ci sono dipendenze non dichiarate.
- [x] Le query sono preparate.
- [x] Entità e campi sono in whitelist.
- [x] Trasporto, validazione, orchestrazione e persistenza sono separati.
- [x] Gli errori HTTP non mostrano stack trace, query o percorsi.
- [x] I test automatici sono inclusi ed eseguibili.
- [x] Non risultano attese indefinite note; una guardia AST rifiuta
      `WaitForExit()` senza timeout negli script PowerShell.
- [x] PostgreSQL e PHP/PDO applicano timeout finiti, configurabili e validati.
- [x] `mvn clean test` rileva ed esegue realmente tre contratti Java.

## Compatibilità

- [x] Python 3.12 è supportato.
- [x] Django e dipendenze sono disponibili offline.
- [x] Esiste un WAR per Tomcat 9/Java 8+.
- [x] Esiste un WAR per Tomcat 11/Java 17+.
- [x] Il configuratore seleziona l'artefatto corretto.
- [x] Maven, Gradle, Composer, Node.js e IDE non sono richiesti.
- [x] PostgreSQL viene rilevato e verificato.

## Installazione e verifica

- [x] Tutta la configurazione parte da riga di comando.
- [x] La procedura è stata provata da una copia pulita.
- [x] Installazione e verifica terminano in cinque minuti o meno.
- [x] Il tempo è stato misurato e registrato.
- [x] Prerequisiti e versioni ammesse sono espliciti.
- [x] I passi sono numerati e facilmente individuabili.
- [x] I casi avversi hanno diagnosi e soluzione.
- [x] Non viene dato nulla per scontato.
- [x] Il comando di verifica prova davvero i tre servizi e il database.
- [x] Un percorso Windows troppo lungo viene rifiutato prima della copia o
      dell'installazione con indicazione di riestrarre in `C:\DriveAura51`.

## Documentazione

- [x] Il manuale è destinato a un utente generico.
- [x] Il manuale è sintetico e non è un diario di sviluppo.
- [x] Le frasi sono brevi.
- [x] Si usano imperativo o infinito, non il futuro.
- [x] Lo stesso componente mantiene sempre lo stesso nome.
- [x] Il manuale spiega cosa si installa.
- [x] Il manuale elenca i prerequisiti.
- [x] Il manuale descrive installazione e verifica.
- [x] Il manuale spiega cosa fare se qualcosa va male.
- [x] Il manuale finale è un PDF leggibile e verificato visivamente.
- [x] Il documento delle scelte è di circa una pagina ed è in PDF.

## Materiale di consegna

- [x] È incluso un dump verificabile del database di origine.
- [x] Sono inclusi codice, configurazioni di esempio e artefatti.
- [x] Cache, log, ambienti virtuali, credenziali e file IDE sono esclusi.
- [x] L'archivio viene estratto e verificato in una cartella nuova.
- [x] I PDF si aprono e non presentano testo tagliato o illeggibile.

## Email

- [x] La bozza usa un oggetto con prefisso `[PW26]`.
- [x] La bozza usa il nome del gruppo `Drive Aura 51`.
- [x] La bozza indica il secondo progetto.
- [x] La bozza dichiara la scelta B nel corpo.
- [ ] All'invio, sostituire i segnaposto e inserire tutti i membri in CC.
- [ ] All'invio, verificare che ZIP e checksum allegati siano accessibili e
      che i due PDF contenuti nello ZIP si aprano.

## Penalità da evitare

- [ ] Ricontrollare destinatari, CC e allegati immediatamente prima dell'invio.
- [x] Nessun superamento dei cinque minuti nelle prove pulite finali.
- [x] Il manuale contiene prerequisiti, passi numerati, verifica e diagnosi.
