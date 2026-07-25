# Checklist del docente

## Scelta e architettura

- [ ] La consegna dichiara esplicitamente il caso B.
- [ ] Il servizio remoto è PHP sul sito del Progetto 1.
- [ ] Il servizio locale è Python/Django.
- [ ] Lo strato intermedio è una servlet Java.
- [ ] Il percorso reale dei dati è PHP → servlet → Django → PostgreSQL.
- [ ] La servlet non accede direttamente ai database.

## Migrazione

- [ ] Tutte le otto entità previste vengono migrate.
- [ ] Il dataset massivo completo viene trasferito.
- [ ] Conteggi sorgente e destinazione coincidono.
- [ ] Digest sorgente e destinazione coincidono.
- [ ] Chiavi primarie semplici e composte sono preservate.
- [ ] Non esistono righe orfane.
- [ ] Il direttore sanitario resta obbligatorio e univoco.
- [ ] Ogni Ricovero mantiene cittadino, ospedale e patologie.
- [ ] I sottoinsiemi cronica e mortale restano indipendenti.
- [ ] I progressivi valgono `MAX(cod) + 1`.
- [ ] Un rilancio non crea duplicati.
- [ ] Un errore intermedio non viene dichiarato come successo.

## Codice

- [ ] Tutto il codice sorgente è incluso.
- [ ] Le scelte non ovvie sono commentate.
- [ ] Non ci sono credenziali o token reali.
- [ ] Non ci sono dipendenze non dichiarate.
- [ ] Le query sono preparate.
- [ ] Entità e campi sono in whitelist.
- [ ] Trasporto, validazione, orchestrazione e persistenza sono separati.
- [ ] Gli errori non mostrano stack trace, query o percorsi.
- [ ] I test automatici sono inclusi ed eseguibili.

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

- [ ] Oggetto con prefisso `[PW26]`.
- [ ] Oggetto con nome del gruppo.
- [ ] Oggetto con indicazione del secondo progetto.
- [ ] Corpo con dichiarazione della scelta B.
- [ ] Tutti i membri del gruppo in CC.
- [ ] Allegati o collegamenti sono accessibili.

## Penalità da evitare

- [ ] Nessuna difformità nell'email.
- [ ] Nessun superamento dei cinque minuti.
- [ ] Nessuna necessità per il docente di chiedere chiarimenti sul manuale.
