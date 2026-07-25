\pset tuples_only on
\pset format unaligned
\set ON_ERROR_STOP on

SELECT 'cittadino_count|' || COUNT(*) FROM cittadino;
SELECT 'patologia_count|' || COUNT(*) FROM patologia;
SELECT 'patologia_cronica_count|' || COUNT(*) FROM patologia_cronica;
SELECT 'patologia_mortale_count|' || COUNT(*) FROM patologia_mortale;
SELECT 'ospedale_count|' || COUNT(*) FROM ospedale;
SELECT 'ricovero_count|' || COUNT(*) FROM ricovero;
SELECT 'patologia_ricovero_count|' || COUNT(*) FROM patologia_ricovero;
SELECT 'progressivo_ricovero_count|' || COUNT(*) FROM progressivo_ricovero;

SELECT 'ricovero_pk_duplicates|' || COUNT(*)
FROM (
    SELECT cod_ospedale, cod
    FROM ricovero
    GROUP BY cod_ospedale, cod
    HAVING COUNT(*) > 1
) AS duplicates;

SELECT 'patologia_ricovero_pk_duplicates|' || COUNT(*)
FROM (
    SELECT cod_ospedale, cod_ricovero, cod_patologia
    FROM patologia_ricovero
    GROUP BY cod_ospedale, cod_ricovero, cod_patologia
    HAVING COUNT(*) > 1
) AS duplicates;

SELECT 'orphan_ospedale_direttore|' || COUNT(*)
FROM ospedale AS o
LEFT JOIN cittadino AS c ON c.cssn = o.direttore_sanitario_cssn
WHERE c.cssn IS NULL;

SELECT 'duplicate_ospedale_direttore|' || COUNT(*)
FROM (
    SELECT direttore_sanitario_cssn
    FROM ospedale
    GROUP BY direttore_sanitario_cssn
    HAVING COUNT(*) > 1
) AS duplicates;

SELECT 'orphan_patologia_cronica|' || COUNT(*)
FROM patologia_cronica AS pc
LEFT JOIN patologia AS p ON p.cod = pc.cod_patologia
WHERE p.cod IS NULL;

SELECT 'orphan_patologia_mortale|' || COUNT(*)
FROM patologia_mortale AS pm
LEFT JOIN patologia AS p ON p.cod = pm.cod_patologia
WHERE p.cod IS NULL;

SELECT 'orphan_ricovero_ospedale|' || COUNT(*)
FROM ricovero AS r
LEFT JOIN ospedale AS o ON o.codice = r.cod_ospedale
WHERE o.codice IS NULL;

SELECT 'orphan_ricovero_cittadino|' || COUNT(*)
FROM ricovero AS r
LEFT JOIN cittadino AS c ON c.cssn = r.paziente_cssn
WHERE c.cssn IS NULL;

SELECT 'orphan_patologia_ricovero_ricovero|' || COUNT(*)
FROM patologia_ricovero AS pr
LEFT JOIN ricovero AS r
  ON r.cod_ospedale = pr.cod_ospedale
 AND r.cod = pr.cod_ricovero
WHERE r.cod_ospedale IS NULL;

SELECT 'orphan_patologia_ricovero_patologia|' || COUNT(*)
FROM patologia_ricovero AS pr
LEFT JOIN patologia AS p ON p.cod = pr.cod_patologia
WHERE p.cod IS NULL;

SELECT 'orphan_progressivo_ospedale|' || COUNT(*)
FROM progressivo_ricovero AS progressivo
LEFT JOIN ospedale AS o ON o.codice = progressivo.cod_ospedale
WHERE o.codice IS NULL;

SELECT 'invalid_patologia_criticita|' || COUNT(*)
FROM patologia
WHERE criticita NOT BETWEEN 1 AND 5;

SELECT 'invalid_ricovero_domain|' || COUNT(*)
FROM ricovero
WHERE cod < 1 OR durata NOT BETWEEN 1 AND 3650 OR costo < 0;

SELECT 'ricovero_without_patologia|' || COUNT(*)
FROM ricovero AS r
WHERE NOT EXISTS (
    SELECT 1
    FROM patologia_ricovero AS pr
    WHERE pr.cod_ospedale = r.cod_ospedale
      AND pr.cod_ricovero = r.cod
);

SELECT 'invalid_progressivo|' || COUNT(*)
FROM progressivo_ricovero AS progressivo
LEFT JOIN (
    SELECT cod_ospedale, MAX(cod) + 1 AS expected_next
    FROM ricovero
    GROUP BY cod_ospedale
) AS expected ON expected.cod_ospedale = progressivo.cod_ospedale
WHERE progressivo.prossimo_cod <> expected.expected_next
   OR expected.expected_next IS NULL;

SELECT 'migration_status|' || status
FROM migration_execution
WHERE migration_id = :'migration_id';

SELECT 'migration_entity_runs|' || COUNT(*)
FROM entity_migration_run
WHERE migration_id = :'migration_id';

