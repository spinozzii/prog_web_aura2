# Scelte progettuali

> Stato: bozza iniziale. Aggiornare dopo l'implementazione e produrre un PDF di
> circa una pagina.

## Obiettivo

Il progetto migra il database del Servizio Sanitario usato nel Progetto 1 da
MySQL/MariaDB su Altervista a PostgreSQL locale. Il trasferimento attraversa
un web-service PHP remoto, una servlet Java intermedia e un web-service Django
locale.

## Scelte principali

È stato scelto PostgreSQL perché il modello contiene chiavi composte, chiavi
esterne, vincoli univoci e una relazione molti-a-molti. La struttura
relazionale può quindi essere preservata senza trasformazioni documentali.

I dati vengono esportati in JSON a lotti ordinati per chiave primaria. Il
manifest iniziale dichiara identificativo del dataset, conteggi e digest.
Questa soluzione evita risposte troppo grandi e permette di rilevare
trasferimenti incompleti o dati cambiati durante l'esecuzione.

La servlet non accede ai database. Coordina le chiamate HTTP, mantiene lo stato
della migrazione e inoltra i lotti. La logica Java è condivisa, mentre due
adattatori producono artefatti compatibili con Tomcat 9 e Tomcat 11.

Il servizio Django valida ogni lotto e lo inserisce in una transazione
PostgreSQL. L'identificativo della migrazione, la sequenza e il digest rendono
il trasferimento ripetibile senza duplicazioni. La migrazione viene dichiarata
completa soltanto dopo il confronto di conteggi, digest e vincoli.

## Installazione

La consegna include dipendenze Python offline e WAR precompilati. Un
configuratore da riga di comando rileva le versioni presenti, seleziona
l'artefatto corretto e avvia i controlli. La procedura non richiede IDE,
compilatori aggiuntivi o download durante la verifica.

## Verifica

Il collaudo confronta tutte le entità, comprese chiavi composte, sottoinsiemi
delle patologie, associazioni e progressivi. Un comando finale espone lo stato
dei tre servizi e l'esito dell'ultima migrazione.

