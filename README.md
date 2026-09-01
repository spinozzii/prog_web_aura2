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
senza download. T16 aggiunge `verifica-rapida.bat`, un ingresso guidato da
Prompt dei comandi che verifica l'integrità e non sovrascrive database
esistenti. Il candidato aggiornato misura 12.867.808 byte e ha SHA-256
`ae7d6ef17c9f1a31291c5a53766e5bc4fba7fc73bfaf5d3d8fa5e4c4d521d2a0`.
Lo stato vincolante resta sempre in `TASKS.md`.

Il 20 agosto 2026 il componente PHP è stato collaudato definitivamente su
Altervista. Il fallback server-only risolve il limite `SetEnv`; HTTPS presenta
un certificato valido e `/health` risponde 200 diretto, il manifest anonimo
401 e quello autenticato 200. Dopo backup completo verificato, le sole otto
tabelle sanitarie sono state ricostruite dalle fonti ufficiali: 36.176 righe,
otto digest e `datasetId` coincidono con T07. Una migrazione reale attraverso
Tomcat 11, Django e PostgreSQL ha completato 364 lotti; il rilancio è
idempotente e il WAR Tomcat 9 è stato riconfermato. L'evidenza completa è in
`docs/VERIFICA_ALTERVISTA.md`.

La consegna principale resta il pacchetto offline pubblicato su `consegna`.
L'endpoint Altervista conforme è disponibile come sorgente reale opzionale;
la prova standard del docente resta offline e non richiede rete o token.

Ogni valore d'ambiente ha precedenza e, soltanto per le chiavi assenti, il
servizio legge `remote-php/config/local.php`. Il repository contiene
esclusivamente `local.php.example`; il file reale è ignorato da Git e non fa
parte del pacchetto di consegna. Prima di inserirvi valori reali è stato
verificato il diniego HTTP della directory `config`.

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
autorizzata il 4 agosto 2026 e riallineata il 20 agosto 2026; ogni ulteriore
intervento remoto richiede una nuova autorizzazione.

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
- `docs/VERIFICA_ALTERVISTA.md`: pubblicazione HTTPS, backup/riallineamento,
  manifest T07 e verticale reale osservata;
- `docs/BOZZA_EMAIL_CONSEGNA.md`: bozza non inviata e controlli pre-invio;
- `docs/RISCHI.md`: rischi e contromisure.

## Avvio del lavoro

Codex deve leggere i documenti elencati in `AGENTS.md`, eseguire soltanto
l'attività marcata `AUTORIZZATA` in `TASKS.md`, verificare il risultato,
aggiornare `TASKS.md` e `PROJECT_STATUS.md`, quindi fermarsi.
