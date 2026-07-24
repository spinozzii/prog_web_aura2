package it.unibg.driveaura.bridge.core;

import java.util.Map;

public interface HttpTransport {
    Response execute(String method, String url, Map<String, String> headers, String body, int connectTimeoutMs, int readTimeoutMs);

    final class Response {
        public final int status;
        public final String body;
        public final String contentType;

        public Response(int status, String body) {
            this(status, body, "application/json; charset=utf-8");
        }

        public Response(int status, String body, String contentType) {
            this.status = status;
            this.body = body;
            this.contentType = contentType == null ? "" : contentType;
        }
    }
}
