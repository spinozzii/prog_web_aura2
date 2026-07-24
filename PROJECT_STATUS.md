# Stato del progetto

## Stato corrente

La scelta B è approvata: migrazione tramite servizio PHP remoto, servlet Java
intermedia e servizio Django locale verso PostgreSQL.

T00, T01, T01.1 e T01.2 sono completate. T02 è suddivisa in quattro passi
verificabili; T02.1 è in revisione. Non esiste alcuna attività autorizzata.

## Fatti e decisioni verificati

- Il caso B richiede PHP remoto, servlet Java intermedia, Python/Django locale
  e PostgreSQL.
- Django 5.2.16 è fissato per Python 3.12.
- Tomcat 9 usa `javax.servlet` e Java 8+, Tomcat 11 usa `jakarta.servlet` e
  Java 17+; la logica Java comune resta separata dagli adattatori.
- Il Progetto 1 è una fonte in sola lettura e non è stato coinvolto.
- `origin` è `https://github.com/spinozzii/prog_web_aura2.git` e `main` segue
  `origin/main`.

## Esito T02.1

- `docs/CONTRATTO_DATI.md` definisce il contratto eseguibile di `patologia`:
  ordine dei campi, serializzazione JSON compatta, UTF-8 senza BOM, escape,
  slash invariati, ordinamento per `cod`, LF finale e SHA-256.
- La fixture `tests/fixtures/patologia-canonical.json` include record leggibili
  con accenti, virgolette, barra rovesciata, newline, slash e criticità 1/5.
  Il digest previsto è
  `53f27d16f82cdf36bbdb1bd28b61bc6cf7f7057d5cc135a66c2bd9105cc27b83`.
- PHP, Java core compatibile Java 8 e Python implementano ognuno una sola
  funzione di canonicalizzazione e digest senza nuove dipendenze applicative.
- Il runner completo con PHP 8.3.32, Python 3.12.13/Django 5.2.16 e Java ha
  superato salute e canonicalizzazione in tutti e tre i linguaggi.
- Senza runtime nel PATH il runner fallisce; `-AllowPartial` termina con
  riepilogo esplicito degli skip.
- `mvn clean package` con Maven 3.9.16 ha superato la compilazione Java e ha
  prodotto entrambi i WAR Tomcat 9 e Tomcat 11.
- Gli endpoint `/health` non sono stati modificati. Non sono stati implementati
  manifest, export, orchestrazione, importazione, PostgreSQL o accesso ai dati.

## Limiti residui

- PHP e Django usati dai test completi sono runtime temporanei, non componenti
  della consegna.
- T02.2, T02.3 e T02.4 restano nel backlog e non sono stati avviati.

## Prossimo passo

Revisionare T02.1. Non iniziare T02.2 senza approvazione esplicita.
