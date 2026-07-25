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

/** Servlet-independent resilient HTTP orchestrator for the complete dataset. */
public final class MigrationOrchestrator {
    private static final String API_VERSION = "1.0";
    private static final String EMPTY_DIGEST =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
    private static final Pattern CURSOR =
            Pattern.compile("[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+");
    private static final Pattern ERROR_CODE =
            Pattern.compile("[A-Z][A-Z0-9_]{0,63}");

    private final MigrationConfig config;
    private final HttpTransport transport;

    public MigrationOrchestrator(MigrationConfig config, HttpTransport transport) {
        if (config == null || transport == null) throw new IllegalArgumentException("Dipendenza mancante.");
        this.config = config;
        this.transport = transport;
    }

    public Result migrate(String migrationId) {
        String normalizedMigrationId = normalizeMigrationId(migrationId);
        Manifest manifest = readManifest();
        String currentEntity = EntitySchemas.names().get(0);
        boolean initialized = false;
        try {
            initializeMigration(normalizedMigrationId, manifest);
            initialized = true;
            MigrationState state = readState(normalizedMigrationId, manifest);
            rejectFatalState(state);
            int limit = Math.min(config.batchSize, manifest.maxBatchSize);
            ArrayList<EntityResult> results = new ArrayList<EntityResult>();
            for (EntitySchema schema : EntitySchemas.ordered()) {
                currentEntity = schema.name;
                EntityState checkpoint = state.entity(schema.name);
                if (checkpoint.status.equals("completed")) {
                    results.add(new EntityResult(
                            schema.name,
                            checkpoint.rowsImported,
                            checkpoint.nextBatchSequence,
                            checkpoint.expectedDigest));
                    continue;
                }
                results.add(migrateEntity(
                        normalizedMigrationId,
                        manifest,
                        manifest.entity(schema.name),
                        schema,
                        limit,
                        checkpoint,
                        schema.name.equals(EntitySchemas.names().get(
                                EntitySchemas.names().size() - 1))));
            }

            verifyManifestUnchanged(manifest);
            MigrationState finalState = readState(normalizedMigrationId, manifest);
            if (!"completed".equals(finalState.status)) {
                throw localContract("Lo stato globale non conferma il completamento.");
            }
            for (EntityState entity : finalState.entities) {
                if (!"completed".equals(entity.status)) {
                    throw localContract("Una entita locale non risulta completata.");
                }
            }
            return resultFromState(finalState);
        } catch (MigrationException error) {
            if (initialized) {
                recordFailureSafely(
                        normalizedMigrationId, manifest.datasetId, currentEntity, error);
            }
            throw error;
        }
    }

    /** Strict local status proxy used by both Servlet adapters. */
    public MigrationState status(String migrationId) {
        return readState(normalizeMigrationId(migrationId), null);
    }

    private Result resultFromState(MigrationState state) {
        ArrayList<EntityResult> results = new ArrayList<EntityResult>();
        long totalRows = 0L;
        long totalBatches = 0L;
        for (EntityState entity : state.entities) {
            EntityResult result = new EntityResult(
                    entity.entity,
                    entity.rowsImported,
                    entity.nextBatchSequence,
                    entity.expectedDigest);
            results.add(result);
            totalRows = addExact(totalRows, result.rowCount);
            totalBatches = addExact(totalBatches, result.batchCount);
        }
        return new Result(
                state.migrationId,
                state.datasetId,
                state.status,
                results,
                totalRows,
                totalBatches);
    }

