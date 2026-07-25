package it.unibg.driveaura.bridge.tomcat11;

import it.unibg.driveaura.bridge.core.JdkHttpTransport;
import it.unibg.driveaura.bridge.core.MigrationConfig;
import it.unibg.driveaura.bridge.core.MigrationEndpoint;
import it.unibg.driveaura.bridge.core.MigrationException;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/** Tomcat 11 adapter; all migration behavior remains in the Java 8 core. */
@WebServlet(urlPatterns = {"/api/v1/migrations", "/api/v1/migrations/*"})
public final class MigrationServlet extends HttpServlet {
    private static final int MAX_REQUEST_BYTES = 4096;

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws IOException {
        MigrationEndpoint.Response result;
        try {
            if (request.getPathInfo() != null && !request.getPathInfo().isEmpty()) {
                throw new MigrationException("NOT_FOUND", 404, "Risorsa non trovata.");
            }
            String body = readBody(request);
            if (!body.trim().isEmpty() && !jsonContentType(request.getContentType())) {
                throw new MigrationException(
                        "INVALID_CONTENT_TYPE", 400, "E richiesto application/json.");
            }
            MigrationEndpoint endpoint =
                    new MigrationEndpoint(MigrationConfig.fromEnvironment(), new JdkHttpTransport());
            result = endpoint.start(request.getHeader("Authorization"), body);
        } catch (MigrationException error) {
            result = MigrationEndpoint.error(error);
        }
        write(response, result);
    }

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException {
        MigrationEndpoint.Response result;
        try {
            MigrationEndpoint endpoint =
                    new MigrationEndpoint(MigrationConfig.fromEnvironment(), new JdkHttpTransport());
            result = endpoint.status(
                    request.getHeader("Authorization"), migrationId(request.getPathInfo()));
        } catch (MigrationException error) {
            result = MigrationEndpoint.error(error);
        }
        write(response, result);
    }

    private static String migrationId(String pathInfo) {
        if (pathInfo == null || pathInfo.length() < 2
                || pathInfo.charAt(0) != '/' || pathInfo.indexOf('/', 1) >= 0) {
            throw new MigrationException("NOT_FOUND", 404, "Risorsa non trovata.");
        }
        return pathInfo.substring(1);
    }

    private static String readBody(HttpServletRequest request) throws IOException {
        InputStream input = request.getInputStream();
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[1024];
        int total = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            total += read;
            if (total > MAX_REQUEST_BYTES) {
                throw new MigrationException(
                        "REQUEST_TOO_LARGE", 413, "La richiesta di avvio e troppo grande.");
            }
            output.write(buffer, 0, read);
        }
        try {
            return StandardCharsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(output.toByteArray())).toString();
        } catch (CharacterCodingException error) {
            throw new MigrationException("INVALID_JSON", 400, "Il corpo non e UTF-8 valido.");
        }
    }

    private static boolean jsonContentType(String value) {
        if (value == null) return false;
        String mediaType = value.toLowerCase(Locale.ROOT).split(";", 2)[0].trim();
        return "application/json".equals(mediaType);
    }

    private static void write(HttpServletResponse response, MigrationEndpoint.Response result)
            throws IOException {
        response.setStatus(result.status);
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.setHeader("Cache-Control", "no-store");
        response.getWriter().write(result.body);
    }
}
