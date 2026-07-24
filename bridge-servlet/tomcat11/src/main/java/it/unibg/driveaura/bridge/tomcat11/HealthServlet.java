package it.unibg.driveaura.bridge.tomcat11;

import it.unibg.driveaura.bridge.core.HealthResponse;
import java.io.IOException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/** Thin Tomcat 11 adapter; the health representation stays in core. */
@WebServlet("/health")
public final class HealthServlet extends HttpServlet {
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_OK);
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write(HealthResponse.json());
    }
}
