package it.unibg.driveaura.bridge.tomcat9;

import it.unibg.driveaura.bridge.core.HealthResponse;
import java.io.IOException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

/** Thin Tomcat 9 adapter; the health representation stays in core. */
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
