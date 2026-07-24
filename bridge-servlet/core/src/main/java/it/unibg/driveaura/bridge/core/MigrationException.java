package it.unibg.driveaura.bridge.core;

public final class MigrationException extends RuntimeException {
    public final String code;
    public final int httpStatus;

    public MigrationException(String code, int httpStatus, String message) {
        super(message);
        this.code = code;
        this.httpStatus = httpStatus;
    }

    public MigrationException(String code, int httpStatus, String message, Throwable cause) {
        super(message, cause);
        this.code = code;
        this.httpStatus = httpStatus;
    }
}
