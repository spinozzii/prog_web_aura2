package it.unibg.driveaura.bridge.core;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Servlet-independent HTTP orchestrator for the first vertical Patologia
 * migration. It never accesses either database directly.
 */
public final class MigrationOrchestrator {
    private static final String API_VERSION = "1.0";
    private static final String ENTITY = "patologia";
    private static final String EMPTY_DIGEST =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

    private final MigrationConfig config;
    private final HttpTransport transport;

    public MigrationOrchestrator(MigrationConfig config, HttpTransport transport) {
        if (config == null || transport == null) throw new IllegalArgumentException("Dipendenza mancante.");
        this.config = config;
        this.transport = transport;
    }

    public Result migrate(String migrationId) {
        try {
            return migrateValidated(migrationId);
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "REMOTE_CONTRACT_ERROR",
                    502,
                    "Il servizio remoto ha restituito un contratto non valido.",
                    error);
        }
    }

    private Result migrateValidated(String migrationId) {
        String normalizedMigrationId = normalizeMigrationId(migrationId);
        Manifest manifest = readManifest();
        int limit = Math.min(config.batchSize, manifest.maxBatchSize);
        MessageDigest completeDigest = newSha256();
        int importedRows = 0;
        int batchSequence = 0;
        String cursor = null;
        String previousCode = null;
        Set<String> seenCursors = new HashSet<String>();

        do {
            Page page = readPage(manifest, cursor, limit, previousCode);
            byte[] canonical = PatologiaCanonicalizer.canonicalize(page.rows)
                    .getBytes(StandardCharsets.UTF_8);
            completeDigest.update(canonical);
            importedRows += page.rows.size();
            if (importedRows > manifest.rowCount) {
                throw remoteContract("Il conteggio esportato supera il manifest.");
            }

            // The remote service exposes one terminal empty page for an empty dataset,
            // but Django creates that run atomically during finalize with zero batches.
            if (!page.rows.isEmpty()) {
                sendBatch(normalizedMigrationId, manifest, batchSequence, page);
                batchSequence++;
                previousCode = page.rows.get(page.rows.size() - 1).cod;
            }

            if (!page.hasMore) {
                cursor = null;
            } else {
                if (!seenCursors.add(page.nextCursor)) {
                    throw remoteContract("Il cursore remoto forma un ciclo.");
                }
                cursor = page.nextCursor;
            }
        } while (cursor != null);

        String completeHex = hex(completeDigest.digest());
        if (importedRows != manifest.rowCount) {
            throw remoteContract("Il conteggio esportato non coincide con il manifest.");
        }
        if (!completeHex.equals(manifest.digest)) {
            throw remoteContract("Il digest esportato non coincide con il manifest.");
        }
        if (manifest.rowCount == 0 && !EMPTY_DIGEST.equals(completeHex)) {
            throw remoteContract("Il dataset vuoto non ha il digest atteso.");
        }

        finalizeMigration(normalizedMigrationId, manifest, batchSequence);
        return new Result(
                normalizedMigrationId,
                manifest.datasetId,
                ENTITY,
                "completed",
                importedRows,
                batchSequence,
                completeHex);
    }

    private Manifest readManifest() {
        HttpTransport.Response response = execute(
                "remote", "GET", config.remoteBaseUrl + "/api/v1/manifest",
                authorization(config.remoteSecret), null);
        Map<String, Object> body = successfulObject("remote", response, 200);
        exactFields(body, "apiVersion", "datasetId", "generatedAt", "entityOrder", "entities", "maxBatchSize");
        apiVersion(body);
        String datasetId = digest(body, "datasetId");
        nonEmptyString(body, "generatedAt");

        List<Object> order = list(body, "entityOrder");
        if (order.size() != 1 || !ENTITY.equals(order.get(0))) {
            throw remoteContract("L'ordine delle entita del manifest non e supportato.");
        }
        List<Object> entities = list(body, "entities");
        if (entities.size() != 1) {
            throw remoteContract("Il manifest deve contenere solo Patologia.");
        }
        Map<String, Object> entity = object(entities.get(0));
        exactFields(entity, "entity", "rowCount", "digest");
        if (!ENTITY.equals(string(entity, "entity"))) {
            throw remoteContract("Entita del manifest non valida.");
        }
        int rowCount = integer(entity, "rowCount", 0, Integer.MAX_VALUE);
        String digest = digest(entity, "digest");
        int maximum = integer(body, "maxBatchSize", 1, 100);
        if (!datasetId.equals(digest)) {
            throw remoteContract("Dataset e digest del manifest non coincidono.");
        }
        if (rowCount == 0 && !EMPTY_DIGEST.equals(digest)) {
            throw remoteContract("Digest del manifest vuoto non valido.");
        }
        return new Manifest(datasetId, rowCount, digest, maximum);
    }

    private Page readPage(Manifest manifest, String requestedCursor, int limit, String previousCode) {
        StringBuilder url = new StringBuilder(config.remoteBaseUrl)
                .append("/api/v1/export/patologia?limit=").append(limit);
        if (requestedCursor != null) url.append("&cursor=").append(urlEncode(requestedCursor));
        HttpTransport.Response response = execute(
                "remote", "GET", url.toString(), authorization(config.remoteSecret), null);
        Map<String, Object> body = successfulObject("remote", response, 200);
        exactFields(body, "apiVersion", "datasetId", "entity", "cursor", "nextCursor",
                "hasMore", "rowCount", "rows", "digest");
        apiVersion(body);
        if (!manifest.datasetId.equals(string(body, "datasetId"))) {
            throw new MigrationException(
                    "REMOTE_DATASET_CHANGED", 409, "Il dataset remoto e cambiato durante la migrazione.");
        }
        if (!ENTITY.equals(string(body, "entity"))) throw remoteContract("Entita export non valida.");
        String echoedCursor = nullableString(body, "cursor");
        if (requestedCursor == null ? echoedCursor != null : !requestedCursor.equals(echoedCursor)) {
            throw remoteContract("Il servizio remoto non ha confermato il cursore.");
        }

        boolean hasMore = bool(body, "hasMore");
        String nextCursor = nullableString(body, "nextCursor");
        List<Object> rawRows = list(body, "rows");
        int declaredCount = integer(body, "rowCount", 0, limit);
        if (declaredCount != rawRows.size()) {
            throw remoteContract("Il conteggio della pagina non coincide.");
        }

        List<PatologiaCanonicalizer.Patologia> rows =
                new ArrayList<PatologiaCanonicalizer.Patologia>(rawRows.size());
        String prior = previousCode;
        for (Object rawRow : rawRows) {
            Map<String, Object> row = object(rawRow);
            exactFields(row, "cod", "nome", "criticita");
            String code = nonEmptyString(row, "cod");
            if (code.codePointCount(0, code.length()) > 20 || code.indexOf('\0') >= 0) {
                throw remoteContract("Codice Patologia non valido.");
            }
            String name = nonEmptyString(row, "nome");
            if (name.indexOf('\0') >= 0) throw remoteContract("Nome Patologia non valido.");
            int severity = integer(row, "criticita", 1, 5);
            if (prior != null && PatologiaCanonicalizer.compareCodes(prior, code) >= 0) {
                throw remoteContract("Le righe Patologia non sono strettamente ordinate.");
            }
            rows.add(new PatologiaCanonicalizer.Patologia(code, name, severity));
            prior = code;
        }

        String declaredDigest = digest(body, "digest");
        if (!PatologiaCanonicalizer.sha256(rows).equals(declaredDigest)) {
            throw remoteContract("Il digest della pagina non coincide.");
        }
        if (hasMore) {
            if (rows.isEmpty() || nextCursor == null || nextCursor.isEmpty()
                    || nextCursor.equals(requestedCursor)) {
                throw remoteContract("La continuazione della pagina non e valida.");
            }
        } else if (nextCursor != null) {
            throw remoteContract("La pagina terminale contiene un cursore successivo.");
        }
        if (rows.isEmpty() && manifest.rowCount != 0) {
            throw remoteContract("Pagina vuota inattesa.");
        }
        return new Page(rows, declaredDigest, hasMore, nextCursor);
    }

    private void sendBatch(String migrationId, Manifest manifest, int sequence, Page page) {
        LinkedHashMap<String, Object> request = new LinkedHashMap<String, Object>();
        request.put("apiVersion", API_VERSION);
        request.put("datasetId", manifest.datasetId);
        request.put("entity", ENTITY);
        request.put("batchSequence", Long.valueOf(sequence));
        request.put("rowCount", Long.valueOf(page.rows.size()));
        request.put("rows", rowObjects(page.rows));
        request.put("digest", page.digest);
        request.put("expectedRowCount", Long.valueOf(manifest.rowCount));
        request.put("expectedDigest", manifest.digest);
        HttpTransport.Response response = execute(
                "local", "POST",
                config.localBaseUrl + "/api/v1/migrations/" + migrationId + "/batches",
                authorization(config.localSecret), Json.stringify(request));
        if (response.status != 200 && response.status != 201) {
            if (response.status == 409) {
                throw new MigrationException(
                        "LOCAL_CONFLICT", 409, "Il servizio locale ha rifiutato il lotto per conflitto.");
            }
            throw upstreamStatus("local", response.status);
        }
        try {
            Map<String, Object> body = jsonObject("local", response);
            exactFields(body, "apiVersion", "migrationId", "datasetId", "entity", "batchSequence",
                    "rowCount", "digest", "idempotent", "status");
            apiVersion(body);
            if (!migrationId.equals(string(body, "migrationId"))
                    || !manifest.datasetId.equals(string(body, "datasetId"))
                    || !ENTITY.equals(string(body, "entity"))
                    || sequence != integer(body, "batchSequence", 0, Integer.MAX_VALUE)
                    || page.rows.size() != integer(body, "rowCount", 0, Integer.MAX_VALUE)
                    || !page.digest.equals(digest(body, "digest"))) {
                throw localContract("Il servizio locale non ha confermato il lotto.");
            }
            boolean idempotent = bool(body, "idempotent");
            if ((response.status == 200 && !idempotent) || (response.status == 201 && idempotent)) {
                throw localContract("Lo stato idempotente del lotto non coincide.");
            }
            String status = string(body, "status");
            if (!"running".equals(status) && !("completed".equals(status) && idempotent)) {
                throw localContract("Stato locale inatteso dopo il lotto.");
            }
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "LOCAL_CONTRACT_ERROR",
                    502,
                    "Il servizio locale ha restituito un contratto lotto non valido.",
                    error);
        }
    }

    private void finalizeMigration(String migrationId, Manifest manifest, int batchCount) {
        LinkedHashMap<String, Object> request = new LinkedHashMap<String, Object>();
        request.put("apiVersion", API_VERSION);
        request.put("datasetId", manifest.datasetId);
        request.put("entity", ENTITY);
        request.put("expectedRowCount", Long.valueOf(manifest.rowCount));
        request.put("expectedBatchCount", Long.valueOf(batchCount));
        request.put("expectedDigest", manifest.digest);
        HttpTransport.Response response = execute(
                "local", "POST",
                config.localBaseUrl + "/api/v1/migrations/" + migrationId + "/finalize",
                authorization(config.localSecret), Json.stringify(request));
        if (response.status != 200) {
            if (response.status == 409) {
                throw new MigrationException(
                        "LOCAL_FINALIZE_CONFLICT", 409, "La migrazione locale non e completa.");
            }
            throw upstreamStatus("local", response.status);
        }
        try {
            Map<String, Object> body = jsonObject("local", response);
            exactFields(body, "apiVersion", "migrationId", "datasetId", "entity", "status",
                    "rowCount", "batchCount", "digest", "verification");
            apiVersion(body);
            if (!migrationId.equals(string(body, "migrationId"))
                    || !manifest.datasetId.equals(string(body, "datasetId"))
                    || !ENTITY.equals(string(body, "entity"))
                    || !"completed".equals(string(body, "status"))
                    || manifest.rowCount != integer(body, "rowCount", 0, Integer.MAX_VALUE)
                    || batchCount != integer(body, "batchCount", 0, Integer.MAX_VALUE)
                    || !manifest.digest.equals(digest(body, "digest"))) {
                throw localContract("La finalizzazione locale non coincide con il manifest.");
            }
            Map<String, Object> verification = map(body, "verification");
            exactFields(verification, "rowCountMatches", "digestMatches", "constraintsValid");
            if (!bool(verification, "rowCountMatches")
                    || !bool(verification, "digestMatches")
                    || !bool(verification, "constraintsValid")) {
                throw localContract("La verifica finale locale non e riuscita.");
            }
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "LOCAL_CONTRACT_ERROR",
                    502,
                    "Il servizio locale ha restituito una finalizzazione non valida.",
                    error);
        }
    }

    private HttpTransport.Response execute(
            String service, String method, String url, Map<String, String> headers, String body) {
        try {
            return transport.execute(
                    method, url, headers, body, config.connectTimeoutMs, config.readTimeoutMs);
        } catch (MigrationException error) {
            if ("HTTP_TIMEOUT".equals(error.code)) {
                throw new MigrationException(
                        service.toUpperCase(Locale.ROOT) + "_TIMEOUT",
                        504,
                        "Il servizio " + service + " non ha risposto entro il timeout.",
                        error);
            }
            if ("HTTP_UNAVAILABLE".equals(error.code)) {
                throw new MigrationException(
                        service.toUpperCase(Locale.ROOT) + "_UNAVAILABLE",
                        502,
                        "Il servizio " + service + " non e raggiungibile.",
                        error);
            }
            throw error;
        }
    }

    private static Map<String, Object> successfulObject(
            String service, HttpTransport.Response response, int expectedStatus) {
        if (response.status != expectedStatus) throw upstreamStatus(service, response.status);
        return jsonObject(service, response);
    }

    private static Map<String, Object> jsonObject(String service, HttpTransport.Response response) {
        String contentType = response.contentType.toLowerCase(Locale.ROOT).replace(" ", "");
        if (!contentType.startsWith("application/json") || !contentType.contains("charset=utf-8")) {
            throw contract(service, "Content-Type JSON UTF-8 mancante.");
        }
        try {
            return object(Json.parse(response.body));
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    service.toUpperCase(Locale.ROOT) + "_CONTRACT_ERROR",
                    502,
                    "Il servizio " + service + " ha restituito JSON non valido.",
                    error);
        }
    }

    private static MigrationException upstreamStatus(String service, int status) {
        String prefix = service.toUpperCase(Locale.ROOT);
        if (status == 401 || status == 403) {
            return new MigrationException(
                    prefix + "_AUTH_ERROR", 502, "Il servizio " + service + " ha rifiutato l'autenticazione.");
        }
        if (status == 409 && "remote".equals(service)) {
            return new MigrationException(
                    "REMOTE_DATASET_CHANGED", 409, "Il dataset remoto e cambiato durante la migrazione.");
        }
        return new MigrationException(
                prefix + "_HTTP_ERROR", 502, "Il servizio " + service + " ha restituito un errore HTTP.");
    }

    private static MigrationException remoteContract(String message) {
        return new MigrationException("REMOTE_CONTRACT_ERROR", 502, message);
    }

    private static MigrationException localContract(String message) {
        return new MigrationException("LOCAL_CONTRACT_ERROR", 502, message);
    }

    private static MigrationException contract(String service, String message) {
        return "remote".equals(service) ? remoteContract(message) : localContract(message);
    }

    private static Map<String, String> authorization(String secret) {
        return Collections.singletonMap("Authorization", "Bearer " + secret);
    }

    private static List<Object> rowObjects(List<PatologiaCanonicalizer.Patologia> rows) {
        ArrayList<Object> result = new ArrayList<Object>(rows.size());
        for (PatologiaCanonicalizer.Patologia row : rows) {
            LinkedHashMap<String, Object> value = new LinkedHashMap<String, Object>();
            value.put("cod", row.cod);
            value.put("nome", row.nome);
            value.put("criticita", Long.valueOf(row.criticita));
            result.add(value);
        }
        return result;
    }

    private static void apiVersion(Map<String, Object> object) {
        if (!API_VERSION.equals(string(object, "apiVersion"))) {
            throw new IllegalArgumentException("Versione API non valida.");
        }
    }

    private static void exactFields(Map<String, Object> value, String... fields) {
        Set<String> expected = new LinkedHashSet<String>(Arrays.asList(fields));
        if (!value.keySet().equals(expected)) {
            throw new IllegalArgumentException("Campi JSON non validi.");
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> object(Object value) {
        if (!(value instanceof Map)) throw new IllegalArgumentException("Oggetto JSON richiesto.");
        return (Map<String, Object>) value;
    }

    private static Map<String, Object> map(Map<String, Object> value, String key) {
        if (!value.containsKey(key)) throw new IllegalArgumentException("Campo JSON mancante.");
        return object(value.get(key));
    }

    @SuppressWarnings("unchecked")
    private static List<Object> list(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof List)) throw new IllegalArgumentException("Array JSON richiesto.");
        return (List<Object>) item;
    }

    private static String string(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof String)) throw new IllegalArgumentException("Stringa JSON richiesta.");
        return (String) item;
    }

    private static String nonEmptyString(Map<String, Object> value, String key) {
        String item = string(value, key);
        if (item.isEmpty()) throw new IllegalArgumentException("Stringa JSON vuota.");
        return item;
    }

    private static String nullableString(Map<String, Object> value, String key) {
        if (!value.containsKey(key)) throw new IllegalArgumentException("Campo JSON mancante.");
        Object item = value.get(key);
        if (item == null) return null;
        if (!(item instanceof String)) throw new IllegalArgumentException("Stringa JSON richiesta.");
        return (String) item;
    }

    private static boolean bool(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof Boolean)) throw new IllegalArgumentException("Booleano JSON richiesto.");
        return ((Boolean) item).booleanValue();
    }

    private static int integer(Map<String, Object> value, String key, int minimum, int maximum) {
        Object item = value.get(key);
        if (!(item instanceof Long)) throw new IllegalArgumentException("Intero JSON richiesto.");
        long number = ((Long) item).longValue();
        if (number < minimum || number > maximum) {
            throw new IllegalArgumentException("Intero JSON fuori limite.");
        }
        return (int) number;
    }

    private static String digest(Map<String, Object> value, String key) {
        String result = string(value, key);
        if (!result.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("Digest JSON non valido.");
        }
        return result;
    }

    private static String normalizeMigrationId(String migrationId) {
        try {
            UUID value = UUID.fromString(migrationId);
            String normalized = value.toString();
            if (!normalized.equals(migrationId.toLowerCase(Locale.ROOT))) {
                throw new IllegalArgumentException("UUID non canonico.");
            }
            return normalized;
        } catch (RuntimeException error) {
            throw new MigrationException(
                    "INVALID_MIGRATION_ID", 400, "Identificativo migrazione non valido.");
        }
    }

    private static MessageDigest newSha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("SHA-256 non disponibile.", error);
        }
    }

    private static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) result.append(String.format("%02x", value & 0xff));
        return result.toString();
    }

    private static String urlEncode(String value) {
        try {
            return URLEncoder.encode(value, "UTF-8").replace("+", "%20");
        } catch (UnsupportedEncodingException error) {
            throw new IllegalStateException("UTF-8 non disponibile.", error);
        }
    }

    private static final class Manifest {
        private final String datasetId;
        private final int rowCount;
        private final String digest;
        private final int maxBatchSize;

        private Manifest(String datasetId, int rowCount, String digest, int maxBatchSize) {
            this.datasetId = datasetId;
            this.rowCount = rowCount;
            this.digest = digest;
            this.maxBatchSize = maxBatchSize;
        }
    }

    private static final class Page {
        private final List<PatologiaCanonicalizer.Patologia> rows;
        private final String digest;
        private final boolean hasMore;
        private final String nextCursor;

        private Page(
                List<PatologiaCanonicalizer.Patologia> rows,
                String digest,
                boolean hasMore,
                String nextCursor) {
            this.rows = rows;
            this.digest = digest;
            this.hasMore = hasMore;
            this.nextCursor = nextCursor;
        }
    }

    public static final class Result {
        public final String migrationId;
        public final String datasetId;
        public final String entity;
        public final String status;
        public final int rowCount;
        public final int batchCount;
        public final String digest;

        private Result(
                String migrationId,
                String datasetId,
                String entity,
                String status,
                int rowCount,
                int batchCount,
                String digest) {
            this.migrationId = migrationId;
            this.datasetId = datasetId;
            this.entity = entity;
            this.status = status;
            this.rowCount = rowCount;
            this.batchCount = batchCount;
            this.digest = digest;
        }

        public Map<String, Object> toJsonObject() {
            LinkedHashMap<String, Object> value = new LinkedHashMap<String, Object>();
            value.put("apiVersion", API_VERSION);
            value.put("migrationId", migrationId);
            value.put("datasetId", datasetId);
            value.put("entity", entity);
            value.put("status", status);
            value.put("rowCount", Long.valueOf(rowCount));
            value.put("batchCount", Long.valueOf(batchCount));
            value.put("digest", digest);
            LinkedHashMap<String, Object> verification = new LinkedHashMap<String, Object>();
            verification.put("rowCountMatches", Boolean.TRUE);
            verification.put("digestMatches", Boolean.TRUE);
            verification.put("constraintsValid", Boolean.TRUE);
            value.put("verification", verification);
            return value;
        }
    }
}