    private EntityResult migrateEntity(
            String migrationId,
            Manifest manifest,
            EntityManifest entityManifest,
            EntitySchema schema,
            int limit,
            EntityState checkpoint,
            boolean finalEntity) {
        int importedRows = checkpoint.rowsImported;
        int batchSequence = checkpoint.nextBatchSequence;
        String cursor = checkpoint.hasMore ? checkpoint.nextCursor : null;
        EntityCanonicalizer.Key previous = checkpoint.lastKey;
        boolean completeDigestAvailable = importedRows == 0;
        MessageDigest completeDigest = EntityCanonicalizer.newSha256();
        Set<String> seenCursors = new HashSet<String>();

        if (importedRows == entityManifest.rowCount && !checkpoint.hasMore) {
            if (completeDigestAvailable
                    && entityManifest.rowCount == 0
                    && !EMPTY_DIGEST.equals(EntityCanonicalizer.hex(completeDigest.digest()))) {
                throw remoteContract("Il digest vuoto non e disponibile.");
            }
            if (finalEntity) verifyManifestUnchanged(manifest);
            finalizeMigration(migrationId, manifest, entityManifest, batchSequence);
            return new EntityResult(
                    schema.name, importedRows, batchSequence, entityManifest.digest);
        }
        if (importedRows > 0 && !checkpoint.hasMore) {
            throw localContract("Il checkpoint sorgente termina prima del conteggio atteso.");
        }

        do {
            Page page = readPage(
                    manifest, entityManifest, schema, cursor, limit, previous);
            if (completeDigestAvailable) {
                completeDigest.update(EntityCanonicalizer.canonicalBytes(schema, page.rows));
            }
            importedRows = addExact(importedRows, page.rows.size());
            if (importedRows > entityManifest.rowCount) {
                throw remoteContract("Il conteggio esportato supera il manifest.");
            }
            if (!page.rows.isEmpty()) {
                sendBatch(
                        migrationId,
                        manifest,
                        entityManifest,
                        schema,
                        batchSequence,
                        cursor,
                        page);
                batchSequence = addExact(batchSequence, 1);
                previous = EntityCanonicalizer.keyOf(
                        schema, page.rows.get(page.rows.size() - 1));
            }
            if (page.hasMore) {
                if (importedRows == entityManifest.rowCount
                        || !seenCursors.add(page.nextCursor)) {
                    throw remoteContract("La continuazione remota non e coerente.");
                }
                cursor = page.nextCursor;
            } else {
                cursor = null;
            }
        } while (cursor != null);

        if (importedRows != entityManifest.rowCount) {
            throw remoteContract("Il conteggio esportato non coincide con il manifest.");
        }
        if (completeDigestAvailable) {
            String completeHex = EntityCanonicalizer.hex(completeDigest.digest());
            if (!completeHex.equals(entityManifest.digest)) {
                throw remoteContract("Il digest esportato non coincide con il manifest.");
            }
        }
        if (finalEntity) verifyManifestUnchanged(manifest);
        finalizeMigration(migrationId, manifest, entityManifest, batchSequence);
        return new EntityResult(
                schema.name, importedRows, batchSequence, entityManifest.digest);
    }

