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
`docs/CONTRATTO_DATI.md`. Prima dell'importazione verificare il checksum del
pacchetto sorgente e ripristinarlo in un database MariaDB vuoto. Dopo la
migrazione confrontare per ogni entità conteggio e digest tra manifest PHP,
registro Django e ricalcolo dei record PostgreSQL.

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

Per i guasti temporanei T07 usa `scripts/t07-fault-proxy.py` soltanto su
loopback. Il proxy può iniettare una sola attesa oltre timeout, uno stato HTTP
temporaneo o un digest alterato. Ogni risposta sintetica consuma il corpo
della richiesta e chiude la connessione; il log non contiene header o payload.
Il test deve dimostrare sia il numero limitato di tentativi sia l'assenza di
retry per dataset, digest, autenticazione o contratto non validi.

Per il riavvio:

1. partire da PostgreSQL vuoto e avviare una migrazione massiva;
2. attendere un checkpoint intermedio persistito;
3. arrestare soltanto la servlet;
4. riavviarla con lo stesso `migrationId`;
5. verificare che riparta dal cursore e dalla sequenza confermati;
6. controllare 36.176 righe, 364 lotti e stato `completed`;
7. rilanciare lo stesso identificativo e verificare conteggi invariati.

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

## 8. Esito osservato per T07

Il 25 luglio 2026 la migrazione massiva da PostgreSQL vuoto ha completato
36.176 righe in 364 lotti attraverso Tomcat 11; il rilancio dello stesso
`migrationId` attraverso Tomcat 9 non ha creato duplicati. Una seconda
migrazione è stata interrotta dopo un checkpoint intermedio e completata,
sempre con lo stesso identificativo, dopo il riavvio di Tomcat 9.

Sono stati inoltre osservati timeout remoto, HTTP 503 locale, dataset cambiato,
digest errato e duplicato uguale o discordante. Le query SQL hanno restituito
zero violazioni e l'audit Django ha ricalcolato digest uguali al manifest.
Tempi, digest, checkpoint ed esiti HTTP sono registrati in
`docs/VERIFICA_T07.md`.

Questo esito soddisfa la parte massiva e di resilienza, ma non chiude ancora i
criteri di release relativi a installazione pulita, limite di cinque minuti e
documenti finali.

## 9. Esito osservato per T09

Il candidato offline è stato estratto in una cartella nuova con spazi e
verificato senza accesso alla rete. Python 3.12.10, Java 23.0.2,
Tomcat 11.0.24 e PostgreSQL 18.4 hanno completato installazione, migrazioni,
salute, readiness, 22 righe/22 lotti, rilancio idempotente, audit e cleanup in
43,571 secondi wall-clock.

Tomcat 9.0.120 ha superato la stessa verticale in 38,822 secondi. Sono passati
16 casi avversi, runner completo, controlli migrazioni, build Maven e audit
dell'archivio. I PDF A4 finali sono stati renderizzati e ispezionati pagina per
pagina. Dettagli, limiti e hash sono in `docs/VERIFICA_T09.md`.

## 10. Esito osservato per T11

Il 30 luglio 2026 l'audit finale ha ripetuto la prova da una nuova copia del
pacchetto finale con watchdog finiti e PostgreSQL reale. Tomcat 9.0.120 ha
completato in 45,619 secondi wall-clock; Tomcat 11.0.24 ha completato in
46,427 secondi. Entrambi hanno trasferito 22 righe in 22 lotti, superato il
rilancio idempotente e liberato tutte le porte.

Sono passati il runner rigoroso, la semantica `-AllowPartial`, 27 casi
installer, 5 test del mock remoto, 25 test Django, i controlli migrazioni su
PostgreSQL, il lint dei 18 file PHP e `mvn clean package`. Le evidenze massive,
il dump e gli otto digest sono stati ricalcolati senza ripetere la migrazione
costosa già osservata in T07.

Due build consecutive dello ZIP hanno prodotto 12.842.104 byte e SHA-256
`0184e28030d54518778307efcc0f5f11d8f0c1ab11c540b4ce3aab1286e15bea`.
Tutte le pagine dei due PDF sono state nuovamente renderizzate e ispezionate.
Dettagli, correzioni e limiti sono in `docs/VERIFICA_T11.md`.
