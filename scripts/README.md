# Configurazione e verifica

Questa cartella conterrà gli strumenti da riga di comando per:

- rilevare prerequisiti e versioni;
- configurare l'ambiente locale;
- installare dipendenze Python offline;
- preparare PostgreSQL;
- selezionare e distribuire il WAR corretto;
- avviare, verificare e arrestare i servizi;
- misurare la procedura completa.

I comandi definitivi devono essere indipendenti da un IDE e provati da una
copia pulita. Non aggiungere comandi fittizi al manuale.

T02.2 aggiunge `verify-patologia-migration.ps1`: controlla i tre endpoint di
salute e accetta la verticale soltanto dopo la finalizzazione verificata di
`patologia`. Il comando usa URL espliciti e legge `BRIDGE_API_SECRET`
dall'ambiente; non installa runtime e non contiene credenziali.
