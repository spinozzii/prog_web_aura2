# Servizio PHP remoto

## Responsabilità

- espone salute, manifest ed export a lotti;
- legge MySQL/MariaDB tramite PDO;
- resta compatibile con Altervista;
- non modifica i dati;
- autentica le richieste;
- applica whitelist e query preparate.

## T01: endpoint disponibile

Il front controller è `public/index.php`. La directory `public/health` e la
regola `public/.htaccess` fanno raggiungere `GET /health` su Apache compatibile
con Altervista, senza un router di sviluppo. La directory richiama soltanto il
front controller e permette lo stesso percorso con `php -S -t public`.

```json
{"apiVersion":"1.0","service":"remote-php","status":"ok"}
```

Non richiede Composer né configurazione di database. Il test unitario richiede
PHP CLI:

```text
php tests/HealthResponseTest.php
```

Il runner condiviso avvia anche un server PHP temporaneo senza opzione
`router` e verifica via HTTP `GET /health`, incluso il Content-Type.

Manifest, export, autenticazione e accesso PDO restano fuori dallo scope T01.
