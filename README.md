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

Il 4 agosto 2026 il componente PHP aggiornato è stato collaudato su Altervista.
Il fallback server-only risolve il limite dell'account, che non propaga
`SetEnv`: `/health` risponde HTTP 200, il manifest anonimo HTTP 401 e quello
autenticato HTTP 200 con otto entità. Il database remoto contiene però una
riga eccedente sia in `ricovero` sia in `patologia_ricovero`. Il preflight
T13.1 ha inoltre rilevato una riga `ricovero` comune ma divergente e tre
progressivi diversi dal seed: cancellare soltanto le due righe extra non
renderebbe conformi i digest. Nessun DML è stato eseguito. HTTPS fallisce la
validazione del certificato e l'attivazione dal pannello richiede
identificazione telefonica. Non usare ancora l'endpoint come sorgente della
servlet e non modificare il database senza una nuova autorizzazione.
L'evidenza completa è in `docs/VERIFICA_ALTERVISTA.md`.

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
- `docs/VERIFICA_ALTERVISTA.md`: fallback remoto, collaudo HTTP, preflight
  forense del database, digest e limite HTTPS osservati;
- `docs/BOZZA_EMAIL_CONSEGNA.md`: bozza non inviata e controlli pre-invio;
- `docs/RISCHI.md`: rischi e contromisure.

## Avvio del lavoro

Codex deve leggere i documenti elencati in `AGENTS.md`, eseguire soltanto
l'attività marcata `AUTORIZZATA` in `TASKS.md`, verificare il risultato,
aggiornare `TASKS.md` e `PROJECT_STATUS.md`, quindi fermarsi.
