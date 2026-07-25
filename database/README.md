# Database e dump

Questa cartella contiene:

- schema PostgreSQL o migrazioni SQL esplicite;
- query di verifica;
- dump del database MySQL/MariaDB di origine;
- istruzioni di ripristino usate nella prova.

Non salvare credenziali. Il dump definitivo deve essere confrontato con il
manifest remoto e con i conteggi del Progetto 1.

`t03-fixture-mariadb.sql` crea soltanto il piccolo dataset relazionale
controllato usato dalla prova T03. È ripetibile, non contiene credenziali e
preserva FK, chiavi composte, direttore sanitario univoco, domini e
progressivi.

`drive-aura-51-source-v2.zip` è il dump massivo verificabile usato dalla prova
T07. `README_SOURCE_DUMP.md` documenta checksum, rigenerazione senza copie SQL
permanenti, ripristino e controlli successivi.

Lo schema PostgreSQL consegnato è gestito dalle migrazioni Django in
`local-django/health_service/migrations`.
