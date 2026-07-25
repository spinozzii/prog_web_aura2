# Esempio senza valori reali. Usare almeno 12 caratteri per ogni segreto.
$env:POSTGRES_PASSWORD = '<password-postgresql>'
$env:DJANGO_SECRET_KEY = '<stringa-casuale-almeno-32-caratteri>'
$env:LOCAL_API_SECRET = '<segreto-locale-almeno-12-caratteri>'
$env:REMOTE_API_SECRET = '<segreto-remoto-almeno-12-caratteri>'
$env:BRIDGE_API_SECRET = '<segreto-bridge-almeno-12-caratteri>'
