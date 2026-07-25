package it.unibg.driveaura.bridge.core;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * Core representation of POST /api/v1/migrations. Servlet adapters only read
 * the HTTP request and write this response.
 */
public final class MigrationEndpoint {
    private static final String API_VERSION = "1.0";

    private final MigrationConfig config;
    private final MigrationOrchestrator orchestrator;

    public MigrationEndpoint(MigrationConfig config, HttpTransport transport) {
        this.config = config;
        this.orchestrator = new MigrationOrchestrator(config, transport);
    }

    public Response start(String authorization, String requestBody) {
        try {
            authorize(authorization);
            String migrationId = requestMigrationId(requestBody);
            MigrationOrchestrator.Result result = orchestrator.migrate(migrationId);
            return new Response(200, Json.stringify(result.toJsonObject()));
        } catch (MigrationException error) {
            return error(error);
        } catch (IllegalArgumentException error) {
            return error(new MigrationException(
                    "INVALID_REQUEST", 400, "La richiesta di avvio non e valida."));
        } catch (RuntimeException error) {
            return error(new MigrationException(
                    "INTERNAL_ERROR", 500, "Errore interno della servlet."));
        }
    }

    public Response status(String authorization, String migrationId) {
        try {
            authorize(authorization);
            MigrationOrchestrator.MigrationState state = orchestrator.status(migrationId);
            return new Response(200, Json.stringify(state.toJsonObject()));
        } catch (MigrationException error) {
            return error(error);
        } catch (RuntimeException error) {
            return error(new MigrationException(
                    "INTERNAL_ERROR", 500, "Errore interno della servlet."));
        }
    }

    public static Response error(MigrationException error) {
        LinkedHashMap<String, Object> body = new LinkedHashMap<String, Object>();
        body.put("apiVersion", API_VERSION);
        LinkedHashMap<String, Object> detail = new LinkedHashMap<String, Object>();
        detail.put("code", error.code);
        detail.put("message", error.getMessage());
        detail.put("recoverable", Boolean.valueOf(error.recoverable));
        body.put("error", detail);
        return new Response(error.httpStatus, Json.stringify(body));
    }

    private void authorize(String authorization) {
        String expected = "Bearer " + config.bridgeSecret;
        String actual = authorization == null ? "" : authorization;
        if (!MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                actual.getBytes(StandardCharsets.UTF_8))) {
            throw new MigrationException("UNAUTHORIZED", 401, "Autenticazione richiesta.");
        }
    }

    @SuppressWarnings("unchecked")
    private static String requestMigrationId(String requestBody) {
        String body = requestBody == null ? "" : requestBody.trim();
        if (body.isEmpty()) return UUID.randomUUID().toString();
        Object parsed = Json.parse(body);
        if (!(parsed instanceof Map)) throw new IllegalArgumentException("Oggetto richiesto.");
        Map<String, Object> object = (Map<String, Object>) parsed;
        for (String key : object.keySet()) {
            if (!"apiVersion".equals(key) && !"migrationId".equals(key)) {
                throw new IllegalArgumentException("Campo non ammesso.");
            }
        }
        Object version = object.get("apiVersion");
        if (object.containsKey("apiVersion") && !API_VERSION.equals(version)) {
            throw new IllegalArgumentException("Versione non valida.");
        }
        if (!object.containsKey("migrationId")) return UUID.randomUUID().toString();
        Object requested = object.get("migrationId");
        if (!(requested instanceof String)) throw new IllegalArgumentException("UUID richiesto.");
        try {
            UUID value = UUID.fromString((String) requested);
            if (!value.toString().equals(((String) requested).toLowerCase(Locale.ROOT))) {
                throw new IllegalArgumentException("UUID non canonico.");
            }
            return value.toString();
        } catch (RuntimeException error) {
            throw new IllegalArgumentException("UUID non valido.", error);
        }
    }

    public static final class Response {
        public final int status;
        public final String body;

        public Response(int status, String body) {
            this.status = status;
            this.body = body;
        }
    }
}
