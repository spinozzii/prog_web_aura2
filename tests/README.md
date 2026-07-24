# Test condivisi

Questa cartella conterrà fixture e vettori di contratto condivisi tra PHP,
Java e Python:

- salute;
- manifest;
- pagine di export;
- lotti di import;
- errori;
- canonicalizzazione e digest.

Ogni linguaggio deve verificare gli stessi input e gli stessi digest attesi.
I test specifici dei componenti possono restare accanto al relativo codice.

`patologia-canonical.json`, `patologia-empty.json` e
`patologia-line-separators.json` sono i vettori condivisi eseguibili. Il
runner rigoroso:

```powershell
.\tests\run-health-contracts.ps1
```

esegue salute, canonicalizzazione, API PHP, orchestratore Java e importazione
Django. `-AllowPartial` serve soltanto a rendere espliciti gli skip dei runtime
non disponibili; non trasforma una suite parziale in un esito completo.
