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

/** Dependency-free contracts for checkpoint, resume and selective retry. */
public final class MigrationOrchestratorTest {
    private static final String MIGRATION_ID =
            "11111111-1111-1111-1111-111111111111";
    private static final String REMOTE = "https://remote.test";
    private static final String LOCAL = "http://127.0.0.1:8765";

    private MigrationOrchestratorTest() {
    }

    public static void main(String[] args) {
        configureResources(args);
        sharedFixtureDigests();
        validatorsAndCompositeKeys();
        freshCheckpointedMigration();
        resumeSkipsCompletedAndContinuesCursor();
        remoteTimeoutIsRetried();
        local503IsRetried();
        invalidHttpResponseIsNotRetried();
        fatalContractIsSingleAttemptAndReported();
        finalManifestChangeIsRejected();
        statusProxyAndRecoverableError();
        System.out.println("Resilienza orchestratore Java valida.");
    }

    private static void configureResources(String[] args) {
        if (args.length == 2) {
            System.setProperty("driveaura.entitySchema", args[0]);
            System.setProperty("driveaura.t03Fixture", args[1]);
        } else if (args.length != 0) {
            throw new IllegalArgumentException(
                    "Uso: MigrationOrchestratorTest [entity-schema.json t03-dataset.json]");
        }
    }

    @SuppressWarnings("unchecked")
    private static void sharedFixtureDigests() {
        Map<String, Object> fixture = (Map<String, Object>) Json.parse(readFixture());
        Map<String, Object> rowsByEntity =
                (Map<String, Object>) fixture.get("rowsByEntity");
        Map<String, Object> expectedByEntity =
                (Map<String, Object>) fixture.get("expectedByEntity");
        ArrayList<DatasetIdentity.Descriptor> descriptors =
                new ArrayList<DatasetIdentity.Descriptor>();
        for (EntitySchema schema : EntitySchemas.ordered()) {
            List<Object> rawRows = (List<Object>) rowsByEntity.get(schema.name);
            List<EntityCanonicalizer.Row> rows =
                    EntityCanonicalizer.validateAll(schema, rawRows);
            Map<String, Object> expected =
                    (Map<String, Object>) expectedByEntity.get(schema.name);
            String canonical = new String(
                    EntityCanonicalizer.canonicalBytes(schema, rows),
                    StandardCharsets.UTF_8);
            check(canonical.equals(expected.get("expectedCanonical")),
                    "Byte canonici fixture non validi per " + schema.name + ".");
            String digest = EntityCanonicalizer.sha256(schema, rows);
            check(digest.equals(expected.get("expectedSha256")),
                    "Digest fixture non valido per " + schema.name + ".");
            descriptors.add(new DatasetIdentity.Descriptor(
                    schema.name, rawRows.size(), digest));
        }
        check(DatasetIdentity.sha256(descriptors).equals(
                        fixture.get("expectedDatasetId")),
                "DatasetId condiviso non valido.");
    }

    private static void validatorsAndCompositeKeys() {
        check(EntitySchemas.names().size() == 8, "Schema condiviso incompleto.");
        final EntitySchema ricovero = EntitySchemas.require("ricovero");
        final Map<String, Object> invalidDate =
                ricovero("H1", 1, "2025-02-29", "10.00");
        expectIllegal(new Action() {
            @Override
            public void run() {
                EntityCanonicalizer.validate(ricovero, invalidDate);
            }
        });
        final Map<String, Object> invalidDecimal =
                ricovero("H1", 1, "2024-02-29", "01.00");
        expectIllegal(new Action() {
            @Override
            public void run() {
                EntityCanonicalizer.validate(ricovero, invalidDecimal);
            }
        });
        EntityCanonicalizer.Row first = EntityCanonicalizer.validate(
                ricovero, ricovero("H1", 2, "2024-01-01", "10.00"));
        EntityCanonicalizer.Row second = EntityCanonicalizer.validate(
                ricovero, ricovero("H2", 1, "2024-01-01", "10.00"));
        EntityCanonicalizer.Key key = EntityCanonicalizer.keyOf(ricovero, first);
        check(EntityCanonicalizer.compare(ricovero, key, second) < 0,
                "Il resume deve confrontare la PK composta completa.");
    }