    private Manifest readManifest() {
        try {
            HttpTransport.Response response = execute(
                    "remote", "GET", config.remoteBaseUrl + "/api/v1/manifest",
                    authorization(config.remoteSecret), null, true);
            Map<String, Object> body = successfulObject("remote", response, 200);
            exactFields(
                    body, "apiVersion", "datasetId", "generatedAt",
                    "entityOrder", "entities", "maxBatchSize");
            apiVersion(body);
            String datasetId = digest(body, "datasetId");
            validateGeneratedAt(nonEmptyString(body, "generatedAt"));
            List<EntitySchema> schemas = EntitySchemas.ordered();
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
                descriptors.add(new DatasetIdentity.Descriptor(
                        schema.name, rowCount, entityDigest));
            }
            if (!datasetId.equals(DatasetIdentity.sha256(descriptors))) {
                throw remoteContract("Dataset e descrittori del manifest non coincidono.");
            }
            return new Manifest(
                    datasetId,
                    entityManifests,
                    integer(body, "maxBatchSize", 1, 100));
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "REMOTE_CONTRACT_ERROR", 502,
                    "Il servizio remoto ha restituito un manifest non valido.",
                    false, error);
        }
    }

    private void verifyManifestUnchanged(Manifest expected) {
        if (!expected.sameSnapshot(readManifest())) {
            throw new MigrationException(
                    "REMOTE_DATASET_CHANGED", 409,
                    "Il dataset remoto e cambiato durante la migrazione.");
        }
    }

    private void initializeMigration(String migrationId, Manifest manifest) {
        LinkedHashMap<String, Object> request = new LinkedHashMap<String, Object>();
        request.put("apiVersion", API_VERSION);
        request.put("datasetId", manifest.datasetId);
        request.put("entityOrder", new ArrayList<String>(EntitySchemas.names()));
        ArrayList<Object> entities = new ArrayList<Object>();
        for (EntityManifest entity : manifest.entities) {
            LinkedHashMap<String, Object> descriptor = new LinkedHashMap<String, Object>();
            descriptor.put("entity", entity.entity);
            descriptor.put("rowCount", Long.valueOf(entity.rowCount));
            descriptor.put("digest", entity.digest);
            entities.add(descriptor);
        }
        request.put("entities", entities);
        HttpTransport.Response response = execute(
                "local", "POST",
                config.localBaseUrl + "/api/v1/migrations/" + migrationId,
                authorization(config.localSecret), Json.stringify(request), true);
        if (response.status != 200 && response.status != 201) {
            if (response.status == 409) {
                throw new MigrationException(
                        "LOCAL_CONFLICT", 409,
                        "Il servizio locale ha rifiutato il manifest per conflitto.");
            }
            throw upstreamStatus("local", response.status);
        }
        try {
            Map<String, Object> body = jsonObject("local", response);
            exactFields(
                    body, "apiVersion", "migrationId", "datasetId", "status", "idempotent");
            apiVersion(body);
            boolean idempotent = bool(body, "idempotent");
            if (!migrationId.equals(string(body, "migrationId"))
                    || !manifest.datasetId.equals(string(body, "datasetId"))
                    || !globalStatus(string(body, "status"))
                    || (response.status == 200 && !idempotent)
                    || (response.status == 201 && idempotent)) {
                throw localContract("Il servizio locale non ha confermato l'inizializzazione.");
            }
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "LOCAL_CONTRACT_ERROR", 502,
                    "La risposta di inizializzazione locale non e valida.",
                    false, error);
        }
    }

    private MigrationState readState(String migrationId, Manifest manifest) {
        HttpTransport.Response response = execute(
                "local", "GET",
                config.localBaseUrl + "/api/v1/migrations/" + migrationId,
                authorization(config.localSecret), null, true);
        if (response.status != 200) throw upstreamStatus("local", response.status);
        try {
            Map<String, Object> body = jsonObject("local", response);
            exactFields(
                    body, "apiVersion", "migrationId", "datasetId", "entity",
                    "status", "rowsImported", "totalExpected", "batchesImported",
                    "lastBatchSequence", "lastError", "currentEntity",
                    "recoverable", "entities");
            apiVersion(body);
            if (!migrationId.equals(string(body, "migrationId"))) {
                throw localContract("Lo stato appartiene a una migrazione diversa.");
            }
            String datasetId = digest(body, "datasetId");
            if (manifest != null && !manifest.datasetId.equals(datasetId)) {
                throw new MigrationException(
                        "REMOTE_DATASET_CHANGED", 409,
                        "Lo stato locale appartiene a un dataset diverso.");
            }
            String status = string(body, "status");
            if (!globalStatus(status)) throw new IllegalArgumentException("Stato globale non valido.");
            String currentEntity = string(body, "currentEntity");
            if (!EntitySchemas.names().contains(currentEntity)
                    || !currentEntity.equals(string(body, "entity"))) {
                throw new IllegalArgumentException("Entita corrente non valida.");
            }
            long aggregateRows = nonNegativeLong(body, "rowsImported");
            long aggregateExpected = nonNegativeLong(body, "totalExpected");
            long aggregateBatches = nonNegativeLong(body, "batchesImported");
            Integer aggregateLastSequence = nullableInteger(
                    body, "lastBatchSequence", 0, Integer.MAX_VALUE);
            String aggregateLastError = nullableString(body, "lastError");
            if (aggregateLastError != null
                    && !ERROR_CODE.matcher(aggregateLastError).matches()) {
                throw new IllegalArgumentException("Codice errore globale non valido.");
            }
            Boolean recoverable = nullableBoolean(body, "recoverable");
            if ("interrupted".equals(status) && !Boolean.TRUE.equals(recoverable)) {
                throw new IllegalArgumentException("Interruzione senza classe recuperabile.");
            }
            if ("failed".equals(status) && Boolean.TRUE.equals(recoverable)) {
                throw new IllegalArgumentException("Fallimento definitivo dichiarato recuperabile.");
            }

            List<Object> rawEntities = list(body, "entities");
            if (rawEntities.size() != EntitySchemas.ordered().size()) {
                throw new IllegalArgumentException("Checkpoint entita incompleti.");
            }
            ArrayList<EntityState> states = new ArrayList<EntityState>();
            ArrayList<DatasetIdentity.Descriptor> descriptors =
                    new ArrayList<DatasetIdentity.Descriptor>();
            long expectedRows = 0L;
            long importedRows = 0L;
            long importedBatches = 0L;
            for (int index = 0; index < EntitySchemas.ordered().size(); index++) {
                EntitySchema schema = EntitySchemas.ordered().get(index);
                EntityState entity = parseEntityState(schema, object(rawEntities.get(index)));
                if (manifest != null) {
                    EntityManifest expected = manifest.entity(schema.name);
                    if (entity.expectedRowCount != expected.rowCount
                            || !entity.expectedDigest.equals(expected.digest)) {
                        throw new MigrationException(
                                "REMOTE_DATASET_CHANGED", 409,
                                "Il checkpoint locale usa descrittori diversi.");
                    }
                }
                states.add(entity);
                descriptors.add(new DatasetIdentity.Descriptor(
                        entity.entity, entity.expectedRowCount, entity.expectedDigest));
                expectedRows = addExact(expectedRows, entity.expectedRowCount);
                importedRows = addExact(importedRows, entity.rowsImported);
                importedBatches = addExact(
                        importedBatches, entity.nextBatchSequence);
            }
            if (!datasetId.equals(DatasetIdentity.sha256(descriptors))) {
                throw new IllegalArgumentException("Identita globale del checkpoint non valida.");
            }
            EntityState current = states.get(EntitySchemas.names().indexOf(currentEntity));
            if (aggregateExpected != expectedRows
                    || aggregateRows != importedRows
                    || aggregateBatches != importedBatches
                    || !sameNullable(
                    aggregateLastSequence, current.lastBatchSequence)
                    || !sameNullable(aggregateLastError, current.lastError)) {
                throw new IllegalArgumentException("Aggregati dello stato non validi.");
            }
            if ("completed".equals(status)) {
                for (EntityState entity : states) {
                    if (!"completed".equals(entity.status)) {
                        throw new IllegalArgumentException("Stato globale completato incoerente.");
                    }
                }
            }
            return new MigrationState(
                    migrationId, datasetId, status, currentEntity,
                    aggregateRows, aggregateExpected, aggregateBatches,
                    aggregateLastSequence, aggregateLastError,
                    recoverable, states);
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "LOCAL_CONTRACT_ERROR", 502,
                    "Il servizio locale ha restituito uno stato non valido.",
                    false, error);
        }
    }

    private EntityState parseEntityState(
            EntitySchema schema, Map<String, Object> body) {
        exactFields(
                body, "entity", "status", "expectedRowCount", "expectedDigest",
                "rowsImported", "nextBatchSequence", "lastBatchSequence",
                "sourceCursor", "nextCursor", "hasMore", "lastKey", "lastError");
        if (!schema.name.equals(string(body, "entity"))) {
            throw new IllegalArgumentException("Ordine checkpoint non valido.");
        }
        String status = string(body, "status");
        if (!entityStatus(status)) throw new IllegalArgumentException("Stato entita non valido.");
        int expectedRows = integer(body, "expectedRowCount", 0, Integer.MAX_VALUE);
        String expectedDigest = digest(body, "expectedDigest");
        if (expectedRows == 0 && !EMPTY_DIGEST.equals(expectedDigest)) {
            throw new IllegalArgumentException("Digest entita vuota non valido.");
        }
        int rowsImported = integer(body, "rowsImported", 0, expectedRows);
        int nextSequence = integer(body, "nextBatchSequence", 0, Integer.MAX_VALUE);
        Integer lastSequence = nullableInteger(body, "lastBatchSequence", 0, Integer.MAX_VALUE);
        String sourceCursor = nullableCursor(body, "sourceCursor");
        String nextCursor = nullableCursor(body, "nextCursor");
        boolean hasMore = bool(body, "hasMore");
        if (hasMore != (nextCursor != null)) {
            throw new IllegalArgumentException("Cursore checkpoint incoerente.");
        }
        List<Object> rawLastKey = list(body, "lastKey");
        EntityCanonicalizer.Key lastKey = null;
        if (nextSequence == 0) {
            if (rowsImported != 0 || lastSequence != null || sourceCursor != null
                    || nextCursor != null || hasMore || !rawLastKey.isEmpty()) {
                throw new IllegalArgumentException("Checkpoint iniziale non valido.");
            }
        } else {
            if (lastSequence == null || lastSequence.intValue() != nextSequence - 1
                    || rowsImported == 0) {
                throw new IllegalArgumentException("Sequenza checkpoint non valida.");
            }
            lastKey = EntityCanonicalizer.validateKey(schema, rawLastKey);
        }
        if (rowsImported == expectedRows && hasMore) {
            throw new IllegalArgumentException("Checkpoint oltre il conteggio atteso.");
        }
        if (rowsImported < expectedRows && nextSequence > 0 && !hasMore) {
            throw new IllegalArgumentException("Checkpoint terminale incompleto.");
        }
        if ("completed".equals(status)
                && (rowsImported != expectedRows || hasMore || nextCursor != null)) {
            throw new IllegalArgumentException("Entita completata con checkpoint incoerente.");
        }
        String lastError = nullableString(body, "lastError");
        if (lastError != null && !ERROR_CODE.matcher(lastError).matches()) {
            throw new IllegalArgumentException("Codice errore checkpoint non valido.");
        }
        return new EntityState(
                schema.name, status, expectedRows, expectedDigest, rowsImported,
                nextSequence, lastSequence, sourceCursor, nextCursor, hasMore,
                rawLastKey, lastKey, lastError);
    }

    private Page readPage(
            Manifest manifest,
            EntityManifest entityManifest,
            EntitySchema schema,
            String requestedCursor,
            int limit,
            EntityCanonicalizer.Key previous) {
        StringBuilder url = new StringBuilder(config.remoteBaseUrl)
                .append("/api/v1/export/").append(schema.name)
                .append("?limit=").append(limit)
                .append("&datasetId=").append(manifest.datasetId);
        if (requestedCursor != null) url.append("&cursor=").append(urlEncode(requestedCursor));
        HttpTransport.Response response = execute(
                "remote", "GET", url.toString(),
                authorization(config.remoteSecret), null, true);
        Map<String, Object> body = successfulObject("remote", response, 200);
        try {
            exactFields(body, "apiVersion", "datasetId", "entity", "cursor", "nextCursor",
                    "hasMore", "rowCount", "rows", "digest");
            apiVersion(body);
            if (!manifest.datasetId.equals(string(body, "datasetId"))) {
                throw new MigrationException(
                        "REMOTE_DATASET_CHANGED", 409,
                        "Il dataset remoto e cambiato durante la migrazione.");
            }
            if (!schema.name.equals(string(body, "entity"))) {
                throw remoteContract("Entita export non valida.");
            }
            String echoedCursor = nullableString(body, "cursor");
            if (requestedCursor == null
                    ? echoedCursor != null
                    : !requestedCursor.equals(echoedCursor)) {
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
            EntityCanonicalizer.Row priorRow = null;
            for (Object rawRow : rawRows) {
                EntityCanonicalizer.Row row = EntityCanonicalizer.validate(schema, rawRow);
                if ((priorRow == null && previous != null
                        && EntityCanonicalizer.compare(schema, previous, row) >= 0)
                        || (priorRow != null
                        && EntityCanonicalizer.compare(schema, priorRow, row) >= 0)) {
                    throw remoteContract(
                            "Le righe non sono strettamente ordinate per chiave completa.");
                }
                rows.add(row);
                priorRow = row;
            }
            String declaredDigest = digest(body, "digest");
            if (!EntityCanonicalizer.sha256(schema, rows).equals(declaredDigest)) {
                throw remoteContract("Il digest della pagina non coincide.");
            }
            if (hasMore) {
                if (rows.isEmpty() || !validCursor(nextCursor)
                        || nextCursor.equals(requestedCursor)) {
                    throw remoteContract("La continuazione della pagina non e valida.");
                }
            } else if (nextCursor != null) {
                throw remoteContract("La pagina terminale contiene un cursore successivo.");
            }
            if (rows.isEmpty() && entityManifest.rowCount != 0) {
                throw remoteContract("Pagina vuota inattesa.");
            }
            return new Page(rows, declaredDigest, hasMore, nextCursor);
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "REMOTE_CONTRACT_ERROR", 502,
                    "Il servizio remoto ha restituito una pagina non valida.",
                    false, error);
        }
    }

    private void sendBatch(
            String migrationId,
            Manifest manifest,
            EntityManifest entityManifest,
            EntitySchema schema,
            int sequence,
            String sourceCursor,
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
        request.put("sourceCursor", sourceCursor);
        request.put("nextCursor", page.nextCursor);
        request.put("hasMore", Boolean.valueOf(page.hasMore));
        HttpTransport.Response response = execute(
                "local", "POST",
                config.localBaseUrl + "/api/v1/migrations/" + migrationId + "/batches",
                authorization(config.localSecret), Json.stringify(request), true);
        if (response.status != 200 && response.status != 201) {
            if (response.status == 409) {
                throw new MigrationException(
                        "LOCAL_CONFLICT", 409,
                        "Il servizio locale ha rifiutato il lotto per conflitto.");
            }
            throw upstreamStatus("local", response.status);
        }
        try {
            Map<String, Object> body = jsonObject("local", response);
            exactFields(
                    body, "apiVersion", "migrationId", "datasetId", "entity",
                    "batchSequence", "rowCount", "digest", "idempotent", "status",
                    "sourceCursor", "nextCursor", "hasMore");
            apiVersion(body);
            if (!migrationId.equals(string(body, "migrationId"))
                    || !manifest.datasetId.equals(string(body, "datasetId"))
                    || !schema.name.equals(string(body, "entity"))
                    || sequence != integer(body, "batchSequence", 0, Integer.MAX_VALUE)
                    || page.rows.size() != integer(body, "rowCount", 0, Integer.MAX_VALUE)
                    || !page.digest.equals(digest(body, "digest"))
                    || !sameNullable(sourceCursor, nullableString(body, "sourceCursor"))
                    || !sameNullable(page.nextCursor, nullableString(body, "nextCursor"))
                    || page.hasMore != bool(body, "hasMore")) {
                throw localContract("Il servizio locale non ha confermato il lotto.");
            }
            boolean idempotent = bool(body, "idempotent");
            if ((response.status == 200 && !idempotent)
                    || (response.status == 201 && idempotent)) {
                throw localContract("Lo stato idempotente del lotto non coincide.");
            }
            String status = string(body, "status");
            if (!"running".equals(status)
                    && !("completed".equals(status) && idempotent)) {
                throw localContract("Stato locale inatteso dopo il lotto.");
            }
        } catch (MigrationException error) {
            throw error;
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    "LOCAL_CONTRACT_ERROR", 502,
                    "Il servizio locale ha restituito un contratto lotto non valido.",
                    false, error);
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
                authorization(config.localSecret), Json.stringify(request), true);
        if (response.status != 200) {
            if (response.status == 409) {
                throw new MigrationException(
                        "LOCAL_FINALIZE_CONFLICT", 409,
                        "La migrazione locale non e completa.");
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
                    || entityManifest.rowCount
                    != integer(body, "rowCount", 0, Integer.MAX_VALUE)
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
                    "Il servizio locale ha restituito una finalizzazione non valida.",
                    false, error);
        }
    }

    private void recordFailureSafely(
            String migrationId,
            String datasetId,
            String entity,
            MigrationException failure) {
        try {
            LinkedHashMap<String, Object> request = new LinkedHashMap<String, Object>();
            request.put("apiVersion", API_VERSION);
            request.put("datasetId", datasetId);
            request.put("entity", entity);
            request.put("errorCode", failure.code);
            request.put("recoverable", Boolean.valueOf(failure.recoverable));
            HttpTransport.Response response = execute(
                    "local", "POST",
                    config.localBaseUrl + "/api/v1/migrations/" + migrationId + "/failure",
                    authorization(config.localSecret), Json.stringify(request), true);
            if (response.status != 200) return;
            Map<String, Object> body = jsonObject("local", response);
            exactFields(
                    body, "apiVersion", "migrationId", "datasetId", "status",
                    "currentEntity", "lastError", "recoverable");
            apiVersion(body);
            String expectedStatus = failure.recoverable ? "interrupted" : "failed";
            if (!migrationId.equals(string(body, "migrationId"))
                    || !datasetId.equals(string(body, "datasetId"))
                    || !expectedStatus.equals(string(body, "status"))
                    || !entity.equals(string(body, "currentEntity"))
                    || !failure.code.equals(string(body, "lastError"))
                    || failure.recoverable != bool(body, "recoverable")) {
                return;
            }
        } catch (RuntimeException ignored) {
            // Failure reporting must never replace the original migration error.
        }
    }

    private void rejectFatalState(MigrationState state) {
        if ("failed".equals(state.status)) {
            throw new MigrationException(
                    "LOCAL_MIGRATION_FAILED", 409,
                    "La migrazione locale e in stato definitivo.");
        }
        if ("interrupted".equals(state.status) && !Boolean.TRUE.equals(state.recoverable)) {
            throw localContract("La migrazione interrotta non e recuperabile.");
        }
    }

    private HttpTransport.Response execute(
            String service,
            String method,
            String url,
            Map<String, String> headers,
            String body,
            boolean idempotent) {
        int attempt = 0;
        while (true) {
            try {
                HttpTransport.Response response = transport.execute(
                        method, url, headers, body,
                        config.connectTimeoutMs, config.readTimeoutMs);
                if (idempotent && retryableStatus(response.status)) {
                    if (attempt < config.maxRetries) {
                        attempt++;
                        retryPause();
                        continue;
                    }
                    throw new MigrationException(
                            service.toUpperCase(Locale.ROOT) + "_TEMPORARY_ERROR",
                            503,
                            "Il servizio " + service + " ha esaurito i tentativi.",
                            true);
                }
                return response;
            } catch (MigrationException error) {
                if (idempotent
                        && ("HTTP_TIMEOUT".equals(error.code)
                        || "HTTP_UNAVAILABLE".equals(error.code))) {
                    if (attempt < config.maxRetries) {
                        attempt++;
                        retryPause();
                        continue;
                    }
                    String suffix = "HTTP_TIMEOUT".equals(error.code)
                            ? "_TIMEOUT" : "_UNAVAILABLE";
                    int status = "HTTP_TIMEOUT".equals(error.code) ? 504 : 502;
                    throw new MigrationException(
                            service.toUpperCase(Locale.ROOT) + suffix,
                            status,
                            "Il servizio " + service + " non e raggiungibile.",
                            true,
                            error);
                }
                throw error;
            }
        }
    }

    private void retryPause() {
        if (config.retryDelayMs == 0) return;
        try {
            Thread.sleep(config.retryDelayMs);
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new MigrationException(
                    "RETRY_INTERRUPTED", 503,
                    "La migrazione e stata interrotta durante un retry.",
                    true,
                    error);
        }
    }

    private static boolean retryableStatus(int status) {
        return status == 408 || status == 429 || status == 500
                || status == 502 || status == 503 || status == 504;
    }

    private static Map<String, Object> successfulObject(
            String service, HttpTransport.Response response, int expectedStatus) {
        if (response.status != expectedStatus) throw upstreamStatus(service, response.status);
        return jsonObject(service, response);
    }

    private static Map<String, Object> jsonObject(
            String service, HttpTransport.Response response) {
        if (!jsonUtf8(response.contentType)) {
            throw contract(service, "Content-Type JSON UTF-8 mancante.");
        }
        try {
            return object(Json.parse(response.body));
        } catch (IllegalArgumentException error) {
            throw new MigrationException(
                    service.toUpperCase(Locale.ROOT) + "_CONTRACT_ERROR", 502,
                    "Il servizio " + service + " ha restituito JSON non valido.",
                    false, error);
        }
    }

    private static boolean jsonUtf8(String contentType) {
        String[] parts = contentType.split(";");
        if (parts.length < 2
                || !"application/json".equals(
                parts[0].trim().toLowerCase(Locale.ROOT))) {
            return false;
        }
        boolean utf8 = false;
        for (int index = 1; index < parts.length; index++) {
            String part = parts[index].trim();
            int separator = part.indexOf('=');
            if (separator < 1) continue;
            if ("charset".equals(
                    part.substring(0, separator).trim().toLowerCase(Locale.ROOT))) {
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
        if (status == 404 && "local".equals(service)) {
            return new MigrationException(
                    "MIGRATION_NOT_FOUND", 404, "Migrazione non trovata.");
        }
        if (status == 409 && "remote".equals(service)) {
            return new MigrationException(
                    "REMOTE_DATASET_CHANGED", 409,
                    "Il dataset remoto e cambiato durante la migrazione.");
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

    private static String nullableCursor(Map<String, Object> value, String key) {
        String cursor = nullableString(value, key);
        if (cursor != null && !validCursor(cursor)) {
            throw new IllegalArgumentException("Cursore checkpoint non valido.");
        }
        return cursor;
    }

    private static boolean bool(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof Boolean)) throw new IllegalArgumentException("Booleano JSON richiesto.");
        return ((Boolean) item).booleanValue();
    }

    private static Boolean nullableBoolean(Map<String, Object> value, String key) {
        if (!value.containsKey(key)) throw new IllegalArgumentException("Campo JSON mancante.");
        Object item = value.get(key);
        if (item == null) return null;
        if (!(item instanceof Boolean)) throw new IllegalArgumentException("Booleano JSON richiesto.");
        return (Boolean) item;
    }

    private static int integer(
            Map<String, Object> value, String key, int minimum, int maximum) {
        Object item = value.get(key);
        if (!(item instanceof Long)) throw new IllegalArgumentException("Intero JSON richiesto.");
        long number = ((Long) item).longValue();
        if (number < minimum || number > maximum) {
            throw new IllegalArgumentException("Intero JSON fuori limite.");
        }
        return (int) number;
    }

    private static long nonNegativeLong(
            Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof Long) || ((Long) item).longValue() < 0L) {
            throw new IllegalArgumentException("Intero JSON non negativo richiesto.");
        }
        return ((Long) item).longValue();
    }

    private static Integer nullableInteger(
            Map<String, Object> value, String key, int minimum, int maximum) {
        if (!value.containsKey(key)) throw new IllegalArgumentException("Campo JSON mancante.");
        if (value.get(key) == null) return null;
        return Integer.valueOf(integer(value, key, minimum, maximum));
    }

    private static String digest(Map<String, Object> value, String key) {
        String result = string(value, key);
        if (!result.matches("[0-9a-f]{64}")) {
            throw new IllegalArgumentException("Digest JSON non valido.");
        }
        return result;
    }

    private static boolean validCursor(String cursor) {
        return cursor != null
                && cursor.length() <= 1024
                && CURSOR.matcher(cursor).matches();
    }

    private static boolean sameNullable(String left, String right) {
        return left == null ? right == null : left.equals(right);
    }

    private static boolean sameNullable(Integer left, Integer right) {
        return left == null ? right == null : left.equals(right);
    }

    private static boolean globalStatus(String value) {
        return "created".equals(value) || "running".equals(value)
                || "interrupted".equals(value) || "failed".equals(value)
                || "completed".equals(value);
    }

    private static boolean entityStatus(String value) {
        return "created".equals(value) || "running".equals(value)
                || "failed".equals(value) || "completed".equals(value);
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
                    "INVALID_MIGRATION_ID", 400,
                    "Identificativo migrazione non valido.");
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

        private Manifest(
                String datasetId, List<EntityManifest> entities, int maxBatchSize) {
            this.datasetId = datasetId;
            this.entities = Collections.unmodifiableList(
                    new ArrayList<EntityManifest>(entities));
            LinkedHashMap<String, EntityManifest> index =
                    new LinkedHashMap<String, EntityManifest>();
            for (EntityManifest entity : entities) index.put(entity.entity, entity);
            this.byName = Collections.unmodifiableMap(index);
            this.maxBatchSize = maxBatchSize;
        }

        private EntityManifest entity(String name) {
            EntityManifest value = byName.get(name);
            if (value == null) throw new IllegalArgumentException("Entita manifest mancante.");
            return value;
        }

        private boolean sameSnapshot(Manifest other) {
            if (!datasetId.equals(other.datasetId)
                    || maxBatchSize != other.maxBatchSize
                    || entities.size() != other.entities.size()) {
                return false;
            }
            for (int index = 0; index < entities.size(); index++) {
                EntityManifest left = entities.get(index);
                EntityManifest right = other.entities.get(index);
                if (!left.entity.equals(right.entity)
                        || left.rowCount != right.rowCount
                        || !left.digest.equals(right.digest)) {
                    return false;
                }
            }
            return true;
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

    public static final class EntityState {
        public final String entity;
        public final String status;
        public final int expectedRowCount;
        public final String expectedDigest;
        public final int rowsImported;
        public final int nextBatchSequence;
        public final Integer lastBatchSequence;
        public final String sourceCursor;
        public final String nextCursor;
        public final boolean hasMore;
        public final List<Object> lastKeyValues;
        private final EntityCanonicalizer.Key lastKey;
        public final String lastError;

        private EntityState(
                String entity,
                String status,
                int expectedRowCount,
                String expectedDigest,
                int rowsImported,
                int nextBatchSequence,
                Integer lastBatchSequence,
                String sourceCursor,
                String nextCursor,
                boolean hasMore,
                List<Object> lastKeyValues,
                EntityCanonicalizer.Key lastKey,
                String lastError) {
            this.entity = entity;
            this.status = status;
            this.expectedRowCount = expectedRowCount;
            this.expectedDigest = expectedDigest;
            this.rowsImported = rowsImported;
            this.nextBatchSequence = nextBatchSequence;
            this.lastBatchSequence = lastBatchSequence;
            this.sourceCursor = sourceCursor;
            this.nextCursor = nextCursor;
            this.hasMore = hasMore;
            this.lastKeyValues = Collections.unmodifiableList(
                    new ArrayList<Object>(lastKeyValues));
            this.lastKey = lastKey;
            this.lastError = lastError;
        }

        private Map<String, Object> toJsonObject() {
            LinkedHashMap<String, Object> value = new LinkedHashMap<String, Object>();
            value.put("entity", entity);
            value.put("status", status);
            value.put("expectedRowCount", Long.valueOf(expectedRowCount));
            value.put("expectedDigest", expectedDigest);
            value.put("rowsImported", Long.valueOf(rowsImported));
            value.put("nextBatchSequence", Long.valueOf(nextBatchSequence));
            value.put("lastBatchSequence",
                    lastBatchSequence == null ? null : Long.valueOf(lastBatchSequence));
            value.put("sourceCursor", sourceCursor);
            value.put("nextCursor", nextCursor);
            value.put("hasMore", Boolean.valueOf(hasMore));
            value.put("lastKey", new ArrayList<Object>(lastKeyValues));
            value.put("lastError", lastError);
            return value;
        }
    }

    public static final class MigrationState {
        public final String migrationId;
        public final String datasetId;
        public final String status;
        public final String currentEntity;
        public final long rowsImported;
        public final long totalExpected;
        public final long batchesImported;
        public final Integer lastBatchSequence;
        public final String lastError;
        public final Boolean recoverable;
        public final List<EntityState> entities;
        private final Map<String, EntityState> byName;

        private MigrationState(
                String migrationId,
                String datasetId,
                String status,
                String currentEntity,
                long rowsImported,
                long totalExpected,
                long batchesImported,
                Integer lastBatchSequence,
                String lastError,
                Boolean recoverable,
                List<EntityState> entities) {
            this.migrationId = migrationId;
            this.datasetId = datasetId;
            this.status = status;
            this.currentEntity = currentEntity;
            this.rowsImported = rowsImported;
            this.totalExpected = totalExpected;
            this.batchesImported = batchesImported;
            this.lastBatchSequence = lastBatchSequence;
            this.lastError = lastError;
            this.recoverable = recoverable;
            this.entities = Collections.unmodifiableList(
                    new ArrayList<EntityState>(entities));
            LinkedHashMap<String, EntityState> index =
                    new LinkedHashMap<String, EntityState>();
            for (EntityState entity : entities) index.put(entity.entity, entity);
            this.byName = Collections.unmodifiableMap(index);
        }

        private EntityState entity(String name) {
            EntityState value = byName.get(name);
            if (value == null) throw new IllegalArgumentException("Checkpoint entita mancante.");
            return value;
        }

        public Map<String, Object> toJsonObject() {
            LinkedHashMap<String, Object> value = new LinkedHashMap<String, Object>();
            value.put("apiVersion", API_VERSION);
            value.put("migrationId", migrationId);
            value.put("datasetId", datasetId);
            value.put("entity", currentEntity);
            value.put("status", status);
            value.put("rowsImported", Long.valueOf(rowsImported));
            value.put("totalExpected", Long.valueOf(totalExpected));
            value.put("batchesImported", Long.valueOf(batchesImported));
            value.put("lastBatchSequence",
                    lastBatchSequence == null
                            ? null : Long.valueOf(lastBatchSequence));
            value.put("lastError", lastError);
            value.put("currentEntity", currentEntity);
            value.put("recoverable", recoverable);
            ArrayList<Object> entityValues = new ArrayList<Object>();
            for (EntityState entity : entities) {
                entityValues.add(entity.toJsonObject());
            }
            value.put("entities", entityValues);
            return value;
        }
    }

    public static final class EntityResult {
        public final String entity;
        public final int rowCount;
        public final int batchCount;
        public final String digest;

        private EntityResult(
                String entity, int rowCount, int batchCount, String digest) {
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
            this.entities = Collections.unmodifiableList(
                    new ArrayList<EntityResult>(entities));
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
            for (EntityResult entity : entities) {
                entityValues.add(entity.toJsonObject());
            }
            value.put("entities", entityValues);
            value.put("totalRowCount", Long.valueOf(totalRowCount));
            value.put("totalBatchCount", Long.valueOf(totalBatchCount));
            LinkedHashMap<String, Object> verification =
                    new LinkedHashMap<String, Object>();
            verification.put("rowCountMatches", Boolean.TRUE);
            verification.put("digestMatches", Boolean.TRUE);
            verification.put("constraintsValid", Boolean.TRUE);
            value.put("verification", verification);
            return value;
        }
    }
}
