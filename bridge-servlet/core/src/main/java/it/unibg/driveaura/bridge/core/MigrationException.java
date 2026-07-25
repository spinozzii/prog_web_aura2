package it.unibg.driveaura.bridge.core;

public final class MigrationException extends RuntimeException {
    public final String code;
    public final int httpStatus;
    public final boolean recoverable;

    public MigrationException(String code, int httpStatus, String message) {
        this(code, httpStatus, message, false, null);
    }

    public MigrationException(
            String code, int httpStatus, String message, boolean recoverable) {
        this(code, httpStatus, message, recoverable, null);
    }

    public MigrationException(String code, int httpStatus, String message, Throwable cause) {
        this(code, httpStatus, message, false, cause);
    }

    public MigrationException(
            String code,
            int httpStatus,
            String message,
            boolean recoverable,
            Throwable cause) {
        super(message, cause);
        this.code = code;
        this.httpStatus = httpStatus;
        this.recoverable = recoverable;
    }
}