    private static void freshCheckpointedMigration() {
        LinkedHashMap<String, List<Map<String, Object>>> rows = emptyRows();
        rows.put("cittadino", Arrays.asList(cittadino("A"), cittadino("B")));
        Dataset dataset = dataset(rows);
        FakeTransport fake = new FakeTransport();
        addManifest(fake, dataset);
        fake.response("POST", localMigrationUrl(), 201,
                initResponse(dataset.id, false, "created"));
        fake.response("GET", localMigrationUrl(), 200,
                state(dataset, "created", "cittadino", null,
                        Collections.<String, Checkpoint>emptyMap()));

        EntitySchema schema = EntitySchemas.require("cittadino");
        String cursor = "page1.signature";
        List<Map<String, Object>> first =
                Collections.singletonList(rows.get("cittadino").get(0));
        List<Map<String, Object>> second =
                Collections.singletonList(rows.get("cittadino").get(1));
        fake.response("GET", exportUrl(dataset, "cittadino", null), 200,
                page(dataset.id, schema, first, null, cursor, true));
        fake.response("POST", localBatchesUrl(), 201,
                batchResponse(dataset.id, schema, 0, first, false,
                        null, cursor, true), checkpointCheck(0, null, cursor, true));
        fake.response("GET", exportUrl(dataset, "cittadino", cursor), 200,
                page(dataset.id, schema, second, cursor, null, false));
        fake.response("POST", localBatchesUrl(), 201,
                batchResponse(dataset.id, schema, 1, second, false,
                        cursor, null, false), checkpointCheck(1, cursor, null, false));
        fake.response("POST", localFinalizeUrl(), 200,
                finalizeResponse(dataset, schema, 2));
        addEmptyFinalizations(fake, dataset, 1);
        addManifest(fake, dataset);
        fake.response("GET", localMigrationUrl(), 200,
                completedState(dataset, checkpointsForFresh(rows, cursor)));

        MigrationOrchestrator.Result result =
                new MigrationOrchestrator(config(0), fake).migrate(MIGRATION_ID);
        check("completed".equals(result.status), "Migrazione fresca non completata.");
        check(result.totalRowCount == 2L && result.totalBatchCount == 2L,
                "Totali migrazione fresca non validi.");
        fake.assertDone();
    }

    private static void resumeSkipsCompletedAndContinuesCursor() {
        LinkedHashMap<String, List<Map<String, Object>>> rows = emptyRows();
        rows.put("cittadino", Collections.singletonList(cittadino("A")));
        rows.put("patologia", Arrays.asList(
                patologia("P1", "Prima", 1),
                patologia("P2", "Seconda", 5)));
        Dataset dataset = dataset(rows);
        String resumeCursor = "resume.signature";
        LinkedHashMap<String, Checkpoint> partial = new LinkedHashMap<String, Checkpoint>();
        partial.put("cittadino", Checkpoint.completed(
                1, 1, null, null, false, key("A")));
        partial.put("patologia", Checkpoint.running(
                1, 1, null, resumeCursor, true, key("P1"), "REMOTE_TIMEOUT"));

        FakeTransport fake = new FakeTransport();
        addManifest(fake, dataset);
        fake.response("POST", localMigrationUrl(), 200,
                initResponse(dataset.id, true, "interrupted"));
        fake.response("GET", localMigrationUrl(), 200,
                state(dataset, "interrupted", "patologia", Boolean.TRUE, partial));

        EntitySchema schema = EntitySchemas.require("patologia");
        List<Map<String, Object>> second =
                Collections.singletonList(rows.get("patologia").get(1));
        fake.response("GET", exportUrl(dataset, "patologia", resumeCursor), 200,
                page(dataset.id, schema, second, resumeCursor, null, false));
        fake.response("POST", localBatchesUrl(), 201,
                batchResponse(dataset.id, schema, 1, second, false,
                        resumeCursor, null, false),
                checkpointCheck(1, resumeCursor, null, false));
        fake.response("POST", localFinalizeUrl(), 200,
                finalizeResponse(dataset, schema, 2));
        addEmptyFinalizations(fake, dataset, 2);
        addManifest(fake, dataset);
        LinkedHashMap<String, Checkpoint> completed =
                new LinkedHashMap<String, Checkpoint>(partial);
        completed.put("patologia", Checkpoint.completed(
                2, 2, resumeCursor, null, false, key("P2")));
        fake.response("GET", localMigrationUrl(), 200,
                completedState(dataset, completed));

        MigrationOrchestrator.Result result =
                new MigrationOrchestrator(config(0), fake).migrate(MIGRATION_ID);
        check(result.totalRowCount == 3L && result.totalBatchCount == 3L,
                "Il resume non ha preservato i checkpoint.");
        fake.assertDone();
    }

