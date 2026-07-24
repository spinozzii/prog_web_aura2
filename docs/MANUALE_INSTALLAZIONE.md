# Manuale di installazione

> Stato: struttura iniziale, non consegnabile. Ogni istruzione deve essere
> sostituita con comandi provati durante T09 e il documento finale deve essere
> esportato in PDF.

## 1. Cosa si installa

Descrivere in poche righe:

- servizio locale Django;
- servlet Java;
- database PostgreSQL;
- collegamento al servizio PHP remoto.

## 2. Prerequisiti

Elencare versioni ammesse e comando per verificarle:

1. Python 3.12;
2. Java compatibile con il Tomcat presente;
3. Tomcat 9 oppure Tomcat 11;
4. PostgreSQL;
5. accesso al servizio PHP remoto.

Non indicare software che la procedura non usa.

## 3. Configurazione

Inserire passi numerati per:

1. estrarre l'archivio;
2. creare la configurazione locale da un esempio;
3. inserire le credenziali PostgreSQL e il segreto;
4. eseguire il configuratore;
5. verificare i prerequisiti.

## 4. Avvio

Indicare un comando principale e l'output atteso. Evitare istruzioni dipendenti
da un IDE.

## 5. Migrazione

Indicare:

1. comando o URL locale da usare;
2. stato atteso;
3. conteggi finali;
4. messaggio di successo.

## 6. Verifica

Fornire un comando unico che controlli:

- servizio PHP;
- servlet;
- Django;
- PostgreSQL;
- ultima migrazione completata.

## 7. Arresto

Indicare il comando e verificare che non lasci processi o file bloccati.

## 8. Problemi

Per ogni caso usare:

- sintomo;
- causa probabile;
- controllo;
- soluzione.

Casi minimi:

- Python non trovato;
- Java incompatibile con Tomcat;
- Tomcat non trovato o porta occupata;
- PostgreSQL non raggiungibile;
- credenziali errate;
- servizio remoto non raggiungibile;
- segreto errato;
- migrazione interrotta;
- verifica finale fallita.

