# Istruzioni permanenti per Codex

## Obiettivo

Sviluppare il Progetto 2 di Programmazione Web, scelta B:

- web-service remoto in PHP sul sito del Progetto 1;
- servlet Java intermedia eseguita su Tomcat;
- web-service locale in Python/Django;
- migrazione dei dati del Progetto 1 verso PostgreSQL locale.

Il progetto deve rispettare integralmente `docs/REQUISITI.md` e
`docs/CHECKLIST_PROFESSORE.md`.

## Prima di iniziare qualsiasi attività

1. Leggi integralmente questo file.
2. Leggi `README.md`.
3. Leggi `TASKS.md` e lavora soltanto sull'attività `AUTORIZZATA`.
4. Leggi `PROJECT_STATUS.md`.
5. Consulta `docs/REQUISITI.md`, `docs/ARCHITETTURA.md`,
   `docs/CONTRATTO_DATI.md`, `docs/DECISIONI.md` e i documenti pertinenti.
6. Analizza i file esistenti prima di modificarli.

Se due documenti sembrano in conflitto, non scegliere arbitrariamente:
registra il dubbio in `PROJECT_STATUS.md` e chiedi una decisione.

## Confini del progetto

- Lavora soltanto dentro `drive-aura-51-webservices`.
- Considera il Progetto 1 una fonte in sola lettura.
- Non modificare né distribuire il sito Altervista senza autorizzazione
  esplicita.
- Non inserire credenziali, token, URL privati o dump con segreti nel
  repository.
- Non aggiungere un portale o funzionalità estranee alla migrazione.

## Architettura non negoziabile

- Il servizio remoto è PHP compatibile con Altervista e PDO MySQL/MariaDB.
- La servlet Java interroga il servizio remoto e inoltra i dati al servizio
  locale. Non accede direttamente a nessuno dei due database.
- Il servizio locale è sviluppato con Django 5.2 LTS e Python 3.12.
- Il database locale è PostgreSQL.
- Il flusso consegnato deve attraversare tutti e tre i componenti.
- Tomcat 9 e Tomcat 11 richiedono artefatti distinti:
  `javax.servlet` per Tomcat 9 e `jakarta.servlet` per Tomcat 11.
- Non assumere che Maven, Gradle, Composer, Node.js, un IDE o l'accesso a
  Internet siano disponibili sulla macchina del docente.

## Contratto e migrazione

- Usa JSON UTF-8 e una versione esplicita del contratto.
- Esporta solo entità e campi in whitelist.
- Usa paginazione deterministica; non inviare il dataset completo in una sola
  risposta.
- Mantieni nomi, tipi, chiavi e relazioni descritti in
  `docs/CONTRATTO_DATI.md`.
- Inserisci i dati nell'ordine delle dipendenze.
- Ogni lotto deve essere transazionale e ripetibile senza duplicazioni.
- Una migrazione interrotta deve poter riprendere o essere rilanciata in modo
  sicuro.
- Verifica dataset, conteggi, vincoli e digest prima di dichiarare successo.
- Non indebolire i vincoli PostgreSQL per facilitare l'importazione.

## Installazione e compatibilità

- La configurazione e l'avvio devono avvenire da riga di comando.
- L'installazione e la verifica complete devono rientrare nel limite di cinque
  minuti indicato nelle linee guida.
- Le dipendenze Python devono essere fissate e installabili offline dentro un
  ambiente virtuale locale.
- Gli artefatti Java devono essere precompilati; la macchina del docente non
  deve compilare il progetto.
- La procedura deve rilevare Python, Java, Tomcat e PostgreSQL e produrre
  messaggi di errore operativi.
- Non richiedere Eclipse, Visual Studio, VS Code o strumenti analoghi.
- Ogni istruzione del manuale deve essere stata provata da una copia pulita
  della consegna.

## Qualità e sicurezza

- Valida schema, tipi, dimensioni, cursori, nomi di entità e identificatori.
- Usa query preparate e transazioni.
- Proteggi gli endpoint con un segreto configurabile, mai scritto nel codice.
- Applica timeout, dimensione massima dei lotti e gestione esplicita degli
  errori HTTP.
- Non mostrare stack trace, percorsi locali, segreti o dettagli del database.
- Mantieni separati trasporto HTTP, validazione, orchestrazione e persistenza.
- Commenta le scelte non ovvie; evita commenti che ripetono il codice.
- Ogni comando o endpoint visibile deve funzionare realmente.

## Regole operative

- Lavora su una sola attività alla volta.
- Non iniziare elementi del backlog.
- Mantieni modifiche piccole, verificabili e coerenti.
- Non eliminare fonti o dati senza richiesta esplicita.
- Non modificare requisiti per adattarli al codice.
- Non dichiarare completata un'attività senza controlli proporzionati al
  rischio.
- Se manca una dipendenza o un runtime, esegui comunque test statici e
  isolati, registra il limite e fermati senza simulare un esito positivo.

## Chiusura di ogni attività

Prima di fermarti:

1. esegui i test e i controlli disponibili;
2. aggiorna `PROJECT_STATUS.md` con modifiche, test, problemi e prossimo passo;
3. sposta l'attività in `TASKS.md` da `AUTORIZZATA` a `IN REVISIONE`;
4. non autorizzare autonomamente l'attività successiva;
5. riassumi risultato, file modificati, verifiche e problemi.

## Efficienza

Alla prima attività leggi tutti i documenti fondamentali. Nelle attività
successive rileggi `AGENTS.md`, `TASKS.md`, `PROJECT_STATUS.md`, i file
direttamente coinvolti e soltanto i requisiti pertinenti. Non ristampare file
lunghi o codice invariato nei report.

