package it.unibg.driveaura.bridge.core;

/** Servlet-API-independent representation of the bridge health contract. */
public final class HealthResponse {
    public static final String API_VERSION = "1.0";
    public static final String SERVICE = "bridge-servlet";

    private HealthResponse() {
    }

    public static String json() {
        return "{\"apiVersion\":\"" + API_VERSION
                + "\",\"service\":\"" + SERVICE
                + "\",\"status\":\"ok\"}";
    }
}
