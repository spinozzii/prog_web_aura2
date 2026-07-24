package it.unibg.driveaura.bridge.core;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Small strict JSON codec used to keep the Java 8 core dependency-free. */
public final class Json {
    private Json() {
    }

    public static Object parse(String source) {
        Parser parser = new Parser(source);
        Object value = parser.value(0);
        parser.whitespace();
        if (!parser.end()) {
            throw new IllegalArgumentException("JSON contiene dati aggiuntivi.");
        }
        return value;
    }

    public static String stringify(Object value) {
        StringBuilder output = new StringBuilder();
        write(value, output);
        return output.toString();
    }

    @SuppressWarnings("unchecked")
    private static void write(Object value, StringBuilder output) {
        if (value == null) {
            output.append("null");
        } else if (value instanceof String) {
            output.append('"').append(escape((String) value)).append('"');
        } else if (value instanceof Boolean) {
            output.append(value.toString());
        } else if (value instanceof Number) {
            if (value instanceof Double && (((Double) value).isInfinite() || ((Double) value).isNaN())) {
                throw new IllegalArgumentException("Numero JSON non finito.");
            }
            if (value instanceof Float && (((Float) value).isInfinite() || ((Float) value).isNaN())) {
                throw new IllegalArgumentException("Numero JSON non finito.");
            }
            output.append(value.toString());
        } else if (value instanceof Map) {
            output.append('{');
            boolean first = true;
            for (Map.Entry<String, Object> entry : ((Map<String, Object>) value).entrySet()) {
                if (!first) output.append(',');
                first = false;
                output.append('"').append(escape(entry.getKey())).append("\":");
                write(entry.getValue(), output);
            }
            output.append('}');
        } else if (value instanceof List) {
            output.append('[');
            boolean first = true;
            for (Object item : (List<Object>) value) {
                if (!first) output.append(',');
                first = false;
                write(item, output);
            }
            output.append(']');
        } else {
            throw new IllegalArgumentException("Tipo JSON non supportato.");
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
                    if (character < 0x20) escaped.append(String.format("\\u%04x", (int) character));
                    else escaped.append(character);
            }
        }
        return escaped.toString();
    }

    private static final class Parser {
        private final String source;
        private int index;

        private Parser(String source) {
            this.source = source;
        }

        private Object value(int depth) {
            if (depth > 32) throw new IllegalArgumentException("JSON troppo annidato.");
            whitespace();
            if (end()) throw new IllegalArgumentException("JSON incompleto.");
            char current = source.charAt(index);
            if (current == '{') return object(depth + 1);
            if (current == '[') return array(depth + 1);
            if (current == '"') return string();
            if (current == 't') { literal("true"); return Boolean.TRUE; }
            if (current == 'f') { literal("false"); return Boolean.FALSE; }
            if (current == 'n') { literal("null"); return null; }
            if (current == '-' || asciiDigit(current)) return number();
            throw new IllegalArgumentException("Valore JSON non valido.");
        }

        private Map<String, Object> object(int depth) {
            LinkedHashMap<String, Object> result = new LinkedHashMap<String, Object>();
            index++;
            whitespace();
            if (consume('}')) return result;
            while (true) {
                whitespace();
                if (end() || source.charAt(index) != '"') throw new IllegalArgumentException("Chiave JSON non valida.");
                String key = string();
                if (result.containsKey(key)) throw new IllegalArgumentException("Chiave JSON duplicata.");
                whitespace();
                require(':');
                result.put(key, value(depth));
                whitespace();
                if (consume('}')) return result;
                require(',');
            }
        }

        private List<Object> array(int depth) {
            ArrayList<Object> result = new ArrayList<Object>();
            index++;
            whitespace();
            if (consume(']')) return result;
            while (true) {
                result.add(value(depth));
                whitespace();
                if (consume(']')) return result;
                require(',');
            }
        }

        private String string() {
            require('"');
            StringBuilder result = new StringBuilder();
            while (!end()) {
                char character = source.charAt(index++);
                if (character == '"') return result.toString();
                if (character < 0x20) throw new IllegalArgumentException("Controllo non escapato in JSON.");
                if (character != '\\') {
                    result.append(character);
                    continue;
                }
                if (end()) throw new IllegalArgumentException("Escape JSON incompleto.");
                char escaped = source.charAt(index++);
                switch (escaped) {
                    case '"': result.append('"'); break;
                    case '\\': result.append('\\'); break;
                    case '/': result.append('/'); break;
                    case 'b': result.append('\b'); break;
                    case 'f': result.append('\f'); break;
                    case 'n': result.append('\n'); break;
                    case 'r': result.append('\r'); break;
                    case 't': result.append('\t'); break;
                    case 'u': result.append(unicode()); break;
                    default: throw new IllegalArgumentException("Escape JSON non valido.");
                }
            }
            throw new IllegalArgumentException("Stringa JSON incompleta.");
        }

        private char unicode() {
            if (index + 4 > source.length()) throw new IllegalArgumentException("Escape Unicode incompleto.");
            try {
                char value = (char) Integer.parseInt(source.substring(index, index + 4), 16);
                index += 4;
                return value;
            } catch (NumberFormatException error) {
                throw new IllegalArgumentException("Escape Unicode non valido.");
            }
        }

        private Number number() {
            int start = index;
            if (source.charAt(index) == '-') index++;
            if (end()) throw new IllegalArgumentException("Numero JSON incompleto.");
            if (source.charAt(index) == '0') {
                index++;
                if (!end() && asciiDigit(source.charAt(index))) {
                    throw new IllegalArgumentException("Numero JSON con zero iniziale.");
                }
            } else {
                digits();
            }
            boolean decimal = false;
            if (!end() && source.charAt(index) == '.') { decimal = true; index++; digits(); }
            if (!end() && (source.charAt(index) == 'e' || source.charAt(index) == 'E')) {
                decimal = true; index++;
                if (!end() && (source.charAt(index) == '+' || source.charAt(index) == '-')) index++;
                digits();
            }
            String raw = source.substring(start, index);
            try {
                // A ternary here would promote the Long branch to Double.
                if (decimal) return new BigDecimal(raw);
                return Long.valueOf(raw);
            } catch (NumberFormatException error) {
                throw new IllegalArgumentException("Numero JSON non valido.");
            }
        }

        private void digits() {
            int start = index;
            while (!end() && asciiDigit(source.charAt(index))) index++;
            if (start == index) throw new IllegalArgumentException("Numero JSON incompleto.");
        }

        private static boolean asciiDigit(char value) {
            return value >= '0' && value <= '9';
        }

        private void literal(String value) {
            if (!source.startsWith(value, index)) throw new IllegalArgumentException("Letterale JSON non valido.");
            index += value.length();
        }

        private boolean consume(char expected) {
            if (!end() && source.charAt(index) == expected) { index++; return true; }
            return false;
        }

        private void require(char expected) {
            if (!consume(expected)) throw new IllegalArgumentException("Separatore JSON non valido.");
        }

        private void whitespace() {
            while (!end()) {
                char value = source.charAt(index);
                if (value != ' ' && value != '\n' && value != '\r' && value != '\t') return;
                index++;
            }
        }

        private boolean end() {
            return index >= source.length();
        }
    }
}
