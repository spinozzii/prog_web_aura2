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

Da T07 ogni export richiede anche il `datasetId` a 64 cifre esadecimali
ricevuto dal manifest. Un cursore è valido soltanto per quella precisa
identità del dataset. La prima pagina di ogni entità ricontrolla la sorgente:
se conteggi o digest sono cambiati, l'export risponde con un errore definitivo
prima di restituire righe della nuova entità.

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

La sequenza vuota produce esattamente zero byte; il relativo SHA-256 è
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

Il vettore contiene accenti, virgolette, barra rovesciata, newline, slash e
criticità 1 e 5. Il digest atteso è
`53f27d16f82cdf36bbdb1bd28b61bc6cf7f7057d5cc135a66c2bd9105cc27b83`.

### 4.2 Contratto HTTP eseguibile T02.2

Per la prima verticale il dataset contiene soltanto `patologia`;
`datasetId` coincide con il digest canonico completo dell'entità. Manifest,
pagine e richieste di importazione usano `apiVersion` `1.0`, JSON UTF-8 e
campi esatti.

Il manifest remoto ha questa forma:

```json
{
  "apiVersion": "1.0",
  "datasetId": "<sha256>",
  "generatedAt": "<timestamp UTC>",
  "entityOrder": ["patologia"],
  "entities": [
    {"entity": "patologia", "rowCount": 2, "digest": "<sha256>"}
  ],
  "maxBatchSize": 100
}
```

Una pagina di export contiene esattamente:

```json
{
  "apiVersion": "1.0",
  "datasetId": "<sha256>",
  "entity": "patologia",
  "cursor": null,
  "nextCursor": "<opaco-o-null>",
  "hasMore": true,
  "rowCount": 1,
  "rows": [{"cod": "P001", "nome": "Esempio", "criticita": 1}],
  "digest": "<sha256-del-lotto>"
}
```

Il cursore ricevuto viene ripetuto in `cursor`; `nextCursor` è non nullo
soltanto se `hasMore` è vero. Ogni pagina è ordinata strettamente per `cod`,
non supera il limite richiesto e il suo digest usa le regole della sezione
4.1.

Il lotto inviato a Django contiene esattamente:

```json
{
  "apiVersion": "1.0",
  "datasetId": "<sha256>",
  "entity": "patologia",
  "batchSequence": 0,
  "rowCount": 1,
  "rows": [{"cod": "P001", "nome": "Esempio", "criticita": 1}],
  "digest": "<sha256-del-lotto>",
  "expectedRowCount": 2,
  "expectedDigest": "<sha256-completo>"
}
```

`batchSequence` parte da zero ed è contiguo. `isLast` non fa parte del
contratto: la completezza viene decisa soltanto dalla finalizzazione:

```json
{
  "apiVersion": "1.0",
  "datasetId": "<sha256>",
  "entity": "patologia",
  "expectedRowCount": 2,
  "expectedBatchCount": 2,
  "expectedDigest": "<sha256-completo>"
}
```

Per la sequenza vuota il manifest dichiara zero righe e il digest della
sezione 4.1; l'export restituisce una pagina terminale vuota, Java non invia
alcun lotto e finalizza con `expectedRowCount` e `expectedBatchCount` entrambi
zero.

Le API dati richiedono un Bearer proveniente dall'ambiente. Il servizio PHP
firma il cursore con HMAC e lo lega a entità, dataset e scadenza; Java tratta
il cursore come opaco. Il servizio Django registra run e lotto nella stessa
transazione dei dati. Un lotto già registrato con stesso digest e conteggio è
idempotente; uno con identità uguale e contenuto diverso è un conflitto.

### 4.3 Estensione eseguibile T03

`shared/entity-schema.json` è la whitelist condivisa per tutte le otto
entità. Dichiara ordine, tabella sorgente, campi ordinati, tipi, limiti, chiavi,
FK, vincoli univoci e predecessore. PHP, Java e Django caricano o rispecchiano
questa definizione e rifiutano entità o campi estranei.

`tests/fixtures/t03-dataset.json` contiene un dataset relazionale controllato,
il byte stream canonico e il digest atteso di ogni entità. La
canonicalizzazione conserva le regole della sezione 4.1, ma usa i campi
nell'ordine dichiarato nello schema e ordina per l'intera chiave:

