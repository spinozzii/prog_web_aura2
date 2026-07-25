# Drive Aura 51 - Migrazione dati tramite Web-service

Secondo progetto di Programmazione Web, scelta B delle linee guida: migrare i
dati del Progetto 1 da MySQL/MariaDB remoto a PostgreSQL locale attraverso tre
componenti obbligatori.

## Architettura obbligatoria

```text
MySQL/MariaDB su Altervista
        |
Web-service PHP remoto
        |
Servlet Java su Tomcat
        |
Web-service Django locale
        |
PostgreSQL locale
```

La servlet Java è l'unico coordinatore del trasferimento. Non è ammesso un
collegamento diretto tra il servizio PHP e il servizio Django nel flusso
consegnato.

## Stato

T07 ha verificato la verticale completa sul dataset massivo di 36.176 righe.
T09 ha prodotto il candidato offline con sorgenti, wheelhouse, WAR, dump,
configuratore e PDF. La prova da ZIP pulito ha completato installazione,
configurazione e verifica in 43,571 secondi senza usare Internet. Lo stato
vincolante resta sempre in `TASKS.md`.

## Origine dei dati

Il progetto sorgente è:

`../../progetto 1/drive-aura-51-servizio-sanitario`

Il database contiene:

- 3.200 cittadini;
- 30 ospedali;
- 200 patologie;
- 12.000 ricoveri;
- 20.492 associazioni Patologia-Ricovero;
- i sottoinsiemi delle patologie e i progressivi dei ricoveri.

Il progetto sorgente è una fonte in sola lettura. Il codice del Progetto 2 vive
interamente in questa cartella; l'eventuale pubblicazione dell'endpoint PHP su
Altervista avverrà solo in una fase esplicitamente autorizzata.

## Documenti principali

- `AGENTS.md`: regole permanenti per Codex;
- `TASKS.md`: unica fonte di autorizzazione delle attività;
- `PROJECT_STATUS.md`: stato verificato;
- `docs/REQUISITI.md`: requisiti consolidati;
- `docs/ARCHITETTURA.md`: architettura e contratti;
- `docs/CONTRATTO_DATI.md`: dati, ordine e formato di migrazione;
- `docs/DECISIONI.md`: decisioni durevoli;
- `docs/CHECKLIST_PROFESSORE.md`: criteri di valutazione e penalità;
- `docs/PIANO_TEST.md`: strategia di verifica;
- `docs/VERIFICA_T02_2.md`: procedura ed esito osservato della prima verticale;
- `docs/VERIFICA_T03.md`: procedura ed esito della verticale completa;
- `docs/VERIFICA_T07.md`: migrazione massiva e prove di resilienza osservate;
- `docs/VERIFICA_T09.md`: pacchetto offline, prova pulita, PDF e casi avversi;
- `docs/RISCHI.md`: rischi e contromisure.

## Avvio del lavoro

Codex deve leggere i documenti elencati in `AGENTS.md`, eseguire soltanto
l'attività marcata `AUTORIZZATA` in `TASKS.md`, verificare il risultato,
aggiornare `TASKS.md` e `PROJECT_STATUS.md`, quindi fermarsi.
