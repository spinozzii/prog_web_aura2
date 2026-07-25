package it.unibg.driveaura.bridge.core;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.SocketTimeoutException;
import java.net.URL;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Map;

/** HttpURLConnection transport with bounded responses and redirects disabled. */
public final class JdkHttpTransport implements HttpTransport {
    private static final int MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

    @Override
    public Response execute(String method, String url, Map<String, String> headers, String body, int connectTimeoutMs, int readTimeoutMs) {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(url).openConnection();
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod(method);
            connection.setConnectTimeout(connectTimeoutMs);
            connection.setReadTimeout(readTimeoutMs);
            connection.setRequestProperty("Accept", "application/json");
            for (Map.Entry<String, String> header : headers.entrySet()) connection.setRequestProperty(header.getKey(), header.getValue());
            if (body != null) {
                byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                connection.setFixedLengthStreamingMode(bytes.length);
                OutputStream output = connection.getOutputStream();
                output.write(bytes);
                output.close();
            }
            int status = connection.getResponseCode();
            InputStream input = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
            String responseBody = "";
            if (input != null) {
                try {
                    responseBody = readBounded(input);
                } finally {
                    input.close();
                }
            }
            return new Response(status, responseBody, connection.getContentType());
        } catch (SocketTimeoutException error) {
            throw new MigrationException(
                    "HTTP_TIMEOUT", 504,
                    "Un servizio non ha risposto entro il timeout.", true, error);
        } catch (InvalidResponseException error) {
            throw new MigrationException(
                    "HTTP_INVALID_RESPONSE", 502,
                    "Un servizio ha restituito una risposta HTTP non valida.",
                    false, error);
        } catch (IOException error) {
            throw new MigrationException(
                    "HTTP_UNAVAILABLE", 502,
                    "Un servizio non e raggiungibile.", true, error);
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private static String readBounded(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096];
        int total = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            total += read;
            if (total > MAX_RESPONSE_BYTES) {
                throw new InvalidResponseException("Risposta HTTP troppo grande.");
            }
            output.write(buffer, 0, read);
        }
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(output.toByteArray())).toString();
        } catch (CharacterCodingException error) {
            throw new InvalidResponseException(
                    "Risposta HTTP non UTF-8.", error);
        }
    }

    private static final class InvalidResponseException extends IOException {
        private InvalidResponseException(String message) {
            super(message);
        }

        private InvalidResponseException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