SELECT 'migration_batches|' || COUNT(*)
FROM entity_migration_batch AS batch
INNER JOIN entity_migration_run AS run ON run.id = batch.run_id
WHERE run.migration_id = :'migration_id';

SELECT (
    (SELECT COUNT(*) = 3200 FROM cittadino)
    AND (SELECT COUNT(*) = 200 FROM patologia)
    AND (SELECT COUNT(*) = 143 FROM patologia_cronica)
    AND (SELECT COUNT(*) = 81 FROM patologia_mortale)
    AND (SELECT COUNT(*) = 30 FROM ospedale)
    AND (SELECT COUNT(*) = 12000 FROM ricovero)
    AND (SELECT COUNT(*) = 20492 FROM patologia_ricovero)
    AND (SELECT COUNT(*) = 30 FROM progressivo_ricovero)
    AND NOT EXISTS (
        SELECT 1
        FROM (
            SELECT cod_ospedale, cod
            FROM ricovero
            GROUP BY cod_ospedale, cod
            HAVING COUNT(*) > 1
        ) AS duplicates
    )
    AND NOT EXISTS (
        SELECT 1
        FROM (
            SELECT cod_ospedale, cod_ricovero, cod_patologia
            FROM patologia_ricovero
            GROUP BY cod_ospedale, cod_ricovero, cod_patologia
            HAVING COUNT(*) > 1
        ) AS duplicates
    )
    AND NOT EXISTS (
        SELECT 1
        FROM ospedale AS o
        LEFT JOIN cittadino AS c ON c.cssn = o.direttore_sanitario_cssn
        WHERE c.cssn IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM (
            SELECT direttore_sanitario_cssn
            FROM ospedale
            GROUP BY direttore_sanitario_cssn
            HAVING COUNT(*) > 1
        ) AS duplicates
    )
    AND NOT EXISTS (
        SELECT 1
        FROM patologia_cronica AS pc
        LEFT JOIN patologia AS p ON p.cod = pc.cod_patologia
        WHERE p.cod IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM patologia_mortale AS pm
        LEFT JOIN patologia AS p ON p.cod = pm.cod_patologia
        WHERE p.cod IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM ricovero AS r
        LEFT JOIN ospedale AS o ON o.codice = r.cod_ospedale
        WHERE o.codice IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM ricovero AS r
        LEFT JOIN cittadino AS c ON c.cssn = r.paziente_cssn
        WHERE c.cssn IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM patologia_ricovero AS pr
        LEFT JOIN ricovero AS r
          ON r.cod_ospedale = pr.cod_ospedale
         AND r.cod = pr.cod_ricovero
        WHERE r.cod_ospedale IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM patologia_ricovero AS pr
        LEFT JOIN patologia AS p ON p.cod = pr.cod_patologia
        WHERE p.cod IS NULL
    )
    AND NOT EXISTS (
        SELECT 1
        FROM progressivo_ricovero AS progressivo
        LEFT JOIN ospedale AS o ON o.codice = progressivo.cod_ospedale
        WHERE o.codice IS NULL
    )
    AND NOT EXISTS (
        SELECT 1 FROM patologia WHERE criticita NOT BETWEEN 1 AND 5
    )
    AND NOT EXISTS (
        SELECT 1
        FROM ricovero
        WHERE cod < 1 OR durata NOT BETWEEN 1 AND 3650 OR costo < 0
    )
    AND NOT EXISTS (
        SELECT 1
        FROM ricovero AS r
        WHERE NOT EXISTS (
            SELECT 1
            FROM patologia_ricovero AS pr
            WHERE pr.cod_ospedale = r.cod_ospedale
              AND pr.cod_ricovero = r.cod
        )
    )
    AND NOT EXISTS (
        SELECT 1
        FROM progressivo_ricovero AS progressivo
        LEFT JOIN (
            SELECT cod_ospedale, MAX(cod) + 1 AS expected_next
            FROM ricovero
            GROUP BY cod_ospedale
        ) AS expected ON expected.cod_ospedale = progressivo.cod_ospedale
        WHERE progressivo.prossimo_cod <> expected.expected_next
           OR expected.expected_next IS NULL
    )
    AND COALESCE((
        SELECT status = 'completed'
        FROM migration_execution
        WHERE migration_id = :'migration_id'
    ), FALSE)
    AND (
        SELECT COUNT(*) = 8
           AND COUNT(*) FILTER (WHERE status = 'completed') = 8
        FROM entity_migration_run
        WHERE migration_id = :'migration_id'
    )
    AND (
        SELECT COUNT(*) = 364
        FROM entity_migration_batch AS batch
        INNER JOIN entity_migration_run AS run ON run.id = batch.run_id
        WHERE run.migration_id = :'migration_id'
    )
) AS t07_valid
\gset

\if :t07_valid
\echo 'PASS: vincoli e stato PostgreSQL T07 validi.'
\else
\echo 'FAIL: conteggi, vincoli o stato PostgreSQL T07 non validi.'
DO $$
BEGIN
    RAISE EXCEPTION 'Verifica PostgreSQL T07 fallita.';
END
$$;
\endif