    private static void remoteTimeoutIsRetried() {
        Dataset dataset = dataset(emptyRows());
        FakeTransport fake = new FakeTransport();
        fake.failure("GET", REMOTE + "/api/v1/manifest",
                new MigrationException(
                        "HTTP_TIMEOUT", 504, "timeout", true));
        addManifest(fake, dataset);
        addAllEmptyWorkflowAfterManifest(fake, dataset);
        MigrationOrchestrator.Result result =
                new MigrationOrchestrator(config(1), fake).migrate(MIGRATION_ID);
        check("completed".equals(result.status), "Retry timeout remoto fallito.");
        fake.assertDone();
    }

    private static void local503IsRetried() {
        Dataset dataset = dataset(emptyRows());
        FakeTransport fake = new FakeTransport();
        addManifest(fake, dataset);
        fake.response("POST", localMigrationUrl(), 503, error("TEMPORARY"));
        fake.response("POST", localMigrationUrl(), 201,
                initResponse(dataset.id, false, "created"));
        fake.response("GET", localMigrationUrl(), 200,
                state(dataset, "created", "cittadino", null,
                        Collections.<String, Checkpoint>emptyMap()));
        addEmptyFinalizations(fake, dataset, 0);
        addManifest(fake, dataset);
        fake.response("GET", localMigrationUrl(), 200,
                completedState(dataset,
                        Collections.<String, Checkpoint>emptyMap()));
        MigrationOrchestrator.Result result =
                new MigrationOrchestrator(config(1), fake).migrate(MIGRATION_ID);
        check("completed".equals(result.status), "Retry 503 locale fallito.");
        fake.assertDone();
    }

    private static void invalidHttpResponseIsNotRetried() {
        FakeTransport fake = new FakeTransport();
        fake.failure("GET", REMOTE + "/api/v1/manifest",
                new MigrationException(
                        "HTTP_INVALID_RESPONSE", 502,
                        "invalid response", false));
        MigrationException error = expectMigration(
                "HTTP_INVALID_RESPONSE", new Action() {
                    @Override
                    public void run() {
                        new MigrationOrchestrator(config(3), fake)
                                .migrate(MIGRATION_ID);
                    }
                });
        check(!error.recoverable,
                "Risposta HTTP non valida dichiarata recuperabile.");
        fake.assertDone();
    }

