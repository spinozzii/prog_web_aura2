package it.unibg.driveaura.bridge.core;

/** Dependency-free automated contract test runnable with javac and java. */
public final class HealthResponseTest {
    public void testHealthContract() {
        main(new String[0]);
    }

    public static void main(String[] args) {
        String expected = "{\"apiVersion\":\"1.0\",\"service\":\"bridge-servlet\",\"status\":\"ok\"}";
        if (!expected.equals(HealthResponse.json())) {
            throw new AssertionError("Contratto salute bridge non valido.");
        }
        System.out.println("Contratto salute bridge valido.");
    }
}
