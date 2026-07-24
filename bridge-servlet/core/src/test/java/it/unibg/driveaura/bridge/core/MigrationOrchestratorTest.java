package it.unibg.driveaura.bridge.core;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Dependency-free tests for orchestration and hostile upstream responses. */
public final class MigrationOrchestratorTest {
    private static final String MIGRATION_ID = "11111111-1111-1111-1111-111111111111";
    private static final String REMOTE = "https://remote.test";
    private static final String LOCAL = "http://127.0.0.1:8765";
    private static final String EMPTY_DIGEST =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    private static final PatologiaCanonicalizer.Patologia A =
            new PatologiaCanonicalizer.Patologia("A-001", "Alfa", 1);
    private static final PatologiaCanonicalizer.Patologia B =
            new PatologiaCanonicalizer.Patologia("B-002", "Beta", 5);

    private MigrationOrchestratorTest() {
    }

    public static void main(String[] args) {
        jsonIntegersRemainIntegers();
        multipageSuccess();
        emptyDatasetFinalizesWithoutBatch();
        badPageDigestIsRejected();
        repeatedCursorIsRejected();
        localConflictIsPropagatedSafely();
        timeoutIsClassified();
        endpointRejectsWrongSecret();
        endpointRejectsNullMigrationId();
        System.out.println("Orchestrazione Patologia Java valida.");
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

    private static void multipageSuccess() {
        final List<PatologiaCanonicalizer.Patologia> all = Arrays.asList(A, B);
        final String expectedDigest = PatologiaCanonicalizer.sha256(all);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, manifest(all));
        fake.response("GET", REMOTE + "/api/v1/export/patologia?limit=1", 200,
                page(Collections.singletonList(A), expectedDigest, null, "opaque+2", true));
        fake.response("POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/batches", 201,
                batchResponse(0, A, expectedDigest, false, "running"), new BodyCheck() {
                    @Override
                    public void verify(Map<String, Object> body) {
                        exactKeys(body, "apiVersion", "datasetId", "entity", "batchSequence",
                                "rowCount", "rows", "digest", "expectedRowCount", "expectedDigest");
                        check(longValue(body, "batchSequence") == 0, "Prima sequenza non valida.");
                        check(longValue(body, "expectedRowCount") == 2, "Totale atteso non propagato.");
                        check(expectedDigest.equals(body.get("expectedDigest")), "Digest atteso non propagato.");
                    }
                });
        fake.response("GET",
                REMOTE + "/api/v1/export/patologia?limit=1&cursor=opaque%2B2",
                200, page(Collections.singletonList(B), expectedDigest, "opaque+2", null, false));
        fake.response("POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/batches", 201,
                batchResponse(1, B, expectedDigest, false, "running"));
        fake.response("POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/finalize", 200,
                finalizeResponse(2, 2, expectedDigest), new BodyCheck() {
                    @Override
                    public void verify(Map<String, Object> body) {
                        check(longValue(body, "expectedBatchCount") == 2, "Numero lotti non valido.");
                        check(expectedDigest.equals(body.get("expectedDigest")), "Digest finale non propagato.");
                    }
                });

        MigrationOrchestrator.Result result =
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
        check("completed".equals(result.status), "Migrazione non completata.");
        check(result.rowCount == 2 && result.batchCount == 2, "Conteggi risultato non validi.");
        check(expectedDigest.equals(result.digest), "Digest risultato non valido.");
        fake.assertDone();
    }

    private static void emptyDatasetFinalizesWithoutBatch() {
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, manifest(Collections
                .<PatologiaCanonicalizer.Patologia>emptyList()));
        fake.response("GET", REMOTE + "/api/v1/export/patologia?limit=1", 200,
                page(Collections.<PatologiaCanonicalizer.Patologia>emptyList(),
                        EMPTY_DIGEST, null, null, false));
        fake.response("POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/finalize", 200,
                finalizeResponse(0, 0, EMPTY_DIGEST), new BodyCheck() {
                    @Override
                    public void verify(Map<String, Object> body) {
                        check(longValue(body, "expectedRowCount") == 0, "Vuoto: righe attese non zero.");
                        check(longValue(body, "expectedBatchCount") == 0, "Vuoto: lotti attesi non zero.");
                    }
                });

