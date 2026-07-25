# Dump sorgente massivo

`drive-aura-51-source-v2.zip` è il pacchetto consegnabile del dataset
`drive-aura-51-massivo-v2`. Contiene soltanto:

- `schema.sql`;
- `seed_massivo.sql`;
- `source-dump-manifest.json`;
- questa guida, con nome `README_RESTORE.md`.

Il pacchetto non contiene credenziali, configurazioni di connessione o
artefatti dei runtime. Il seed contiene dati sanitari sintetici: va comunque
trattato come dataset applicativo e non deve essere stampato nei log.

## Verifica

Da PowerShell, nella radice del Progetto 2:

```powershell
$actual = (Get-FileHash -Algorithm SHA256 `
    -LiteralPath 'database\drive-aura-51-source-v2.zip').Hash.ToLowerInvariant()
$expected = (Get-Content -Raw `
    -LiteralPath 'database\drive-aura-51-source-v2.zip.sha256').Split()[0]
if ($actual -ne $expected) { throw 'Checksum del pacchetto non valido.' }
```

Estrarre quindi lo ZIP in una cartella vuota e verificare i due file SQL
contro `source-dump-manifest.json`. Gli SHA-256 attesi sono:

- `schema.sql`:
  `f1f162683f987a3f7fae98eba8ef830b03418baf57fe60026c406ca1797d2ada`;
- `seed_massivo.sql`:
  `0d90404c2cc754d1df5078c04b15a39c941f4070d0ba6f2664f54c3c78bc3972`.

Il pacchetto è rigenerabile, senza duplicare stabilmente i file sorgente, con:

```powershell
.\scripts\build-source-dump.ps1 `
    -Project1Root 'C:\percorso\drive-aura-51-servizio-sanitario'
```

Lo script rifiuta sorgenti con checksum o conteggi diversi dal manifest.

## Ripristino MariaDB/MySQL

1. Verificare il checksum ed estrarre il pacchetto.
2. Creare un database vuoto con charset `utf8mb4`.
3. Importare prima `schema.sql`, poi `seed_massivo.sql`. Per esempio:

```powershell
mariadb --host=127.0.0.1 --port=3306 --user=OPERATORE `
    --database=DATABASE_VUOTO `
    --execute="source C:/percorso/estratto/schema.sql"
mariadb --host=127.0.0.1 --port=3306 --user=OPERATORE `
    --database=DATABASE_VUOTO `
    --execute="source C:/percorso/estratto/seed_massivo.sql"
```

Non inserire password nella riga di comando: usare il prompt del client o una
configurazione locale non versionata. Il seed elimina e reinserisce tutte le
righe in una singola transazione; non eseguire CRUD concorrenti durante
l'importazione.

## Conteggi attesi

| Entità | Righe |
|---|---:|
| `cittadino` | 3.200 |
| `patologia` | 200 |
| `patologia_cronica` | 143 |
| `patologia_mortale` | 81 |
| `ospedale` | 30 |
| `ricovero` | 12.000 |
| `patologia_ricovero` | 20.492 |
| `progressivo_ricovero` | 30 |
| **Totale** | **36.176** |

Dopo il ripristino verificare inoltre:

- assenza di duplicati sulle PK semplici e composte;
- assenza di riferimenti orfani per tutte le FK;
- unicità di `ospedale.direttore_sanitario_cssn`;
- presenza di almeno una patologia per ogni ricovero;
- `progressivo_ricovero.prossimo_cod = MAX(ricovero.cod) + 1` per ospedale.