    private static void fatalContractIsSingleAttemptAndReported() {
        LinkedHashMap<String, List<Map<String, Object>>> rows = emptyRows();
        rows.put("cittadino", Collections.singletonList(cittadino("A")));
        Dataset dataset = dataset(rows);
        FakeTransport fake = new FakeTransport();
        addManifest(fake, dataset);
        fake.response("POST", localMigrationUrl(), 201,
                initResponse(dataset.id, false, "created"));
        fake.response("GET", localMigrationUrl(), 200,
                state(dataset, "created", "cittadino", null,
                        Collections.<String, Checkpoint>emptyMap()));
        EntitySchema schema = EntitySchemas.require("cittadino");
        Map<String, Object> invalid = page(
                dataset.id, schema, rows.get("cittadino"), null, null, false);
        invalid.put("digest",
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        fake.response("GET", exportUrl(dataset, "cittadino", null), 200, invalid);
        fake.response("POST", localFailureUrl(), 200,
                failureResponse(dataset.id, "cittadino",
                        "REMOTE_CONTRACT_ERROR", false));
        MigrationException error = expectMigration(
                "REMOTE_CONTRACT_ERROR", new Action() {
                    @Override
                    public void run() {
                        new MigrationOrchestrator(config(3), fake).migrate(MIGRATION_ID);
                    }
                });
        check(!error.recoverable, "Errore di digest dichiarato recuperabile.");
        fake.assertDone();
    }

    private static void finalManifestChangeIsRejected() {
        Dataset initial = dataset(emptyRows());
        LinkedHashMap<String, List<Map<String, Object>>> changedRows = emptyRows();
        changedRows.put("patologia",
                Collections.singletonList(patologia("PX", "Nuova", 1)));
        Dataset changed = dataset(changedRows);
        FakeTransport fake = new FakeTransport();
        addManifest(fake, initial);
        fake.response("POST", localMigrationUrl(), 201,
                initResponse(initial.id, false, "created"));
        fake.response("GET", localMigrationUrl(), 200,
                state(initial, "created", "cittadino", null,
                        Collections.<String, Checkpoint>emptyMap()));
        addEmptyFinalizationsBeforeLast(fake, initial, 0);
        addManifest(fake, changed);
        fake.response("POST", localFailureUrl(), 200,
                failureResponse(initial.id, "progressivo_ricovero",
                        "REMOTE_DATASET_CHANGED", false));
        MigrationException error = expectMigration(
                "REMOTE_DATASET_CHANGED", new Action() {
                    @Override
                    public void run() {
                        new MigrationOrchestrator(config(0), fake).migrate(MIGRATION_ID);
                    }
                });
        check(!error.recoverable, "Cambio dataset dichiarato recuperabile.");
        fake.assertDone();
    }

    private static void statusProxyAndRecoverableError() {
        Dataset dataset = dataset(emptyRows());
        FakeTransport fake = new FakeTransport();
        Map<String, Object> interrupted = state(
                dataset, "interrupted", "cittadino", Boolean.TRUE,
                Collections.<String, Checkpoint>emptyMap());
        fake.response("GET", localMigrationUrl(), 200, interrupted);
        MigrationEndpoint endpoint = new MigrationEndpoint(config(0), fake);
        MigrationEndpoint.Response response =
                endpoint.status("Bearer bridge-test-secret", MIGRATION_ID);
        check(response.status == 200, "Proxy stato non riuscito.");
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) Json.parse(response.body);
        exactKeys(body, "apiVersion", "migrationId", "datasetId", "entity",
                "status", "rowsImported", "totalExpected", "batchesImported",
                "lastBatchSequence", "lastError", "currentEntity",
                "recoverable", "entities");
        check(Boolean.TRUE.equals(body.get("recoverable")),
                "Proxy stato perde recoverable.");
        fake.assertDone();

        MigrationEndpoint.Response unauthorized =
                endpoint.status("Bearer wrong", MIGRATION_ID);
        @SuppressWarnings("unchecked")
        Map<String, Object> errorBody =
                (Map<String, Object>) Json.parse(unauthorized.body);
        @SuppressWarnings("unchecked")
        Map<String, Object> detail =
                (Map<String, Object>) errorBody.get("error");
        exactKeys(detail, "code", "message", "recoverable");
        check(Boolean.FALSE.equals(detail.get("recoverable")),
                "Errore bridge non dichiara recoverable.");
    }

    private static void addAllEmptyWorkflowAfterManifest(
            FakeTransport fake, Dataset dataset) {
        fake.response("POST", localMigrationUrl(), 201,
                initResponse(dataset.id, false, "created"));
        fake.response("GET", localMigrationUrl(), 200,
                state(dataset, "created", "cittadino", null,
                        Collections.<String, Checkpoint>emptyMap()));
        addEmptyFinalizations(fake, dataset, 0);
        addManifest(fake, dataset);
        fake.response("GET", localMigrationUrl(), 200,
                completedState(dataset,
                        Collections.<String, Checkpoint>emptyMap()));
    }

    private static void addEmptyFinalizations(
            FakeTransport fake, Dataset dataset, int startEntityIndex) {
        for (int index = startEntityIndex;
                index < EntitySchemas.ordered().size(); index++) {
            EntitySchema schema = EntitySchemas.ordered().get(index);
            if (index == EntitySchemas.ordered().size() - 1) {
                addManifest(fake, dataset);
            }
            fake.response("POST", localFinalizeUrl(), 200,
                    finalizeResponse(dataset, schema, 0));
        }
    }

