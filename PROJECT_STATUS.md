# Stato del progetto

## Stato corrente

La scelta B è approvata: migrazione tramite servizio PHP remoto, servlet Java
intermedia e servizio Django locale verso PostgreSQL.

T00, T01 e T01.1 sono completate. T01.2 è in revisione. Non esiste alcuna
attività autorizzata; T02 resta nel backlog.

## Fatti e decisioni verificati

- Il caso B richiede PHP remoto, servlet Java intermedia, Python/Django locale
  e PostgreSQL.
- Django 5.2.16 è fissato per Python 3.12.
- Tomcat 9 usa `javax.servlet` e Java 8+, Tomcat 11 usa `jakarta.servlet` e
  Java 17+; la logica Java comune resta separata dagli adattatori.
- Il Progetto 1 è una fonte in sola lettura e non è stato coinvolto.

## Esito T01.2

- Il controllo remoto in sola lettura ha restituito successo senza ref o commit:
  `https://github.com/spinozzii/prog_web_aura2.git` era vuoto.
- È stato inizializzato un repository Git solo in
  `drive-aura-51-webservices`, sul ramo `main`, e configurato `origin` con
  l'URL esatto richiesto.
- Prima del checkpoint sono stati ispezionati tutti i file non ignorati e le
  regole `.gitignore`; risultano esclusi `bridge-servlet/**/target/`, cache
  Python, configurazioni locali e file di log/temporanei.
- È stato usato soltanto il nome e l'email Git già disponibili; nessuna
  configurazione Git globale, identità o credenziale è stata creata o modificata.
- Il checkpoint iniziale `c4ceed79097ecf245f807c381ad27274e3092f00` contiene
  sorgenti, test e documentazione del progetto.
- `main` è pubblicato su `origin/main` senza force push e segue il remoto.

## Limiti residui

- Restano da definire il percorso reale di Tomcat del docente, la distribuzione
  offline definitiva delle dipendenze Python, le credenziali PostgreSQL e il
  formato del dump; questi punti non autorizzano T02.

## Prossimo passo

Revisionare T01.2. Non iniziare T02 senza approvazione esplicita.