- le stringhe restano stringhe JSON UTF-8 non vuote;
- gli interi restano numeri JSON senza parte frazionaria;
- le date civili sono stringhe `YYYY-MM-DD` valide nel calendario gregoriano;
- i decimali sono stringhe non negative con esattamente due cifre dopo il
  punto, per evitare conversioni binarie o perdita degli zeri finali;
- le tuple di chiave composta sono confrontate elemento per elemento, usando
  ordine binario UTF-8 per le stringhe e ordine numerico per gli interi.

Il `datasetId` non coincide più con il digest di una singola entità. Si calcola
in ordine di dipendenza applicando SHA-256 alla concatenazione UTF-8 delle
seguenti righe JSON compatte, ciascuna terminata da `LF`:

```text
{"entity":"<nome>","rowCount":<conteggio>,"digest":"<digest-entita>"}\n
```

L'ordine vincolante è:

1. `cittadino`;
2. `patologia`;
3. `patologia_cronica`;
4. `patologia_mortale`;
5. `ospedale`;
6. `ricovero`;
7. `patologia_ricovero`;
8. `progressivo_ricovero`.

Il manifest T03 espone tutte le otto voci in questo ordine. L'endpoint di ogni
pagina è `GET /api/v1/export/<entita>` e mantiene la forma della sezione 4.2;
il cursore HMAC include entità, `datasetId`, tupla completa dell'ultima chiave
ed espirazione. Il confronto keyset sottostante usa la stessa tupla completa.

Java trasferisce e finalizza un'entità alla volta nell'ordine del manifest.
`batchSequence` riparte da zero per ogni entità; `datasetId` identifica il
dataset globale, mentre `expectedDigest` e `expectedRowCount` identificano
l'entità corrente. Django registra quindi l'identità del run insieme
all'entità. Una finalizzazione riuscita verifica conteggio, digest, vincoli,
predecessore completato e, per l'ultima entità:

- almeno una riga `patologia_ricovero` per ogni `ricovero`;
- un `progressivo_ricovero` per ogni ospedale;
- `prossimo_cod = MAX(ricovero.cod dello stesso ospedale) + 1`.

### 4.4 Checkpoint e ripresa T07

Il registro globale Django viene inizializzato con:

```text
POST /api/v1/migrations/{migrationId}
```

Il corpo contiene esattamente `apiVersion`, `datasetId`, `entityOrder` ed
`entities`; ogni descrittore di entità contiene nome, conteggio e digest del
manifest. Una nuova esecuzione restituisce HTTP 201 e `idempotent: false`; la
stessa inizializzazione, con identità invariata, restituisce HTTP 200 e
`idempotent: true`. Un `migrationId` già legato a un dataset diverso produce
conflitto.

Ogni richiesta di lotto T07 aggiunge i campi obbligatori:

- `sourceCursor`: cursore usato per leggere la pagina, `null` soltanto per la
  prima;
- `nextCursor`: cursore opaco della pagina seguente oppure `null`;
- `hasMore`: vero se e soltanto se `nextCursor` non è nullo.

Django registra questi valori nella stessa transazione del lotto. La risposta
restituisce il checkpoint autorevole; in caso di ripetizione identica prevale
quello già persistito, anche se un cursore HMAC rigenerato contiene una diversa
scadenza.

Lo stato globale:

```text
GET /api/v1/migrations/{migrationId}
```

include `status`, `currentEntity`, `lastError`, `recoverable` e gli otto
checkpoint. Ogni checkpoint espone `entity`, `status`, `expectedRowCount`,
`expectedDigest`, `rowsImported`, `nextBatchSequence`, `lastBatchSequence`,
`sourceCursor`, `nextCursor`, `hasMore`, `lastKey` e `lastError`.

Gli stati globali sono `created`, `running`, `interrupted`, `failed` e
`completed`. La servlet rilegge questo stato a ogni avvio o rilancio e riparte
da `nextBatchSequence` e `nextCursor`. Django rifiuta la finalizzazione se
`hasMore` è ancora vero o il conteggio non è completo.

Quando l'orchestratore interrompe il lavoro segnala al servizio locale:

```text
POST /api/v1/migrations/{migrationId}/failure
```

con `apiVersion`, `datasetId`, `entity`, `errorCode` e `recoverable`. Errori di
trasporto o HTTP temporanei possono lasciare lo stato `interrupted`; dataset,
schema, digest o lotto discordante producono invece uno stato `failed`
definitivo.

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
