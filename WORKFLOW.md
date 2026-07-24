# Workflow Work-Codex

## Principio

Work dirige il progetto e Codex implementa. Entrambi usano questa stessa
cartella; il passaggio di consegne avviene tramite file e revisione manuale.

Non esistono due copie del progetto e non si modifica il codice
contemporaneamente.

## Ruoli

### Work

- interpreta linee guida, requisiti e feedback del docente;
- mantiene architettura, decisioni e priorità;
- autorizza una sola attività in `TASKS.md`;
- revisiona ogni traguardo senza modificare il codice;
- trasforma i difetti in correzioni specifiche.

### Codex

- legge `AGENTS.md` e i documenti richiamati;
- esegue soltanto l'attività autorizzata;
- implementa codice e test;
- aggiorna `TASKS.md` e `PROJECT_STATUS.md`;
- si ferma in attesa della revisione.

## File di coordinamento

- `AGENTS.md`: regole permanenti;
- `TASKS.md`: coda e autorizzazione;
- `PROJECT_STATUS.md`: fatti verificati;
- `docs/DECISIONI.md`: decisioni durevoli;
- `docs/REQUISITI.md`: contratto funzionale;
- `docs/CHECKLIST_PROFESSORE.md`: criteri di accettazione.

Non duplicare la stessa informazione in più documenti se può essere richiamata.

## Ciclo

1. Work autorizza una sola attività.
2. Codex implementa e verifica.
3. Codex porta l'attività in `IN REVISIONE`, aggiorna lo stato e si ferma.
4. Work confronta il risultato con requisiti, checklist e decisioni.
5. Work approva e autorizza il passo seguente oppure assegna correzioni.

## Revisioni obbligatorie

Work revisiona almeno:

- scheletri avviabili e contratti di salute;
- prima migrazione verticale completa;
- completamento di tutte le entità;
- installazione pulita sotto cinque minuti;
- migrazione massiva e verifica;
- documentazione e pacchetto di consegna.

## Stati

- `AUTORIZZATA`: unica attività eseguibile;
- `BACKLOG`: non iniziare;
- `IN REVISIONE`: implementata, attende Work;
- `COMPLETATA`: approvata;
- `BLOCCATA`: richiede una decisione o intervento esterno.

Deve esistere al massimo una attività `AUTORIZZATA`.

## Prompt iniziale per Codex

> Leggi integralmente AGENTS.md, README.md, TASKS.md, PROJECT_STATUS.md,
> docs/REQUISITI.md, docs/ARCHITETTURA.md, docs/CONTRATTO_DATI.md,
> docs/DECISIONI.md e docs/CHECKLIST_PROFESSORE.md. Esegui soltanto
> l'attività marcata AUTORIZZATA. Verifica il risultato, aggiorna TASKS.md e
> PROJECT_STATUS.md, porta l'attività in IN REVISIONE e fermati. Non iniziare
> elementi del backlog e non modificare il Progetto 1.

Modello consigliato: GPT-5.6 Terra  
Utilizzo consigliato: medio

## Prompt di revisione per Work

> Revisiona l'attività indicata come IN REVISIONE. Confronta il risultato con
> AGENTS.md, docs/REQUISITI.md, docs/ARCHITETTURA.md,
> docs/CONTRATTO_DATI.md e docs/CHECKLIST_PROFESSORE.md. Non modificare il
> codice. Se trovi difetti, inserisci correzioni specifiche in TASKS.md;
> altrimenti approva il traguardo e autorizza il passo successivo.

## Regola del singolo autore

Durante l'implementazione Codex è l'unico autore del codice. Durante la
revisione Work non modifica il codice. I documenti di coordinamento sono
aggiornati da chi chiude la propria fase.

