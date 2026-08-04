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
T09 ha prodotto il pacchetto offline. T11.1 ha chiuso i rischi di attese
indefinite e ha riconfermato la consegnabilità: le prove finali da ZIP pulito
sono terminate in 42,732 secondi con Tomcat 11 e 43,334 secondi con Tomcat 9,
senza download. Il candidato riproducibile misura 12.855.976 byte e ha
SHA-256
`1019d2cc3f08d5c07e81b129bf786355b5ccd5471dba7d0ad0fa1fbcd6d5442c`.
Lo stato vincolante resta sempre in `TASKS.md`.

Il 4 agosto 2026 il componente PHP è stato caricato su Altervista e health è
stato osservato con HTTP 200. La verifica del manifest è però bloccata perché
l'account non propaga `SetEnv` al processo PHP; non usare ancora l'endpoint
come sorgente della servlet. L'evidenza è in
`docs/VERIFICA_ALTERVISTA.md`.

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
interamente in questa cartella. La prima pubblicazione Altervista è stata
autorizzata e provata il 4 agosto 2026; ogni ulteriore intervento remoto
richiede una nuova autorizzazione.

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
- `docs/VERIFICA_T11.md`: audit conclusivo, prove finali e limiti;
- `docs/VERIFICA_T11_1.md`: attese finite e verdetto di consegnabilità;
- `docs/VERIFICA_ALTERVISTA.md`: pubblicazione remota, blocco `SetEnv` e
  pulizia osservata;
- `docs/BOZZA_EMAIL_CONSEGNA.md`: bozza non inviata e controlli pre-invio;
- `docs/RISCHI.md`: rischi e contromisure.

## Avvio del lavoro

Codex deve leggere i documenti elencati in `AGENTS.md`, eseguire soltanto
l'attività marcata `AUTORIZZATA` in `TASKS.md`, verificare il risultato,
aggiornare `TASKS.md` e `PROJECT_STATUS.md`, quindi fermarsi.
