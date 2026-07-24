package it.unibg.driveaura.bridge.core;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

/** Dependency-free tests for all-entity orchestration and hostile responses. */
public final class MigrationOrchestratorTest {
    private static final String MIGRATION_ID = "11111111-1111-1111-1111-111111111111";
    private static final String REMOTE = "https://remote.test";
    private static final String LOCAL = "http://127.0.0.1:8765";
    private static final String EMPTY_DIGEST =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    private MigrationOrchestratorTest() {
    }

    public static void main(String[] args) {
        if (args.length == 2) {
            System.setProperty("driveaura.entitySchema", args[0]);
            System.setProperty("driveaura.t03Fixture", args[1]);
        } else if (args.length != 0) {
            throw new IllegalArgumentException(
                    "Uso: MigrationOrchestratorTest [entity-schema.json t03-dataset.json]");
        }
        jsonIntegersRemainIntegers();
        sharedSchemaAndValidators();
        sharedFixtureDigests();
        compositeTupleOrdering();
        allEntitiesSuccess(false);
        allEntitiesSuccess(true);
        wrongManifestOrderIsRejected();
        badPageDigestIsRejected();
        badPageCountIsRejected();
        badPageOrderIsRejected();
        malformedCursorIsRejected();
        misleadingContentTypeIsRejected();
        timeoutIsClassified();
        endpointRejectsWrongSecret();
        endpointRejectsNullMigrationId();
        System.out.println("Orchestrazione completa Java valida.");
    }

    private static void jsonIntegersRemainIntegers() {
        Object value = Json.parse("1");
        check(value instanceof Long && ((Long) value).longValue() == 1L, "Json deve produrre Long.");
        expectIllegal(new Action() {
            @Override
            public void run() {
                Json.parse("01");
            }
        });
    }

    private static void sharedSchemaAndValidators() {
        check(EntitySchemas.ordered().size() == 8, "Schema condiviso incompleto.");
        check(EntitySchemas.names().equals(Arrays.asList(
                "cittadino", "patologia", "patologia_cronica", "patologia_mortale",
                "ospedale", "ricovero", "patologia_ricovero", "progressivo_ricovero")),
                "Ordine schema non valido.");
        final EntitySchema ricovero = EntitySchemas.require("ricovero");
        EntityCanonicalizer.validate(ricovero, ricovero("H1", 1, "2024-02-29", "10.00"));
        expectIllegal(new Action() {
            @Override
            public void run() {
                EntityCanonicalizer.validate(ricovero, ricovero("H1", 1, "2025-02-29", "10.00"));
            }
        });
        expectIllegal(new Action() {
            @Override
            public void run() {
                EntityCanonicalizer.validate(ricovero, ricovero("H1", 1, "2024-02-29", "10.0"));
            }
        });
        expectIllegal(new Action() {
            @Override
            public void run() {
                EntityCanonicalizer.validate(ricovero, ricovero("H1", 1, "2024-02-29", "-1.00"));
            }
        });
        final Map<String, Object> numericCost = ricovero("H1", 1, "2024-02-29", "10.00");
        numericCost.put("costo", new java.math.BigDecimal("10.00"));
        expectIllegal(new Action() {
            @Override
            public void run() {
                EntityCanonicalizer.validate(ricovero, numericCost);
            }
        });
        final Map<String, Object> surrogate = patologia("P1", "malata \ud800", 1);
        expectIllegal(new Action() {
            @Override
            public void run() {
                EntityCanonicalizer.validate(EntitySchemas.require("patologia"), surrogate);
            }
        });
    }

