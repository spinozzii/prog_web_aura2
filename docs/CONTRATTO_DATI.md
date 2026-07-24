# Contratto dei dati

## 1. Principi

- JSON UTF-8.
- Nomi dei campi in `snake_case`.
- Nessun campo non dichiarato.
- `null` ammesso soltanto dove indicato.
- Date civili in formato `YYYY-MM-DD`, senza fuso orario.
- Importi come stringhe decimali con due cifre, per evitare perdita di
  precisione nella serializzazione.
- Interi JSON senza separatori.
- Righe ordinate per la chiave primaria completa.
- I digest usano una rappresentazione canonica definita e testata in modo
  identico nei tre linguaggi.

## 2. Entità

### `cittadino`

Chiave: `cssn`.

Campi:

- `cssn`: stringa non vuota;
- `nome`: stringa non vuota;
- `cognome`: stringa non vuota;
- `data_nascita`: data;
- `luogo_nascita`: stringa non vuota;
- `indirizzo`: stringa non vuota.

### `patologia`

Chiave: `cod`.

Campi:

- `cod`: stringa non vuota, massimo 20 caratteri;
- `nome`: stringa non vuota;
- `criticita`: intero da 1 a 5.

### `patologia_cronica`

Chiave: `cod_patologia`.

Campi:

- `cod_patologia`: stringa non vuota, massimo 20 caratteri, FK verso
  `patologia.cod`.

### `patologia_mortale`

Chiave: `cod_patologia`.

Campi:

- `cod_patologia`: stringa non vuota, massimo 20 caratteri, FK verso
  `patologia.cod`.

### `ospedale`

Chiave: `codice`.

Campi:

- `codice`: stringa non vuota, massimo 20 caratteri;
- `nome`: stringa non vuota;
- `citta`: stringa non vuota;
- `indirizzo`: stringa non vuota;
- `direttore_sanitario_cssn`: stringa, FK verso `cittadino.cssn`, univoca.

### `ricovero`

Chiave composta: `cod_ospedale`, `cod`.

Campi:

- `cod_ospedale`: stringa non vuota, massimo 20 caratteri, FK verso
  `ospedale.codice`;
- `cod`: intero positivo;
- `paziente_cssn`: stringa, FK verso `cittadino.cssn`;
- `data_inizio`: data;
- `durata`: intero da 1 a 3650;
- `motivo`: stringa da 1 a 500 caratteri;
- `costo`: stringa decimale non negativa con due cifre.

### `patologia_ricovero`

Chiave composta: `cod_ospedale`, `cod_ricovero`, `cod_patologia`.

Campi:

- `cod_ospedale`: stringa non vuota, massimo 20 caratteri;
- `cod_ricovero`: intero positivo;
- `cod_patologia`: stringa non vuota, massimo 20 caratteri.

La coppia `cod_ospedale`, `cod_ricovero` riferisce `ricovero`; il codice della
patologia riferisce `patologia`.

### `progressivo_ricovero`

Chiave: `cod_ospedale`.

Campi:

- `cod_ospedale`: stringa non vuota, massimo 20 caratteri, FK verso
  `ospedale.codice`;
- `prossimo_cod`: intero positivo.

Al termine deve valere:

`prossimo_cod = MAX(ricovero.cod dello stesso ospedale) + 1`

## 3. Cursori

Il cursore HTTP è opaco e firmato o validato dal servizio remoto. La
paginazione sottostante usa:

- chiave semplice per entità con una sola PK;
- tupla completa in ordine lessicografico per chiavi composte.

Un cursore non valido, scaduto o riferito a un'altra entità produce errore
client esplicito. `limit` ha un massimo deciso dal server.

## 4. Canonicalizzazione e digest

La specifica eseguibile definitiva deve essere implementata una sola volta per
linguaggio e coperta da vettori di test condivisi.

Regole iniziali:

1. ordine dei campi uguale a quello dichiarato sopra;
2. escape JSON standard;
3. nessuno spazio superfluo;
4. codifica UTF-8 senza BOM;
5. righe separate da `LF`;
6. SHA-256 della sequenza canonica.

Prima della migrazione massiva devono esistere fixture con digest atteso,
verificate in PHP, Java e Python.

### 4.1 Contratto eseguibile iniziale: `patologia`

La fixture condivisa `tests/fixtures/patologia-canonical.json` definisce il
vettore iniziale eseguibile per `patologia`.

Per ogni record, dopo l'ordinamento crescente per `cod`, il byte stream è una
riga UTF-8 senza BOM nel formato esatto:

```text
{"cod":"<cod>","nome":"<nome>","criticita":<criticita>}\n
```

Regole vincolanti:

1. le chiavi appaiono esattamente nell'ordine `cod`, `nome`, `criticita`;
2. JSON compatto: nessuno spazio aggiunto;
3. i caratteri non ASCII restano caratteri UTF-8, non escape `\u`;
4. virgolette inverse, barra rovesciata e caratteri di controllo usano gli
   escape JSON standard; `/` non viene trasformato in `\/`;
5. ogni record termina con `LF` (`0A`), incluso l'ultimo;
6. il digest è SHA-256 minuscolo del byte stream completo.

Il vettore contiene accenti, virgolette, barra rovesciata, newline, slash e
criticità 1 e 5. Il digest atteso è
`53f27d16f82cdf36bbdb1bd28b61bc6cf7f7057d5cc135a66c2bd9105cc27b83`.

## 5. Conteggi attesi del dataset corrente

Conteggi già verificati nel Progetto 1:

- `cittadino`: 3.200;
- `ospedale`: 30;
- `patologia`: 200;
- `ricovero`: 12.000;
- `patologia_ricovero`: 20.492;
- `progressivo_ricovero`: 30.

Per i sottoinsiemi:

- croniche soltanto: 100;
- mortali soltanto: 38;
- croniche e mortali: 43;
- nessuna specializzazione: 19.

Ne derivano:

- `patologia_cronica`: 143;
- `patologia_mortale`: 81.

I conteggi devono essere letti dal manifest e non cablati nel codice. Questi
valori sono criteri di controllo del dataset corrente.

## 6. Errori di contratto

Formato minimo:

```json
{
  "apiVersion": "1.0",
  "error": {
    "code": "INVALID_BATCH",
    "message": "Il lotto non rispetta il contratto."
  }
}
```

Il messaggio è sintetico. I dettagli diagnostici sicuri possono essere
registrati localmente con `migrationId`, entità e sequenza.
