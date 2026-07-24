# Servizio Django locale

## T01: endpoint disponibile

Lo scheletro usa Django 5.2.16 su Python 3.12, fissato in
`requirements.txt`, e non definisce ancora modelli, database o API di
importazione. `GET /health` restituisce:

```json
{"apiVersion":"1.0","service":"local-django","status":"ok"}
```

La risposta usa `application/json; charset=utf-8`. In un ambiente Python 3.12
con dipendenze installate, il test è:

```text
python manage.py test health_service
```

Il valore `DJANGO_SECRET_KEY` può essere fornito dall'ambiente; il fallback è
soltanto un segnaposto di sviluppo e non è una credenziale.

PostgreSQL, autenticazione e importazione restano fuori dallo scope T01.