    private static void addEmptyFinalizationsBeforeLast(
            FakeTransport fake, Dataset dataset, int startEntityIndex) {
        for (int index = startEntityIndex;
                index < EntitySchemas.ordered().size() - 1; index++) {
            EntitySchema schema = EntitySchemas.ordered().get(index);
            fake.response("POST", localFinalizeUrl(), 200,
                    finalizeResponse(dataset, schema, 0));
        }
    }

    private static LinkedHashMap<String, Checkpoint> checkpointsForFresh(
            LinkedHashMap<String, List<Map<String, Object>>> rows,
            String finalSourceCursor) {
        LinkedHashMap<String, Checkpoint> result =
                new LinkedHashMap<String, Checkpoint>();
        result.put("cittadino", Checkpoint.completed(
                rows.get("cittadino").size(), 2,
                finalSourceCursor, null, false, key("B")));
        return result;
    }

    private static void addManifest(FakeTransport fake, Dataset dataset) {
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, dataset.manifest);
    }

    private static BodyCheck checkpointCheck(
            final int sequence,
            final String sourceCursor,
            final String nextCursor,
            final boolean hasMore) {
        return new BodyCheck() {
            @Override
            public void verify(Map<String, Object> body) {
                check(longValue(body, "batchSequence") == sequence,
                        "Sequenza lotto non valida.");
                check(sameNullable(sourceCursor, body.get("sourceCursor")),
                        "sourceCursor non propagato.");
                check(sameNullable(nextCursor, body.get("nextCursor")),
                        "nextCursor non propagato.");
                check(Boolean.valueOf(hasMore).equals(body.get("hasMore")),
                        "hasMore non propagato.");
            }
        };
    }

    private static MigrationConfig config(int retries) {
        return new MigrationConfig(
                REMOTE, LOCAL,
                "remote-test-secret", "local-test-secret", "bridge-test-secret",
                1, 1000, 1000, retries, 0);
    }

    private static Map<String, Object> initResponse(
            String datasetId, boolean idempotent, String status) {
        return row(
                "apiVersion", "1.0",
                "migrationId", MIGRATION_ID,
                "datasetId", datasetId,
                "status", status,
                "idempotent", Boolean.valueOf(idempotent));
    }

    private static Map<String, Object> state(
            Dataset dataset,
            String globalStatus,
            String currentEntity,
            Boolean recoverable,
            Map<String, Checkpoint> checkpoints) {
        ArrayList<Object> entities = new ArrayList<Object>();
        long importedRows = 0L;
        long expectedRows = 0L;
        long importedBatches = 0L;
        Checkpoint current = null;
        for (EntitySchema schema : EntitySchemas.ordered()) {
            Checkpoint checkpoint = checkpoints.get(schema.name);
            if (checkpoint == null) checkpoint = Checkpoint.created();
            EntityInfo info = dataset.info.get(schema.name);
            importedRows += checkpoint.rowsImported;
            expectedRows += info.rows.size();
            importedBatches += checkpoint.nextSequence;
            if (schema.name.equals(currentEntity)) current = checkpoint;
            entities.add(row(
                    "entity", schema.name,
                    "status", checkpoint.status,
                    "expectedRowCount", Long.valueOf(info.rows.size()),
                    "expectedDigest", info.digest,
                    "rowsImported", Long.valueOf(checkpoint.rowsImported),
                    "nextBatchSequence", Long.valueOf(checkpoint.nextSequence),
                    "lastBatchSequence", checkpoint.lastSequence == null
                            ? null : Long.valueOf(checkpoint.lastSequence),
                    "sourceCursor", checkpoint.sourceCursor,
                    "nextCursor", checkpoint.nextCursor,
                    "hasMore", Boolean.valueOf(checkpoint.hasMore),
                    "lastKey", new ArrayList<Object>(checkpoint.lastKey),
                    "lastError", checkpoint.lastError));
        }
        check(current != null, "Entita corrente di test non valida.");
        return row(
                "apiVersion", "1.0",
                "migrationId", MIGRATION_ID,
                "datasetId", dataset.id,
                "entity", currentEntity,
                "status", globalStatus,
                "rowsImported", Long.valueOf(importedRows),
                "totalExpected", Long.valueOf(expectedRows),
                "batchesImported", Long.valueOf(importedBatches),
                "lastBatchSequence", current.lastSequence == null
                        ? null : Long.valueOf(current.lastSequence),
                "lastError", current.lastError,
                "currentEntity", currentEntity,
                "recoverable", recoverable,
                "entities", entities);
    }

    private static Map<String, Object> completedState(
            Dataset dataset, Map<String, Checkpoint> overrides) {
        LinkedHashMap<String, Checkpoint> completed =
                new LinkedHashMap<String, Checkpoint>();
        for (EntitySchema schema : EntitySchemas.ordered()) {
            Checkpoint checkpoint = overrides.get(schema.name);
            if (checkpoint == null) checkpoint = Checkpoint.completed(
                    0, 0, null, null, false,
                    Collections.<Object>emptyList());
            completed.put(schema.name, checkpoint);
        }
        return state(
                dataset, "completed", "progressivo_ricovero", null, completed);
    }

    private static Map<String, Object> page(
            String datasetId,
            EntitySchema schema,
            List<Map<String, Object>> rows,
            String cursor,
            String nextCursor,
            boolean hasMore) {
        return row(
                "apiVersion", "1.0",
                "datasetId", datasetId,
                "entity", schema.name,
                "cursor", cursor,
                "nextCursor", nextCursor,
                "hasMore", Boolean.valueOf(hasMore),
                "rowCount", Long.valueOf(rows.size()),
                "rows", new ArrayList<Object>(rows),
                "digest", digest(schema, rows));
    }

    private static Map<String, Object> batchResponse(
            String datasetId,
            EntitySchema schema,
            int sequence,
            List<Map<String, Object>> rows,
            boolean idempotent,
            String sourceCursor,
            String nextCursor,
            boolean hasMore) {
        return row(
                "apiVersion", "1.0",
                "migrationId", MIGRATION_ID,
                "datasetId", datasetId,
                "entity", schema.name,
                "batchSequence", Long.valueOf(sequence),
                "rowCount", Long.valueOf(rows.size()),
                "digest", digest(schema, rows),
                "idempotent", Boolean.valueOf(idempotent),
                "status", idempotent ? "completed" : "running",
                "sourceCursor", sourceCursor,
                "nextCursor", nextCursor,
                "hasMore", Boolean.valueOf(hasMore));
    }

    private static Map<String, Object> finalizeResponse(
            Dataset dataset, EntitySchema schema, int batchCount) {
        EntityInfo info = dataset.info.get(schema.name);
        return row(
                "apiVersion", "1.0",
                "migrationId", MIGRATION_ID,
                "datasetId", dataset.id,
                "entity", schema.name,
                "status", "completed",
                "rowCount", Long.valueOf(info.rows.size()),
                "batchCount", Long.valueOf(batchCount),
                "digest", info.digest,
                "verification", row(
                        "rowCountMatches", Boolean.TRUE,
                        "digestMatches", Boolean.TRUE,
                        "constraintsValid", Boolean.TRUE));
    }

    private static Map<String, Object> failureResponse(
            String datasetId, String entity, String code, boolean recoverable) {
        return row(
                "apiVersion", "1.0",
                "migrationId", MIGRATION_ID,
                "datasetId", datasetId,
                "status", recoverable ? "interrupted" : "failed",
                "currentEntity", entity,
                "lastError", code,
                "recoverable", Boolean.valueOf(recoverable));
    }

    private static Map<String, Object> error(String code) {
        return row(
                "apiVersion", "1.0",
                "error", row(
                        "code", code,
                        "message", "Errore sintetico."));
    }

    private static String localMigrationUrl() {
        return LOCAL + "/api/v1/migrations/" + MIGRATION_ID;
    }

    private static String localBatchesUrl() {
        return localMigrationUrl() + "/batches";
    }

    private static String localFinalizeUrl() {
        return localMigrationUrl() + "/finalize";
    }

    private static String localFailureUrl() {
        return localMigrationUrl() + "/failure";
    }

    private static String exportUrl(
            Dataset dataset, String entity, String cursor) {
        String url = REMOTE + "/api/v1/export/" + entity
                + "?limit=1&datasetId=" + dataset.id;
        return cursor == null ? url : url + "&cursor=" + cursor;
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
        return row(
                "cssn", cssn,
                "nome", "Anna",
                "cognome", "Rossi",
                "data_nascita", "1980-02-29",
                "luogo_nascita", "Bergamo",
                "indirizzo", "Via Roma");
    }

    private static Map<String, Object> patologia(
            String cod, String nome, int criticita) {
        return row(
                "cod", cod,
                "nome", nome,
                "criticita", Long.valueOf(criticita));
    }

    private static Map<String, Object> ricovero(
            String ospedale, int cod, String data, String costo) {
        return row(
                "cod_ospedale", ospedale,
                "cod", Long.valueOf(cod),
                "paziente_cssn", "CSSN1",
                "data_inizio", data,
                "durata", 3L,
                "motivo", "Controllo",
                "costo", costo);
    }

    private static List<Object> key(Object... values) {
        return new ArrayList<Object>(Arrays.asList(values));
    }

    private static Dataset dataset(
            LinkedHashMap<String, List<Map<String, Object>>> rows) {
        ArrayList<Object> entityValues = new ArrayList<Object>();
        ArrayList<Object> order = new ArrayList<Object>();
        ArrayList<DatasetIdentity.Descriptor> descriptors =
                new ArrayList<DatasetIdentity.Descriptor>();
        LinkedHashMap<String, EntityInfo> info =
                new LinkedHashMap<String, EntityInfo>();
        for (EntitySchema schema : EntitySchemas.ordered()) {
            List<Map<String, Object>> entityRows = rows.get(schema.name);
            String digest = digest(schema, entityRows);
            entityValues.add(row(
                    "entity", schema.name,
                    "rowCount", Long.valueOf(entityRows.size()),
                    "digest", digest));
            order.add(schema.name);
            descriptors.add(new DatasetIdentity.Descriptor(
                    schema.name, entityRows.size(), digest));
            info.put(schema.name, new EntityInfo(entityRows, digest));
        }
        String id = DatasetIdentity.sha256(descriptors);
        Map<String, Object> manifest = row(
                "apiVersion", "1.0",
                "datasetId", id,
                "generatedAt", "2026-07-25T10:00:00Z",
                "entityOrder", order,
                "entities", entityValues,
                "maxBatchSize", 100L);
        return new Dataset(id, manifest, info);
    }

    private static String digest(
            EntitySchema schema, List<Map<String, Object>> rows) {
        ArrayList<EntityCanonicalizer.Row> typed =
                new ArrayList<EntityCanonicalizer.Row>();
        for (Map<String, Object> value : rows) {
            typed.add(EntityCanonicalizer.validate(schema, value));
        }
        return EntityCanonicalizer.sha256(schema, typed);
    }

    private static Map<String, Object> row(Object... values) {
        LinkedHashMap<String, Object> result =
                new LinkedHashMap<String, Object>();
        for (int index = 0; index < values.length; index += 2) {
            result.put((String) values[index], values[index + 1]);
        }
        return result;
    }

    private static long longValue(Map<String, Object> body, String key) {
        return ((Long) body.get(key)).longValue();
    }

    private static boolean sameNullable(Object left, Object right) {
        return left == null ? right == null : left.equals(right);
    }

    private static void exactKeys(Map<String, Object> body, String... keys) {
        check(body.keySet().equals(
                        new LinkedHashSet<String>(Arrays.asList(keys))),
                "Campi JSON inattesi.");
    }

    private static MigrationException expectMigration(
            String code, Action action) {
        try {
            action.run();
            throw new AssertionError("Eccezione attesa: " + code);
        } catch (MigrationException error) {
            check(code.equals(error.code),
                    "Codice errore inatteso: " + error.code);
            return error;
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

    private static String readFixture() {
        InputStream input =
                MigrationOrchestratorTest.class.getResourceAsStream("/t03-dataset.json");
        if (input == null) {
            String configured = System.getProperty("driveaura.t03Fixture");
            File file = new File(
                    configured == null
                            ? "tests/fixtures/t03-dataset.json" : configured);
            if (!file.isFile()) {
                throw new IllegalStateException("Fixture T03 condivisa mancante.");
            }
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
            while ((read = input.read(buffer)) != -1) {
                output.write(buffer, 0, read);
            }
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

    private interface Action {
        void run();
    }

    private interface BodyCheck {
        void verify(Map<String, Object> body);
    }

    private static final class Dataset {
        private final String id;
        private final Map<String, Object> manifest;
        private final Map<String, EntityInfo> info;

        private Dataset(
                String id,
                Map<String, Object> manifest,
                Map<String, EntityInfo> info) {
            this.id = id;
            this.manifest = manifest;
            this.info = info;
        }
    }

    private static final class EntityInfo {
        private final List<Map<String, Object>> rows;
        private final String digest;

        private EntityInfo(
                List<Map<String, Object>> rows, String digest) {
            this.rows = rows;
            this.digest = digest;
        }
    }

    private static final class Checkpoint {
        private final String status;
        private final int rowsImported;
        private final int nextSequence;
        private final Integer lastSequence;
        private final String sourceCursor;
        private final String nextCursor;
        private final boolean hasMore;
        private final List<Object> lastKey;
        private final String lastError;

        private Checkpoint(
                String status,
                int rowsImported,
                int nextSequence,
                Integer lastSequence,
                String sourceCursor,
                String nextCursor,
                boolean hasMore,
                List<Object> lastKey,
                String lastError) {
            this.status = status;
            this.rowsImported = rowsImported;
            this.nextSequence = nextSequence;
            this.lastSequence = lastSequence;
            this.sourceCursor = sourceCursor;
            this.nextCursor = nextCursor;
            this.hasMore = hasMore;
            this.lastKey = lastKey;
            this.lastError = lastError;
        }

        private static Checkpoint created() {
            return new Checkpoint(
                    "created", 0, 0, null, null, null, false,
                    Collections.<Object>emptyList(), null);
        }

        private static Checkpoint running(
                int rows,
                int nextSequence,
                String sourceCursor,
                String nextCursor,
                boolean hasMore,
                List<Object> lastKey,
                String lastError) {
            return new Checkpoint(
                    "running", rows, nextSequence,
                    Integer.valueOf(nextSequence - 1),
                    sourceCursor, nextCursor, hasMore, lastKey, lastError);
        }

        private static Checkpoint completed(
                int rows,
                int nextSequence,
                String sourceCursor,
                String nextCursor,
                boolean hasMore,
                List<Object> lastKey) {
            return new Checkpoint(
                    "completed", rows, nextSequence,
                    nextSequence == 0 ? null : Integer.valueOf(nextSequence - 1),
                    sourceCursor, nextCursor, hasMore, lastKey, null);
        }
    }

    private static final class FakeTransport implements HttpTransport {
        private final List<Step> steps = new ArrayList<Step>();
        private int current;

        private void response(
                String method,
                String url,
                int status,
                Map<String, Object> body) {
            response(method, url, status, body, null);
        }

        private void response(
                String method,
                String url,
                int status,
                Map<String, Object> body,
                BodyCheck bodyCheck) {
            steps.add(new Step(
                    method, url,
                    new Response(status, Json.stringify(body)),
                    null, bodyCheck));
        }

        private void failure(
                String method, String url, MigrationException failure) {
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
            if (current >= steps.size()) {
                throw new AssertionError("Chiamata HTTP inattesa: " + url);
            }
            Step step = steps.get(current++);
            check(step.method.equals(method), "Metodo HTTP inatteso.");
            check(step.url.equals(url), "URL inatteso: " + url);
            String expectedSecret = url.startsWith(REMOTE)
                    ? "Bearer remote-test-secret" : "Bearer local-test-secret";
            check(expectedSecret.equals(headers.get("Authorization")),
                    "Bearer non propagato.");
            if (step.bodyCheck != null) {
                @SuppressWarnings("unchecked")
                Map<String, Object> parsed =
                        (Map<String, Object>) Json.parse(body);
                step.bodyCheck.verify(parsed);
            }
            if (step.failure != null) throw step.failure;
            return step.response;
        }

        private void assertDone() {
            check(current == steps.size(),
                    "Non tutte le chiamate HTTP attese sono state eseguite.");
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
