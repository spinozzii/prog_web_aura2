package it.unibg.driveaura.bridge.core;

import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.format.DateTimeParseException;
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
import java.util.regex.Pattern;

/** Servlet-independent, schema-driven HTTP orchestrator for all entities. */
public final class MigrationOrchestrator {
    private static final String API_VERSION = "1.0";
    private static final String EMPTY_DIGEST =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    private static final Pattern CURSOR =
            Pattern.compile("[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+");

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
        List<EntitySchema> schemas = EntitySchemas.ordered();
        Manifest manifest = readManifest(schemas);
        int limit = Math.min(config.batchSize, manifest.maxBatchSize);
        ArrayList<EntityResult> results = new ArrayList<EntityResult>();
        long totalRows = 0L;
        long totalBatches = 0L;
        for (EntitySchema schema : schemas) {
            EntityResult result = migrateEntity(
                    normalizedMigrationId, manifest, manifest.entity(schema.name), schema, limit);
            results.add(result);
            totalRows = addExact(totalRows, result.rowCount);
            totalBatches = addExact(totalBatches, result.batchCount);
        }
        return new Result(
                normalizedMigrationId,
                manifest.datasetId,
                "completed",
                results,
                totalRows,
                totalBatches);
    }

    private EntityResult migrateEntity(
            String migrationId,
            Manifest manifest,
            EntityManifest entityManifest,
            EntitySchema schema,
            int limit) {
        MessageDigest completeDigest = EntityCanonicalizer.newSha256();
        int importedRows = 0;
        int batchSequence = 0;
        String cursor = null;
        EntityCanonicalizer.Row previous = null;
        Set<String> seenCursors = new HashSet<String>();

        do {
            Page page = readPage(manifest, entityManifest, schema, cursor, limit, previous);
            completeDigest.update(EntityCanonicalizer.canonicalBytes(schema, page.rows));
            importedRows = addExact(importedRows, page.rows.size());
            if (importedRows > entityManifest.rowCount) {
                throw remoteContract("Il conteggio esportato supera il manifest.");
            }
            if (!page.rows.isEmpty()) {
                sendBatch(migrationId, manifest, entityManifest, schema, batchSequence, page);
                batchSequence = addExact(batchSequence, 1);
                previous = page.rows.get(page.rows.size() - 1);
            }
            if (page.hasMore) {
                if (importedRows == entityManifest.rowCount || !seenCursors.add(page.nextCursor)) {
                    throw remoteContract("La continuazione remota non e coerente.");
                }
                cursor = page.nextCursor;
            } else {
                cursor = null;
            }
        } while (cursor != null);

        String completeHex = EntityCanonicalizer.hex(completeDigest.digest());
        if (importedRows != entityManifest.rowCount) {
            throw remoteContract("Il conteggio esportato non coincide con il manifest.");
        }
        if (!completeHex.equals(entityManifest.digest)) {
            throw remoteContract("Il digest esportato non coincide con il manifest.");
        }
        if (entityManifest.rowCount == 0 && !EMPTY_DIGEST.equals(completeHex)) {
            throw remoteContract("Il dataset vuoto non ha il digest atteso.");
        }
        finalizeMigration(migrationId, manifest, entityManifest, batchSequence);
        return new EntityResult(
                schema.name, importedRows, batchSequence, completeHex);
    }

    private Manifest readManifest(List<EntitySchema> schemas) {
        HttpTransport.Response response = execute(
                "remote", "GET", config.remoteBaseUrl + "/api/v1/manifest",
                authorization(config.remoteSecret), null);
        Map<String, Object> body = successfulObject("remote", response, 200);
        exactFields(body, "apiVersion", "datasetId", "generatedAt", "entityOrder", "entities", "maxBatchSize");
        apiVersion(body);
        String datasetId = digest(body, "datasetId");
        validateGeneratedAt(nonEmptyString(body, "generatedAt"));

        List<Object> order = list(body, "entityOrder");
        List<Object> entities = list(body, "entities");
        if (order.size() != schemas.size() || entities.size() != schemas.size()) {
            throw remoteContract("Il manifest non contiene tutte le entita.");
        }
        ArrayList<EntityManifest> entityManifests = new ArrayList<EntityManifest>();
        ArrayList<DatasetIdentity.Descriptor> descriptors =
                new ArrayList<DatasetIdentity.Descriptor>();
        for (int index = 0; index < schemas.size(); index++) {
            EntitySchema schema = schemas.get(index);
            if (!schema.name.equals(order.get(index))) {
                throw remoteContract("L'ordine delle entita del manifest non e valido.");
            }
            Map<String, Object> entity = object(entities.get(index));
            exactFields(entity, "entity", "rowCount", "digest");
            if (!schema.name.equals(string(entity, "entity"))) {
                throw remoteContract("Entita del manifest non valida.");
            }
            int rowCount = integer(entity, "rowCount", 0, Integer.MAX_VALUE);
            String entityDigest = digest(entity, "digest");
            if (rowCount == 0 && !EMPTY_DIGEST.equals(entityDigest)) {
                throw remoteContract("Digest del manifest vuoto non valido.");
            }
            EntityManifest entityManifest =
                    new EntityManifest(schema.name, rowCount, entityDigest);
            entityManifests.add(entityManifest);
            descriptors.add(new DatasetIdentity.Descriptor(schema.name, rowCount, entityDigest));
        }
        if (!datasetId.equals(DatasetIdentity.sha256(descriptors))) {
            throw remoteContract("Dataset e descrittori del manifest non coincidono.");
        }
        return new Manifest(
                datasetId,
                entityManifests,
                integer(body, "maxBatchSize", 1, 100));
    }

    private Page readPage(
            Manifest manifest,
            EntityManifest entityManifest,
            EntitySchema schema,
            String requestedCursor,
            int limit,
            EntityCanonicalizer.Row previous) {
        StringBuilder url = new StringBuilder(config.remoteBaseUrl)
                .append("/api/v1/export/").append(schema.name)
                .append("?limit=").append(limit);
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
        if (!schema.name.equals(string(body, "entity"))) {
            throw remoteContract("Entita export non valida.");
        }
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
        ArrayList<EntityCanonicalizer.Row> rows =
                new ArrayList<EntityCanonicalizer.Row>(rawRows.size());
        EntityCanonicalizer.Row prior = previous;
        for (Object rawRow : rawRows) {
            EntityCanonicalizer.Row row = EntityCanonicalizer.validate(schema, rawRow);
            if (prior != null && EntityCanonicalizer.compare(schema, prior, row) >= 0) {
                throw remoteContract("Le righe non sono strettamente ordinate per chiave completa.");
            }
            rows.add(row);
            prior = row;
        }
        String declaredDigest = digest(body, "digest");
        if (!EntityCanonicalizer.sha256(schema, rows).equals(declaredDigest)) {
            throw remoteContract("Il digest della pagina non coincide.");
        }
        if (hasMore) {
            if (rows.isEmpty() || !validCursor(nextCursor) || nextCursor.equals(requestedCursor)) {
                throw remoteContract("La continuazione della pagina non e valida.");
            }
        } else if (nextCursor != null) {
            throw remoteContract("La pagina terminale contiene un cursore successivo.");
        }
        if (rows.isEmpty() && entityManifest.rowCount != 0) {
            throw remoteContract("Pagina vuota inattesa.");
        }
        return new Page(rows, declaredDigest, hasMore, nextCursor);
    }

    private void sendBatch(
            String migrationId,
            Manifest manifest,
            EntityManifest entityManifest,
            EntitySchema schema,
            int sequence,
            Page page) {
        LinkedHashMap<String, Object> request = new LinkedHashMap<String, Object>();
        request.put("apiVersion", API_VERSION);
        request.put("datasetId", manifest.datasetId);
        request.put("entity", schema.name);
        request.put("batchSequence", Long.valueOf(sequence));
        request.put("rowCount", Long.valueOf(page.rows.size()));
        request.put("rows", rowObjects(page.rows));
        request.put("digest", page.digest);
        request.put("expectedRowCount", Long.valueOf(entityManifest.rowCount));
        request.put("expectedDigest", entityManifest.digest);
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
                    || !schema.name.equals(string(body, "entity"))
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
                    "LOCAL_CONTRACT_ERROR", 502,
                    "Il servizio locale ha restituito un contratto lotto non valido.", error);
        }
    }

    private void finalizeMigration(
            String migrationId,
            Manifest manifest,
            EntityManifest entityManifest,
            int batchCount) {
        LinkedHashMap<String, Object> request = new LinkedHashMap<String, Object>();
        request.put("apiVersion", API_VERSION);
        request.put("datasetId", manifest.datasetId);
        request.put("entity", entityManifest.entity);
        request.put("expectedRowCount", Long.valueOf(entityManifest.rowCount));
        request.put("expectedBatchCount", Long.valueOf(batchCount));
        request.put("expectedDigest", entityManifest.digest);
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
                    || !entityManifest.entity.equals(string(body, "entity"))
                    || !"completed".equals(string(body, "status"))
                    || entityManifest.rowCount != integer(body, "rowCount", 0, Integer.MAX_VALUE)
                    || batchCount != integer(body, "batchCount", 0, Integer.MAX_VALUE)
                    || !entityManifest.digest.equals(digest(body, "digest"))) {
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
                    "LOCAL_CONTRACT_ERROR", 502,
                    "Il servizio locale ha restituito una finalizzazione non valida.", error);
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
                        service.toUpperCase(Locale.ROOT) + "_TIMEOUT", 504,
                        "Il servizio " + service + " non ha risposto entro il timeout.", error);
            }
            if ("HTTP_UNAVAILABLE".equals(error.code)) {
                throw new MigrationException(
                        service.toUpperCase(Locale.ROOT) + "_UNAVAILABLE", 502,
                        "Il servizio " + service + " non e raggiungibile.", error);
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
        if (!jsonUtf8(response.contentType)) {
            throw contract(service, "Content-Type JSON UTF-8 mancante.");
        }
        try {
            return object(Json.parse(response.body));
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    service.toUpperCase(Locale.ROOT) + "_CONTRACT_ERROR", 502,
                    "Il servizio " + service + " ha restituito JSON non valido.", error);
        }
    }

    private static boolean jsonUtf8(String contentType) {
        String[] parts = contentType.split(";");
        if (parts.length < 2 || !"application/json".equals(parts[0].trim().toLowerCase(Locale.ROOT))) {
            return false;
        }
        boolean utf8 = false;
        for (int index = 1; index < parts.length; index++) {
            String part = parts[index].trim();
            int separator = part.indexOf('=');
            if (separator < 1) continue;
            if ("charset".equals(part.substring(0, separator).trim().toLowerCase(Locale.ROOT))) {
                String charset = part.substring(separator + 1).trim().replace("\"", "");
                if (!"utf-8".equals(charset.toLowerCase(Locale.ROOT))) return false;
                utf8 = true;
            }
        }
        return utf8;
    }

    private static MigrationException upstreamStatus(String service, int status) {
        String prefix = service.toUpperCase(Locale.ROOT);
        if (status == 401 || status == 403) {
            return new MigrationException(
                    prefix + "_AUTH_ERROR", 502,
                    "Il servizio " + service + " ha rifiutato l'autenticazione.");
        }
        if (status == 409 && "remote".equals(service)) {
            return new MigrationException(
                    "REMOTE_DATASET_CHANGED", 409, "Il dataset remoto e cambiato durante la migrazione.");
        }
        return new MigrationException(
                prefix + "_HTTP_ERROR", 502,
                "Il servizio " + service + " ha restituito un errore HTTP.");
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

    private static List<Object> rowObjects(List<EntityCanonicalizer.Row> rows) {
        ArrayList<Object> result = new ArrayList<Object>(rows.size());
        for (EntityCanonicalizer.Row row : rows) result.add(row.toJsonObject());
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

    private static boolean validCursor(String cursor) {
        return cursor != null && cursor.length() <= 1024 && CURSOR.matcher(cursor).matches();
    }

    private static void validateGeneratedAt(String value) {
        if (!value.endsWith("Z")) throw new IllegalArgumentException("Timestamp UTC richiesto.");
        try {
            Instant.parse(value);
        } catch (DateTimeParseException error) {
            throw new IllegalArgumentException("Timestamp UTC non valido.", error);
        }
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

    private static int addExact(int left, int right) {
        if (right > 0 && left > Integer.MAX_VALUE - right) {
            throw remoteContract("Conteggio remoto troppo grande.");
        }
        return left + right;
    }

    private static long addExact(long left, long right) {
        if (right > 0L && left > Long.MAX_VALUE - right) {
            throw remoteContract("Conteggio remoto troppo grande.");
        }
        return left + right;
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
        private final List<EntityManifest> entities;
        private final Map<String, EntityManifest> byName;
        private final int maxBatchSize;

        private Manifest(String datasetId, List<EntityManifest> entities, int maxBatchSize) {
            this.datasetId = datasetId;
            this.entities = Collections.unmodifiableList(new ArrayList<EntityManifest>(entities));
            LinkedHashMap<String, EntityManifest> index = new LinkedHashMap<String, EntityManifest>();
            for (EntityManifest entity : entities) index.put(entity.entity, entity);
            this.byName = Collections.unmodifiableMap(index);
            this.maxBatchSize = maxBatchSize;
        }

        private EntityManifest entity(String name) {
            EntityManifest value = byName.get(name);
            if (value == null) throw new IllegalArgumentException("Entita manifest mancante.");
            return value;
        }
    }

    private static final class EntityManifest {
        private final String entity;
        private final int rowCount;
        private final String digest;

        private EntityManifest(String entity, int rowCount, String digest) {
            this.entity = entity;
            this.rowCount = rowCount;
            this.digest = digest;
        }
    }

    private static final class Page {
        private final List<EntityCanonicalizer.Row> rows;
        private final String digest;
        private final boolean hasMore;
        private final String nextCursor;

        private Page(
                List<EntityCanonicalizer.Row> rows,
                String digest,
                boolean hasMore,
                String nextCursor) {
            this.rows = rows;
            this.digest = digest;
            this.hasMore = hasMore;
            this.nextCursor = nextCursor;
        }
    }

    public static final class EntityResult {
        public final String entity;
        public final int rowCount;
        public final int batchCount;
        public final String digest;

        private EntityResult(String entity, int rowCount, int batchCount, String digest) {
            this.entity = entity;
            this.rowCount = rowCount;
            this.batchCount = batchCount;
            this.digest = digest;
        }

        private Map<String, Object> toJsonObject() {
            LinkedHashMap<String, Object> value = new LinkedHashMap<String, Object>();
            value.put("entity", entity);
            value.put("rowCount", Long.valueOf(rowCount));
            value.put("batchCount", Long.valueOf(batchCount));
            value.put("digest", digest);
            return value;
        }
    }

    public static final class Result {
        public final String migrationId;
        public final String datasetId;
        public final String status;
        public final List<EntityResult> entities;
        public final long totalRowCount;
        public final long totalBatchCount;

        private Result(
                String migrationId,
                String datasetId,
                String status,
                List<EntityResult> entities,
                long totalRowCount,
                long totalBatchCount) {
            this.migrationId = migrationId;
            this.datasetId = datasetId;
            this.status = status;
            this.entities = Collections.unmodifiableList(new ArrayList<EntityResult>(entities));
            this.totalRowCount = totalRowCount;
            this.totalBatchCount = totalBatchCount;
        }

        public Map<String, Object> toJsonObject() {
            LinkedHashMap<String, Object> value = new LinkedHashMap<String, Object>();
            value.put("apiVersion", API_VERSION);
            value.put("migrationId", migrationId);
            value.put("datasetId", datasetId);
            value.put("status", status);
            value.put("entityOrder", new ArrayList<String>(EntitySchemas.names()));
            ArrayList<Object> entityValues = new ArrayList<Object>();
            for (EntityResult entity : entities) entityValues.add(entity.toJsonObject());
            value.put("entities", entityValues);
            value.put("totalRowCount", Long.valueOf(totalRowCount));
            value.put("totalBatchCount", Long.valueOf(totalBatchCount));
            LinkedHashMap<String, Object> verification = new LinkedHashMap<String, Object>();
            verification.put("rowCountMatches", Boolean.TRUE);
            verification.put("digestMatches", Boolean.TRUE);
            verification.put("constraintsValid", Boolean.TRUE);
            value.put("verification", verification);
            return value;
        }
    }
}