    @SuppressWarnings("unchecked")
    private static void sharedFixtureDigests() {
        Map<String, Object> fixture = (Map<String, Object>) Json.parse(readFixture());
        Map<String, Object> rowsByEntity = (Map<String, Object>) fixture.get("rowsByEntity");
        Map<String, Object> expectedByEntity = (Map<String, Object>) fixture.get("expectedByEntity");
        ArrayList<DatasetIdentity.Descriptor> descriptors =
                new ArrayList<DatasetIdentity.Descriptor>();
        for (EntitySchema schema : EntitySchemas.ordered()) {
            List<Object> rawRows = (List<Object>) rowsByEntity.get(schema.name);
            List<EntityCanonicalizer.Row> rows =
                    EntityCanonicalizer.validateAll(schema, rawRows);
            Map<String, Object> expected =
                    (Map<String, Object>) expectedByEntity.get(schema.name);
            String canonical = new String(
                    EntityCanonicalizer.canonicalBytes(schema, rows), StandardCharsets.UTF_8);
            check(canonical.equals(expected.get("expectedCanonical")),
                    "Byte canonici fixture non validi per " + schema.name + ".");
            String digest = EntityCanonicalizer.sha256(schema, rows);
            check(digest.equals(expected.get("expectedSha256")),
                    "Digest fixture non valido per " + schema.name + ".");
            descriptors.add(new DatasetIdentity.Descriptor(
                    schema.name, rawRows.size(), digest));
        }
        check(DatasetIdentity.sha256(descriptors).equals(fixture.get("expectedDatasetId")),
                "DatasetId condiviso non valido.");
    }

    private static void compositeTupleOrdering() {
        EntitySchema ricovero = EntitySchemas.require("ricovero");
        EntityCanonicalizer.Row first =
                EntityCanonicalizer.validate(ricovero, ricovero("H1", 2, "2024-01-01", "10.00"));
        EntityCanonicalizer.Row second =
                EntityCanonicalizer.validate(ricovero, ricovero("H2", 1, "2024-01-01", "10.00"));
        check(EntityCanonicalizer.compare(ricovero, first, second) < 0,
                "La PK composta deve confrontare prima l'ospedale.");

        EntitySchema relation = EntitySchemas.require("patologia_ricovero");
        EntityCanonicalizer.Row left = EntityCanonicalizer.validate(
                relation, row("cod_ospedale", "H1", "cod_ricovero", 1L, "cod_patologia", "P2"));
        EntityCanonicalizer.Row right = EntityCanonicalizer.validate(
                relation, row("cod_ospedale", "H1", "cod_ricovero", 2L, "cod_patologia", "P1"));
        check(EntityCanonicalizer.compare(relation, left, right) < 0,
                "La PK composta deve confrontare tutte le componenti.");
    }

    private static void allEntitiesSuccess(boolean idempotent) {
        LinkedHashMap<String, List<Map<String, Object>>> rows = relatedRows();
        Dataset dataset = dataset(rows);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, dataset.manifest);
        int expectedRows = 0;
        int expectedBatches = 0;
        int entityIndex = 0;
        for (EntitySchema schema : EntitySchemas.ordered()) {
            List<Map<String, Object>> entityRows = rows.get(schema.name);
            expectedRows += entityRows.size();
            int sequence = 0;
            String cursor = null;
            if (entityRows.isEmpty()) {
                fake.response("GET", exportUrl(schema.name, null), 200,
                        page(dataset.id, schema, Collections.<Map<String, Object>>emptyList(),
                                null, null, false));
            } else {
                for (int index = 0; index < entityRows.size(); index++) {
                    String next = index + 1 < entityRows.size()
                            ? "c" + entityIndex + "p" + index + ".signature" : null;
                    List<Map<String, Object>> one =
                            Collections.singletonList(entityRows.get(index));
                    final int expectedSequence = sequence;
                    final String expectedEntity = schema.name;
                    fake.response("GET", exportUrl(schema.name, cursor), 200,
                            page(dataset.id, schema, one, cursor, next, next != null));
                    fake.response(
                            "POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/batches",
                            idempotent ? 200 : 201,
                            batchResponse(dataset.id, schema, sequence, one, idempotent),
                            new BodyCheck() {
                                @Override
                                public void verify(Map<String, Object> body) {
                                    check(expectedEntity.equals(body.get("entity")),
                                            "Entita lotto non propagata.");
                                    check(longValue(body, "batchSequence") == expectedSequence,
                                            "Sequenza lotto non azzerata per entita.");
                                }
                            });
                    cursor = next;
                    sequence++;
                }
            }
            expectedBatches += sequence;
            final String finalizingEntity = schema.name;
            final int finalizingRows = entityRows.size();
            final int finalizingBatches = sequence;
            fake.response(
                    "POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/finalize",
                    200, finalizeResponse(dataset.id, schema, entityRows, sequence),
                    new BodyCheck() {
                        @Override
                        public void verify(Map<String, Object> body) {
                            check(finalizingEntity.equals(body.get("entity")),
                                    "Entita finalizzazione non valida.");
                            check(longValue(body, "expectedRowCount") == finalizingRows,
                                    "Conteggio finale non propagato.");
                            check(longValue(body, "expectedBatchCount") == finalizingBatches,
                                    "Numero lotti finale non propagato.");
                        }
                    });
            entityIndex++;
        }

