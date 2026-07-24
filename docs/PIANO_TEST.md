# Piano di test

## 1. Obiettivo

Dimostrare che i dati attraversano realmente PHP, servlet e Django, arrivano
integri in PostgreSQL e che un utente può installare e verificare il progetto
in non più di cinque minuti.

## 2. Livelli

### Test unitari

PHP:

- whitelist di entità;
- limite dei lotti;
- cursori validi e non validi;
- serializzazione canonica;
- errori senza dettagli sensibili.

Java:

- parsing del manifest;
- ordine delle entità;
- ciclo dei cursori;
- timeout e retry;
- propagazione di `migrationId`;
- gestione degli errori remoto/locale.

Python/Django:

- validazione di ogni entità;
- tipi, date, decimali e lunghezze;
- idempotenza del lotto;
- conflitto di digest;
- transazione e rollback;
- finalizzazione incompleta rifiutata.

### Test di contratto

Le stesse fixture JSON vengono usate nei tre linguaggi per verificare:

- endpoint di salute;
- manifest;
- pagina di export;
- lotto di import;
- errori;
- canonicalizzazione e digest.

### Test di integrazione

- PHP con MySQL/MariaDB di test;
- Django con PostgreSQL reale;
- servlet con server HTTP simulati per gli errori;
- servlet su Tomcat 9;
- servlet su Tomcat 11;
- migrazione verticale completa delle otto entità in ordine di dipendenza.

### Test end-to-end

1. Avviare PHP remoto o ambiente equivalente verificato.
2. Avviare PostgreSQL e Django locale.
3. Distribuire il WAR corretto su Tomcat.
4. Avviare la migrazione dalla servlet.
5. Attendere la finalizzazione.
6. Confrontare conteggi e digest.
7. Eseguire query di integrità.

## 3. Dataset

### Fixture minima

Deve includere:

- caratteri accentati;
- date ai limiti;
- importi con due decimali;
- una patologia solo cronica;
- una solo mortale;
- una appartenente a entrambi i sottoinsiemi;
- una senza specializzazione;
- almeno due ospedali;
- chiavi Ricovero ripetute in ospedali diversi;
- Ricovero con più patologie.

### Dataset massivo

Usare il dataset completo del Progetto 1. I conteggi attesi sono in
`docs/CONTRATTO_DATI.md`.

## 4. Casi avversi obbligatori

- segreto assente o errato;
- entità non ammessa;
- cursore alterato;
- lotto oltre il massimo;
- JSON non valido;
- campo mancante o in più;
- tipo o dominio errato;
- digest errato;
- dataset cambiato a metà migrazione;
- timeout remoto;
- errore temporaneo del servizio locale;
- PostgreSQL non disponibile;
- lotto duplicato uguale;
- lotto duplicato diverso;
- FK mancante;
- finalizzazione con lotti mancanti;
- riavvio dopo interruzione.

## 5. Verifiche PostgreSQL

- conteggio di ogni tabella;
- unicità delle PK;
- assenza di FK orfane;
- unicità dei direttori sanitari;
- criticità tra 1 e 5;
- durata tra 1 e 3650;
- costi non negativi;
- almeno una patologia per ogni ricovero;
- progressivo per ospedale uguale a `MAX(cod) + 1`;
- digest canonico per entità.

## 6. Prova dei cinque minuti

La prova parte da:

- archivio appena estratto;
- software ammesso già installato;
- nessun ambiente virtuale;
- nessun WAR già distribuito;
- database di destinazione vuoto;
- nessun IDE.

Cronometrare:

1. rilevamento prerequisiti;
2. configurazione;
3. preparazione Python;
4. preparazione PostgreSQL;
5. distribuzione e avvio;
6. salute/readiness;
7. migrazione o verifica richiesta dal manuale.

Registrare:

- ambiente;
- versioni;
- tempo totale;
- comandi;
- errori incontrati;
- esito.

Il manuale può contenere soltanto passi superati in questa prova.

## 7. Criterio di uscita

La release è candidata alla consegna soltanto se:

- tutti i test automatici passano;
- Tomcat 9 e 11 sono coperti dagli artefatti previsti;
- PostgreSQL reale è stato usato nell'integrazione;
- dataset massivo, conteggi, digest e vincoli coincidono;
- prova pulita entro cinque minuti superata;
- manuale e documento PDF sono verificati visivamente.
