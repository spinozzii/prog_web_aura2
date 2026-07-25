# Registro dei rischi

## R01 - Incompatibilità Tomcat 9/11

- Probabilità: alta.
- Impatto: alto.
- Causa: namespace `javax.servlet` contro `jakarta.servlet` e requisiti Java
  differenti.
- Mitigazione: logica Java condivisa e due adattatori/WAR; test su entrambi.
- Segnale di chiusura: entrambi i WAR rispondono al contratto di salute.

## R02 - Dipendenze non presenti

- Probabilità: alta.
- Impatto: alto.
- Causa: la macchina garantisce Python ma non Django o i driver PostgreSQL.
- Mitigazione: pacchetto offline con versioni e hash, ambiente virtuale locale,
  nessuna modifica globale.
- Segnale di chiusura: installazione pulita senza rete.
- Stato: chiuso in T09 con wheelhouse verificata e prova pulita in 43,571 s.

## R03 - Chiavi composte in Django

- Probabilità: media.
- Impatto: alto.
- Causa: supporto ORM recente e relazioni verso chiavi composte ancora
  limitate.
- Mitigazione: PostgreSQL come autorità dei vincoli, migrazioni SQL esplicite,
  repository di importazione e test reali.
- Segnale di chiusura: Ricovero e Patologia-Ricovero importati con PK/FK reali.

## R04 - Limiti Altervista

- Probabilità: media.
- Impatto: alto.
- Causa: timeout, memoria o limiti di risposta sull'hosting condiviso.
- Mitigazione: lotti piccoli misurati, keyset pagination, risposte streaming
  dove sicuro, nessun caricamento dell'intero dataset.
- Segnale di chiusura: migrazione massiva remota completata.

## R05 - Dataset incoerente durante l'export

- Probabilità: bassa sul dataset di consegna.
- Impatto: alto.
- Causa: modifiche al database tra richieste.
- Mitigazione: `datasetId`, conteggi e digest; sospensione delle modifiche
  durante la prova; rifiuto della finalizzazione se cambia il manifest.
- Segnale di chiusura: test di modifica intermedia rilevato correttamente.

## R06 - Superamento dei cinque minuti

- Probabilità: media.
- Impatto: alto e penalizzato.
- Causa: download, compilazione, configurazione manuale o troppi passaggi.
- Mitigazione: artefatti precompilati, dipendenze offline, configuratore unico,
  prova cronometrata frequente.
- Segnale di chiusura: due prove pulite consecutive entro il limite.
- Stato: chiuso in T09 con Tomcat 11 in 43,571 s e Tomcat 9 in 38,822 s.

## R07 - Migrazione parziale dichiarata riuscita

- Probabilità: media.
- Impatto: alto.
- Causa: errori tra lotti o retry non idempotenti.
- Mitigazione: stato esplicito, registro lotti, digest, checkpoint e
  finalizzazione separata.
- Segnale di chiusura: test di interruzione e ripresa senza duplicazioni.

## R08 - Esposizione del database remoto

- Probabilità: media.
- Impatto: alto.
- Causa: endpoint pubblico senza protezione o parametri SQL liberi.
- Mitigazione: segreto esterno, HTTPS, sola lettura, whitelist, rate limit
  compatibile con Altervista e messaggi neutri.
- Segnale di chiusura: test di accesso negato e audit del codice PHP.

## R09 - Manuale ambiguo

- Probabilità: media.
- Impatto: alto e penalizzato.
- Causa: istruzioni non provate o rivolte al docente come sviluppatore.
- Mitigazione: manuale breve per utente generico, passi numerati, casi avversi,
  prova da archivio pulito.
- Segnale di chiusura: esecuzione riuscita seguendo solo il PDF.
- Stato: chiuso in T09; procedura provata e 3 pagine renderizzate e ispezionate.

## R10 - Scope eccessivo

- Probabilità: alta.
- Impatto: medio-alto.
- Causa: aggiunta di dashboard, portale, autenticazione utenti o tecnologie
  estranee.
- Mitigazione: TASKS con una sola attività autorizzata e revisioni per
  traguardi.
- Segnale di chiusura: ogni file consegnato è riconducibile a un requisito.