        MigrationOrchestrator.Result result =
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
        check("completed".equals(result.status), "Migrazione completa non completata.");
        check(result.entities.size() == 8, "Risultati entita incompleti.");
        check(result.totalRowCount == expectedRows, "Totale righe aggregato non valido.");
        check(result.totalBatchCount == expectedBatches, "Totale lotti aggregato non valido.");
        Map<String, Object> json = result.toJsonObject();
        exactKeys(json, "apiVersion", "migrationId", "datasetId", "status", "entityOrder",
                "entities", "totalRowCount", "totalBatchCount", "verification");
        check(EntitySchemas.names().equals(json.get("entityOrder")), "Ordine risultato non valido.");
        fake.assertDone();
    }

    private static void wrongManifestOrderIsRejected() {
        Dataset dataset = dataset(relatedRows());
        @SuppressWarnings("unchecked")
        List<Object> order = (List<Object>) dataset.manifest.get("entityOrder");
        Collections.swap(order, 0, 1);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, dataset.manifest);
        expectMigration("REMOTE_CONTRACT_ERROR", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void badPageDigestIsRejected() {
        singleCittadinoFailure(new PageMutation() {
            @Override
            public void mutate(Map<String, Object> page) {
                page.put("digest", EMPTY_DIGEST);
            }
        });
    }

    private static void badPageCountIsRejected() {
        singleCittadinoFailure(new PageMutation() {
            @Override
            public void mutate(Map<String, Object> page) {
                page.put("rowCount", 0L);
            }
        });
    }

    private static void badPageOrderIsRejected() {
        LinkedHashMap<String, List<Map<String, Object>>> rows = emptyRows();
        rows.put("cittadino", Arrays.asList(cittadino("B"), cittadino("A")));
        Dataset dataset = dataset(rows);
        EntitySchema schema = EntitySchemas.require("cittadino");
        Map<String, Object> invalidPage =
                page(dataset.id, schema, rows.get("cittadino"), null, null, false);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, dataset.manifest);
        fake.response("GET", exportUrl("cittadino", null), 200, invalidPage);
        expectMigration("REMOTE_CONTRACT_ERROR", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void singleCittadinoFailure(PageMutation mutation) {
        LinkedHashMap<String, List<Map<String, Object>>> rows = emptyRows();
        rows.put("cittadino", Collections.singletonList(cittadino("A")));
        Dataset dataset = dataset(rows);
        EntitySchema schema = EntitySchemas.require("cittadino");
        Map<String, Object> invalidPage =
                page(dataset.id, schema, rows.get("cittadino"), null, null, false);
        mutation.mutate(invalidPage);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, dataset.manifest);
        fake.response("GET", exportUrl("cittadino", null), 200, invalidPage);
        expectMigration("REMOTE_CONTRACT_ERROR", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void malformedCursorIsRejected() {
        LinkedHashMap<String, List<Map<String, Object>>> rows = emptyRows();
        rows.put("cittadino", Collections.singletonList(cittadino("A")));
        Dataset dataset = dataset(rows);
        EntitySchema schema = EntitySchemas.require("cittadino");
        Map<String, Object> invalidPage =
                page(dataset.id, schema, rows.get("cittadino"), null, "not a cursor", true);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, dataset.manifest);
        fake.response("GET", exportUrl("cittadino", null), 200, invalidPage);
        expectMigration("REMOTE_CONTRACT_ERROR", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void misleadingContentTypeIsRejected() {
        Dataset dataset = dataset(relatedRows());
        FakeTransport fake = new FakeTransport();
        fake.responseWithContentType(
                "GET", REMOTE + "/api/v1/manifest", 200,
                dataset.manifest, "application/jsonp; charset=utf-8");
        expectMigration("REMOTE_CONTRACT_ERROR", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void timeoutIsClassified() {
        FakeTransport fake = new FakeTransport();
        fake.failure("GET", REMOTE + "/api/v1/manifest",
                new MigrationException("HTTP_TIMEOUT", 504, "test timeout"));
        expectMigration("REMOTE_TIMEOUT", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void endpointRejectsWrongSecret() {
        FakeTransport fake = new FakeTransport();
        MigrationEndpoint.Response response =
                new MigrationEndpoint(config(), fake).start("Bearer wrong", "{}");
        check(response.status == 401, "Segreto bridge errato non rifiutato.");
        check(!response.body.contains("bridge-test-secret"), "Segreto esposto nell'errore.");
        fake.assertDone();
    }

    private static void endpointRejectsNullMigrationId() {
        FakeTransport fake = new FakeTransport();
        MigrationEndpoint.Response response = new MigrationEndpoint(config(), fake)
                .start("Bearer bridge-test-secret", "{\"migrationId\":null}");
        check(response.status == 400, "migrationId nullo non rifiutato.");
        fake.assertDone();
    }

    private static MigrationConfig config() {
        return new MigrationConfig(
                REMOTE, LOCAL, "remote-test-secret", "local-test-secret", "bridge-test-secret",
                1, 1000, 1000);
    }

    private static LinkedHashMap<String, List<Map<String, Object>>> relatedRows() {
        LinkedHashMap<String, List<Map<String, Object>>> rows = emptyRows();
        rows.put("cittadino", Arrays.asList(cittadino("CSSN1"), cittadino("CSSN2")));
        rows.put("patologia", Collections.singletonList(patologia("P1", "Cardiopatia", 5)));
        rows.put("patologia_cronica",
                Collections.singletonList(row("cod_patologia", "P1")));
        rows.put("patologia_mortale",
                Collections.singletonList(row("cod_patologia", "P1")));
        rows.put("ospedale", Arrays.asList(
                row("codice", "H1", "nome", "San Carlo", "citta", "Bergamo",
                        "indirizzo", "Via Uno", "direttore_sanitario_cssn", "CSSN1"),
                row("codice", "H2", "nome", "San Luca", "citta", "Milano",
                        "indirizzo", "Via Due", "direttore_sanitario_cssn", "CSSN2")));
        rows.put("ricovero", Arrays.asList(
                ricovero("H1", 2, "2024-02-29", "10.00"),
                ricovero("H2", 1, "2024-03-01", "20.50")));
        rows.put("patologia_ricovero", Arrays.asList(
                row("cod_ospedale", "H1", "cod_ricovero", 2L, "cod_patologia", "P1"),
                row("cod_ospedale", "H2", "cod_ricovero", 1L, "cod_patologia", "P1")));
        rows.put("progressivo_ricovero", Arrays.asList(
                row("cod_ospedale", "H1", "prossimo_cod", 3L),
                row("cod_ospedale", "H2", "prossimo_cod", 2L)));
        return rows;
    }

    private static LinkedHashMap<String, List<Map<String, Object>>> emptyRows() {
        LinkedHashMap<String, List<Map<String, Object>>> result =
                new LinkedHashMap<String, List<Map<String, Object>>>();
        for (String entity : EntitySchemas.names()) {
            result.put(entity, Collections.<Map<String, Object>>emptyList());
        }
        return result;
    }

    private static Map<String, Object> cittadino(String cssn) {
        return row("cssn", cssn, "nome", "Anna", "cognome", "Rossi",
                "data_nascita", "1980-02-29", "luogo_nascita", "Bergamo",
                "indirizzo", "Via Roma");
    }

    private static Map<String, Object> patologia(String cod, String nome, int criticita) {
        return row("cod", cod, "nome", nome, "criticita", Long.valueOf(criticita));
    }

    private static Map<String, Object> ricovero(
            String ospedale, int cod, String data, String costo) {
        return row("cod_ospedale", ospedale, "cod", Long.valueOf(cod),
                "paziente_cssn", "CSSN1", "data_inizio", data, "durata", 3L,
                "motivo", "Controllo", "costo", costo);
    }

    private static Map<String, Object> row(Object... values) {
        LinkedHashMap<String, Object> result = new LinkedHashMap<String, Object>();
        for (int index = 0; index < values.length; index += 2) {
            result.put((String) values[index], values[index + 1]);
        }
        return result;
    }

    private static Dataset dataset(
            LinkedHashMap<String, List<Map<String, Object>>> rows) {
        return datasetInternal(rows);
    }

    private static Dataset datasetInternal(
            LinkedHashMap<String, List<Map<String, Object>>> rows) {
        ArrayList<Object> entityValues = new ArrayList<Object>();
        ArrayList<Object> order = new ArrayList<Object>();
        ArrayList<DatasetIdentity.Descriptor> descriptors =
                new ArrayList<DatasetIdentity.Descriptor>();
        for (EntitySchema schema : EntitySchemas.ordered()) {
            List<EntityCanonicalizer.Row> typed = typed(schema, rows.get(schema.name));
            String digest = EntityCanonicalizer.sha256(schema, typed);
            LinkedHashMap<String, Object> entity = map();
            entity.put("entity", schema.name);
            entity.put("rowCount", Long.valueOf(rows.get(schema.name).size()));
            entity.put("digest", digest);
            entityValues.add(entity);
            order.add(schema.name);
            descriptors.add(new DatasetIdentity.Descriptor(
                    schema.name, rows.get(schema.name).size(), digest));
        }
        String id = DatasetIdentity.sha256(descriptors);
        LinkedHashMap<String, Object> manifest = map();
        manifest.put("apiVersion", "1.0");
        manifest.put("datasetId", id);
        manifest.put("generatedAt", "2026-07-24T12:00:00Z");
        manifest.put("entityOrder", order);
        manifest.put("entities", entityValues);
        manifest.put("maxBatchSize", 100L);
        return new Dataset(id, manifest);
    }

    private static List<EntityCanonicalizer.Row> typed(
            EntitySchema schema, List<Map<String, Object>> rows) {
        ArrayList<EntityCanonicalizer.Row> result =
                new ArrayList<EntityCanonicalizer.Row>();
        for (Map<String, Object> row : rows) result.add(EntityCanonicalizer.validate(schema, row));
        return result;
    }

    private static Map<String, Object> page(
            String datasetId,
            EntitySchema schema,
            List<Map<String, Object>> rows,
            String cursor,
            String nextCursor,
            boolean hasMore) {
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("datasetId", datasetId);
        result.put("entity", schema.name);
        result.put("cursor", cursor);
        result.put("nextCursor", nextCursor);
        result.put("hasMore", Boolean.valueOf(hasMore));
        result.put("rowCount", Long.valueOf(rows.size()));
        result.put("rows", new ArrayList<Object>(rows));
        result.put("digest", EntityCanonicalizer.sha256(schema, typed(schema, rows)));
        return result;
    }

    private static Map<String, Object> batchResponse(
            String datasetId,
            EntitySchema schema,
            int sequence,
            List<Map<String, Object>> rows,
            boolean idempotent) {
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("migrationId", MIGRATION_ID);
        result.put("datasetId", datasetId);
        result.put("entity", schema.name);
        result.put("batchSequence", Long.valueOf(sequence));
        result.put("rowCount", Long.valueOf(rows.size()));
        result.put("digest", EntityCanonicalizer.sha256(schema, typed(schema, rows)));
        result.put("idempotent", Boolean.valueOf(idempotent));
        result.put("status", idempotent ? "completed" : "running");
        return result;
    }

    private static Map<String, Object> finalizeResponse(
            String datasetId,
            EntitySchema schema,
            List<Map<String, Object>> rows,
            int batchCount) {
        LinkedHashMap<String, Object> verification = map();
        verification.put("rowCountMatches", Boolean.TRUE);
        verification.put("digestMatches", Boolean.TRUE);
        verification.put("constraintsValid", Boolean.TRUE);
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("migrationId", MIGRATION_ID);
        result.put("datasetId", datasetId);
        result.put("entity", schema.name);
        result.put("status", "completed");
        result.put("rowCount", Long.valueOf(rows.size()));
        result.put("batchCount", Long.valueOf(batchCount));
        result.put("digest", EntityCanonicalizer.sha256(schema, typed(schema, rows)));
        result.put("verification", verification);
        return result;
    }

    private static String exportUrl(String entity, String cursor) {
        String result = REMOTE + "/api/v1/export/" + entity + "?limit=1";
        return cursor == null ? result : result + "&cursor=" + cursor;
    }

    private static LinkedHashMap<String, Object> map() {
        return new LinkedHashMap<String, Object>();
    }

    private static String readFixture() {
        InputStream input = MigrationOrchestratorTest.class.getResourceAsStream("/t03-dataset.json");
        if (input == null) {
            String configured = System.getProperty("driveaura.t03Fixture");
            File file = new File(
                    configured == null ? "tests/fixtures/t03-dataset.json" : configured);
            if (!file.isFile()) throw new IllegalStateException("Fixture T03 condivisa mancante.");
            try {
                input = new FileInputStream(file);
            } catch (IOException error) {
                throw new IllegalStateException("Fixture T03 non leggibile.", error);
            }
        }
        try {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int read;
            while ((read = input.read(buffer)) != -1) output.write(buffer, 0, read);
            return new String(output.toByteArray(), StandardCharsets.UTF_8);
        } catch (IOException error) {
            throw new IllegalStateException("Fixture T03 non leggibile.", error);
        } finally {
            try {
                input.close();
            } catch (IOException ignored) {
                // The fixture was already consumed.
            }
        }
    }

    private static long longValue(Map<String, Object> body, String key) {
        return ((Long) body.get(key)).longValue();
    }

    private static void exactKeys(Map<String, Object> body, String... keys) {
        check(body.keySet().equals(new LinkedHashSet<String>(Arrays.asList(keys))),
                "Campi JSON inattesi.");
    }

    private static void expectMigration(String code, Action action) {
        try {
            action.run();
            throw new AssertionError("Eccezione attesa: " + code);
        } catch (MigrationException error) {
            check(code.equals(error.code), "Codice errore inatteso: " + error.code);
        }
    }

    private static void expectIllegal(Action action) {
        try {
            action.run();
            throw new AssertionError("IllegalArgumentException attesa.");
        } catch (IllegalArgumentException expected) {
            // Expected.
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private interface Action {
        void run();
    }

    private interface PageMutation {
        void mutate(Map<String, Object> page);
    }

    private interface BodyCheck {
        void verify(Map<String, Object> body);
    }

    private static final class Dataset {
        private final String id;
        private final LinkedHashMap<String, Object> manifest;

        private Dataset(String id, LinkedHashMap<String, Object> manifest) {
            this.id = id;
            this.manifest = manifest;
        }
    }

    private static final class FakeTransport implements HttpTransport {
        private final List<Step> steps = new ArrayList<Step>();
        private int current;

        private void response(String method, String url, int status, Map<String, Object> body) {
            response(method, url, status, body, null);
        }

        private void response(
                String method, String url, int status, Map<String, Object> body, BodyCheck check) {
            steps.add(new Step(method, url, new Response(status, Json.stringify(body)), null, check));
        }

        private void responseWithContentType(
                String method,
                String url,
                int status,
                Map<String, Object> body,
                String contentType) {
            steps.add(new Step(
                    method, url, new Response(status, Json.stringify(body), contentType), null, null));
        }

        private void failure(String method, String url, MigrationException failure) {
            steps.add(new Step(method, url, null, failure, null));
        }

        @Override
        public Response execute(
                String method,
                String url,
                Map<String, String> headers,
                String body,
                int connectTimeoutMs,
                int readTimeoutMs) {
            if (current >= steps.size()) throw new AssertionError("Chiamata HTTP inattesa: " + url);
            Step step = steps.get(current++);
            check(step.method.equals(method), "Metodo HTTP inatteso.");
            check(step.url.equals(url), "URL inatteso: " + url);
            String expectedSecret = url.startsWith(REMOTE)
                    ? "Bearer remote-test-secret" : "Bearer local-test-secret";
            check(expectedSecret.equals(headers.get("Authorization")), "Bearer non propagato.");
            if (step.bodyCheck != null) {
                @SuppressWarnings("unchecked")
                Map<String, Object> parsed = (Map<String, Object>) Json.parse(body);
                step.bodyCheck.verify(parsed);
            }
            if (step.failure != null) throw step.failure;
            return step.response;
        }

        private void assertDone() {
            check(current == steps.size(), "Non tutte le chiamate HTTP attese sono state eseguite.");
        }
    }

    private static final class Step {
        private final String method;
        private final String url;
        private final HttpTransport.Response response;
        private final MigrationException failure;
        private final BodyCheck bodyCheck;

        private Step(
                String method,
                String url,
                HttpTransport.Response response,
                MigrationException failure,
                BodyCheck bodyCheck) {
            this.method = method;
            this.url = url;
            this.response = response;
            this.failure = failure;
            this.bodyCheck = bodyCheck;
        }
    }
}
