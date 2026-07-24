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
non è il dump del Progetto 1, che resta fuori scope fino a T08. Lo script
preserva FK, chiavi composte, direttore sanitario univoco, domini e
progressivi; deve essere caricato in un database di prova già selezionato.

Lo schema PostgreSQL consegnato è gestito dalle migrazioni Django in
`local-django/health_service/migrations`.
