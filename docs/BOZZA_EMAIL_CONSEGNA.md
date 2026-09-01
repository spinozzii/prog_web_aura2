# Bozza email di consegna

Questa è una bozza. Non inviare prima di avere sostituito tutti i segnaposto e
verificato gli allegati.

```text
A: paolo.fosci@unibg.it
CC: <INDIRIZZO MEMBRO 1>; <INDIRIZZO MEMBRO 2>; <ALTRI MEMBRI DEL GRUPPO>
Oggetto: [PW26] Drive Aura 51 - Secondo progetto

Buongiorno,

il gruppo Drive Aura 51 consegna il secondo progetto di Programmazione Web.

La scelta progettuale adottata è la scelta B: web-service PHP remoto,
servlet Java intermedia e web-service Python/Django locale per la migrazione
dei dati in PostgreSQL.

Allegati:

- drive-aura-51-offline.zip
- drive-aura-51-offline.zip.sha256

SHA-256 dello ZIP:
ae7d6ef17c9f1a31291c5a53766e5bc4fba7fc73bfaf5d3d8fa5e4c4d521d2a0

Il pacchetto contiene il manuale PDF, il documento PDF delle scelte, i
sorgenti, i WAR Tomcat 9 e 11, la wheelhouse offline, il dump sorgente e gli
strumenti di installazione e verifica, incluso l'ingresso `verifica-rapida.bat`.

La verifica standard della consegna è offline e locale. È inoltre disponibile
come sorgente reale opzionale il servizio PHP Altervista:
https://motorizzami.altervista.org/drive-aura-api/remote-php/public/health
Il servizio usa HTTPS valido e dataset massivo T07 conforme. Per una migrazione
reale serve soltanto `REMOTE_API_SECRET`, fornito separatamente o su richiesta;
non sono incluse né necessarie credenziali del pannello Altervista o password
del suo database. Il docente inserisce invece le proprie credenziali PostgreSQL
locali durante la verifica.

Cordiali saluti,

Drive Aura 51
<NOMI E COGNOMI DI TUTTI I MEMBRI>
```

## Controllo prima dell'invio

- sostituire tutti i segnaposto;
- inserire in CC tutti i membri del gruppo;
- allegare ZIP e sidecar dalla cartella `dist`;
- ricalcolare SHA-256 e confrontarlo con il valore nella bozza;
- aprire o scaricare entrambi gli allegati dalla mail preparata;
- ricontrollare oggetto, scelta B e indicazione del secondo progetto.
