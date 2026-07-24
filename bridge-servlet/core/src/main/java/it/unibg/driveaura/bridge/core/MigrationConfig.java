package it.unibg.driveaura.bridge.core;

import java.net.URI;
import java.net.URISyntaxException;

/** Immutable, validated configuration supplied outside the repository. */
public final class MigrationConfig {
    public final String remoteBaseUrl;
    public final String localBaseUrl;
    public final String remoteSecret;
    public final String localSecret;
    public final String bridgeSecret;
    public final int batchSize;
    public final int connectTimeoutMs;
    public final int readTimeoutMs;

    public MigrationConfig(String remoteBaseUrl, String localBaseUrl, String remoteSecret, String localSecret,
                           String bridgeSecret, int batchSize, int connectTimeoutMs, int readTimeoutMs) {
        if (!httpUrl(remoteBaseUrl) || !httpUrl(localBaseUrl)
                || empty(remoteSecret) || empty(localSecret) || empty(bridgeSecret)) {
            throw new MigrationException("BRIDGE_NOT_CONFIGURED", 503, "La servlet non e configurata.");
        }
        if (batchSize < 1 || batchSize > 100
                || connectTimeoutMs < 1 || connectTimeoutMs > 120000
                || readTimeoutMs < 1 || readTimeoutMs > 120000) {
            throw new MigrationException(
                    "BRIDGE_NOT_CONFIGURED", 503, "I limiti della servlet non sono validi.");
        }
        this.remoteBaseUrl = trimSlashes(remoteBaseUrl);
        this.localBaseUrl = trimSlashes(localBaseUrl);
        this.remoteSecret = remoteSecret;
        this.localSecret = localSecret;
        this.bridgeSecret = bridgeSecret;
        this.batchSize = batchSize;
        this.connectTimeoutMs = connectTimeoutMs;
        this.readTimeoutMs = readTimeoutMs;
    }

    public static MigrationConfig fromEnvironment() {
        return new MigrationConfig(
                required("REMOTE_API_URL"),
                required("LOCAL_API_URL"),
                required("REMOTE_API_SECRET"),
                required("LOCAL_API_SECRET"),
                required("BRIDGE_API_SECRET"),
                integer("BRIDGE_BATCH_SIZE", 50),
                integer("BRIDGE_CONNECT_TIMEOUT_MS", 3000),
                integer("BRIDGE_READ_TIMEOUT_MS", 10000));
    }

    private static String required(String name) {
        String value = System.getenv(name);
        return value == null ? "" : value;
    }

    private static int integer(String name, int fallback) {
        String value = System.getenv(name);
        if (value == null || value.isEmpty()) return fallback;
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException error) {
            throw new MigrationException(
                    "BRIDGE_NOT_CONFIGURED", 503, "Configurazione numerica non valida.");
        }
    }

    private static boolean httpUrl(String value) {
        if (value == null) return false;
        try {
            URI uri = new URI(value);
            String scheme = uri.getScheme();
            return ("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme))
                    && uri.isAbsolute()
                    && uri.getHost() != null
                    && uri.getUserInfo() == null
                    && uri.getQuery() == null
                    && uri.getFragment() == null;
        } catch (URISyntaxException error) {
            return false;
        }
    }

    private static boolean empty(String value) {
        return value == null || value.isEmpty();
    }

    private static String trimSlashes(String value) {
        while (value.endsWith("/")) value = value.substring(0, value.length() - 1);
        return value;
    }
}
