package it.unibg.driveaura.bridge.core;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/** Canonical JSON and SHA-256 without Servlet or third-party dependencies. */
public final class PatologiaCanonicalizer {
    private PatologiaCanonicalizer() {
    }

    public static String canonicalize(List<Patologia> rows) {
        List<Patologia> sorted = new ArrayList<Patologia>(rows);
        Collections.sort(sorted, new Comparator<Patologia>() {
            @Override
            public int compare(Patologia left, Patologia right) {
                return compareCodes(left.cod, right.cod);
            }
        });
        StringBuilder output = new StringBuilder();
        for (Patologia row : sorted) {
            output.append("{\"cod\":\"").append(escape(row.cod))
                    .append("\",\"nome\":\"").append(escape(row.nome))
                    .append("\",\"criticita\":").append(row.criticita)
                    .append("}\n");
        }
        return output.toString();
    }

    /** Unicode code-point order, matching valid UTF-8 binary and Python order. */
    static int compareCodes(String left, String right) {
        int leftIndex = 0;
        int rightIndex = 0;
        while (leftIndex < left.length() && rightIndex < right.length()) {
            int leftCodePoint = left.codePointAt(leftIndex);
            int rightCodePoint = right.codePointAt(rightIndex);
            if (leftCodePoint != rightCodePoint) {
                return leftCodePoint < rightCodePoint ? -1 : 1;
            }
            leftIndex += Character.charCount(leftCodePoint);
            rightIndex += Character.charCount(rightCodePoint);
        }
        if (leftIndex < left.length()) return 1;
        if (rightIndex < right.length()) return -1;
        return 0;
    }

    public static String sha256(List<Patologia> rows) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(canonicalize(rows).getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte value : digest) {
                hex.append(String.format("%02x", value & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("SHA-256 non disponibile.", error);
        }
    }

    private static String escape(String value) {
        StringBuilder escaped = new StringBuilder();
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            switch (character) {
                case '"': escaped.append("\\\""); break;
                case '\\': escaped.append("\\\\"); break;
                case '\b': escaped.append("\\b"); break;
                case '\f': escaped.append("\\f"); break;
                case '\n': escaped.append("\\n"); break;
                case '\r': escaped.append("\\r"); break;
                case '\t': escaped.append("\\t"); break;
                default:
                    if (character < 0x20) {
                        escaped.append(String.format("\\u%04x", (int) character));
                    } else {
                        escaped.append(character);
                    }
            }
        }
        return escaped.toString();
    }

    public static final class Patologia {
        public final String cod;
        public final String nome;
        public final int criticita;

        public Patologia(String cod, String nome, int criticita) {
            this.cod = cod;
            this.nome = nome;
            this.criticita = criticita;
        }
    }
}