        MigrationOrchestrator.Result result =
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
        check(result.rowCount == 0 && result.batchCount == 0, "Dataset vuoto inoltrato come lotto.");
        fake.assertDone();
    }

    private static void badPageDigestIsRejected() {
        final List<PatologiaCanonicalizer.Patologia> rows = Collections.singletonList(A);
        String datasetDigest = PatologiaCanonicalizer.sha256(rows);
        Map<String, Object> invalidPage = page(rows, datasetDigest, null, null, false);
        invalidPage.put("digest", EMPTY_DIGEST);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, manifest(rows));
        fake.response("GET", REMOTE + "/api/v1/export/patologia?limit=1", 200, invalidPage);
        expectMigration("REMOTE_CONTRACT_ERROR", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void repeatedCursorIsRejected() {
        List<PatologiaCanonicalizer.Patologia> all = Arrays.asList(A, B);
        String datasetDigest = PatologiaCanonicalizer.sha256(all);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, manifest(all));
        fake.response("GET", REMOTE + "/api/v1/export/patologia?limit=1", 200,
                page(Collections.singletonList(A), datasetDigest, null, "same", true));
        fake.response("POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/batches", 201,
                batchResponse(0, A, datasetDigest, false, "running"));
        fake.response("GET", REMOTE + "/api/v1/export/patologia?limit=1&cursor=same", 200,
                page(Collections.singletonList(B), datasetDigest, "same", "same", true));
        expectMigration("REMOTE_CONTRACT_ERROR", new Action() {
            @Override
            public void run() {
                new MigrationOrchestrator(config(), fake).migrate(MIGRATION_ID);
            }
        });
        fake.assertDone();
    }

    private static void localConflictIsPropagatedSafely() {
        List<PatologiaCanonicalizer.Patologia> rows = Collections.singletonList(A);
        String datasetDigest = PatologiaCanonicalizer.sha256(rows);
        FakeTransport fake = new FakeTransport();
        fake.response("GET", REMOTE + "/api/v1/manifest", 200, manifest(rows));
        fake.response("GET", REMOTE + "/api/v1/export/patologia?limit=1", 200,
                page(rows, datasetDigest, null, null, false));
        fake.response("POST", LOCAL + "/api/v1/migrations/" + MIGRATION_ID + "/batches", 409,
                error("BATCH_CONFLICT"));
        expectMigration("LOCAL_CONFLICT", new Action() {
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

    private static Map<String, Object> manifest(List<PatologiaCanonicalizer.Patologia> rows) {
        String digest = PatologiaCanonicalizer.sha256(rows);
        LinkedHashMap<String, Object> entity = map();
        entity.put("entity", "patologia");
        entity.put("rowCount", Long.valueOf(rows.size()));
        entity.put("digest", digest);
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("datasetId", digest);
        result.put("generatedAt", "2026-07-24T12:00:00Z");
        result.put("entityOrder", Collections.<Object>singletonList("patologia"));
        result.put("entities", Collections.<Object>singletonList(entity));
        result.put("maxBatchSize", Long.valueOf(100));
        return result;
    }

    private static Map<String, Object> page(
            List<PatologiaCanonicalizer.Patologia> rows,
            String datasetDigest,
            String cursor,
            String nextCursor,
            boolean hasMore) {
        List<Object> values = rows(rows);
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("datasetId", datasetDigest);
        result.put("entity", "patologia");
        result.put("cursor", cursor);
        result.put("nextCursor", nextCursor);
        result.put("hasMore", Boolean.valueOf(hasMore));
        result.put("rowCount", Long.valueOf(rows.size()));
        result.put("rows", values);
        result.put("digest", PatologiaCanonicalizer.sha256(rows));
        return result;
    }

    private static Map<String, Object> batchResponse(
            int sequence,
            PatologiaCanonicalizer.Patologia row,
            String datasetDigest,
            boolean idempotent,
            String status) {
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("migrationId", MIGRATION_ID);
        result.put("datasetId", datasetDigest);
        result.put("entity", "patologia");
        result.put("batchSequence", Long.valueOf(sequence));
        result.put("rowCount", Long.valueOf(1));
        result.put("digest", PatologiaCanonicalizer.sha256(Collections.singletonList(row)));
        result.put("idempotent", Boolean.valueOf(idempotent));
        result.put("status", status);
        return result;
    }

    private static Map<String, Object> finalizeResponse(int rows, int batches, String digest) {
        LinkedHashMap<String, Object> verification = map();
        verification.put("rowCountMatches", Boolean.TRUE);
        verification.put("digestMatches", Boolean.TRUE);
        verification.put("constraintsValid", Boolean.TRUE);
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("migrationId", MIGRATION_ID);
        result.put("datasetId", digest);
        result.put("entity", "patologia");
        result.put("status", "completed");
        result.put("rowCount", Long.valueOf(rows));
        result.put("batchCount", Long.valueOf(batches));
        result.put("digest", digest);
        result.put("verification", verification);
        return result;
    }

    private static Map<String, Object> error(String code) {
        LinkedHashMap<String, Object> detail = map();
        detail.put("code", code);
        detail.put("message", "Errore sintetico.");
        LinkedHashMap<String, Object> result = map();
        result.put("apiVersion", "1.0");
        result.put("error", detail);
        return result;
    }

    private static List<Object> rows(List<PatologiaCanonicalizer.Patologia> rows) {
        ArrayList<Object> result = new ArrayList<Object>();
        for (PatologiaCanonicalizer.Patologia row : rows) {
            LinkedHashMap<String, Object> value = map();
            value.put("cod", row.cod);
            value.put("nome", row.nome);
            value.put("criticita", Long.valueOf(row.criticita));
            result.add(value);
        }
        return result;
    }

    private static LinkedHashMap<String, Object> map() {
        return new LinkedHashMap<String, Object>();
    }

    private static long longValue(Map<String, Object> body, String key) {
        return ((Long) body.get(key)).longValue();
    }

    private static void exactKeys(Map<String, Object> body, String... keys) {
        check(body.keySet().equals(new java.util.LinkedHashSet<String>(Arrays.asList(keys))),
                "Campi richiesta inattesi.");
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

    private interface BodyCheck {
        void verify(Map<String, Object> body);
    }

    private static final class FakeTransport implements HttpTransport {
        private final List<Step> steps = new ArrayList<Step>();
        private int current;

        private void response(String method, String url, int status, Map<String, Object> body) {
            response(method, url, status, body, null);
        }

        private void response(
                String method, String url, int status, Map<String, Object> body, BodyCheck bodyCheck) {
            steps.add(new Step(method, url, new Response(status, Json.stringify(body)), null, bodyCheck));
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
