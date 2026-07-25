package it.unibg.driveaura.bridge.core;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/** Schema-driven row validation, tuple ordering and canonical SHA-256. */
public final class EntityCanonicalizer {
    private static final Pattern CIVIL_DATE = Pattern.compile("[0-9]{4}-[0-9]{2}-[0-9]{2}");
    private static final Pattern DECIMAL_2 = Pattern.compile("(?:0|[1-9][0-9]*)\\.[0-9]{2}");

    private EntityCanonicalizer() {
    }

    public static Row validate(EntitySchema schema, Object raw) {
        Map<String, Object> object = object(raw);
        if (!object.keySet().equals(fieldNames(schema))) {
            throw new IllegalArgumentException("Campi riga non validi.");
        }
        LinkedHashMap<String, Object> normalized = new LinkedHashMap<String, Object>();
        for (EntitySchema.Field field : schema.fields) {
            Object value = object.get(field.name);
            validateValue(field, value);
            normalized.put(field.name, value);
        }
        return new Row(schema, normalized);
    }

    public static List<Row> validateAll(EntitySchema schema, List<Object> values) {
        ArrayList<Row> rows = new ArrayList<Row>(values.size());
        for (Object value : values) rows.add(validate(schema, value));
        return rows;
    }

    public static byte[] canonicalBytes(EntitySchema schema, List<Row> rows) {
        ArrayList<Row> sorted = new ArrayList<Row>(rows);
        Collections.sort(sorted, comparator(schema));
        StringBuilder output = new StringBuilder();
        for (Row row : sorted) output.append(Json.stringify(row.values)).append('\n');
        return output.toString().getBytes(StandardCharsets.UTF_8);
    }

    public static String sha256(EntitySchema schema, List<Row> rows) {
        return hex(newSha256().digest(canonicalBytes(schema, rows)));
    }

    public static int compare(EntitySchema schema, Row left, Row right) {
        requireSchema(schema, left);
        requireSchema(schema, right);
        for (int index = 0; index < schema.keyFields.size(); index++) {
            EntitySchema.Field field = schema.keyFields.get(index);
            int result = compareValue(
                    field, left.values.get(field.name), right.values.get(field.name));
            if (result != 0) return result;
        }
        return 0;
    }

    public static Key validateKey(EntitySchema schema, Object raw) {
        if (!(raw instanceof List)) throw new IllegalArgumentException("Tupla chiave richiesta.");
        List<?> values = (List<?>) raw;
        if (values.size() != schema.keyFields.size()) {
            throw new IllegalArgumentException("Tupla chiave non valida.");
        }
        ArrayList<Object> normalized = new ArrayList<Object>(values.size());
        for (int index = 0; index < values.size(); index++) {
            Object value = values.get(index);
            validateValue(schema.keyFields.get(index), value);
            normalized.add(value);
        }
        return new Key(schema, normalized);
    }

    public static int compare(EntitySchema schema, Key left, Row right) {
        if (left.schema != schema) throw new IllegalArgumentException("Schema chiave non coerente.");
        requireSchema(schema, right);
        for (int index = 0; index < schema.keyFields.size(); index++) {
            EntitySchema.Field field = schema.keyFields.get(index);
            int result = compareValue(
                    field, left.values.get(index), right.values.get(field.name));
            if (result != 0) return result;
        }
        return 0;
    }

    public static Key keyOf(EntitySchema schema, Row row) {
        requireSchema(schema, row);
        ArrayList<Object> values = new ArrayList<Object>(schema.keyFields.size());
        for (EntitySchema.Field field : schema.keyFields) {
            values.add(row.values.get(field.name));
        }
        return new Key(schema, values);
    }

    static int compareUnicode(String left, String right) {
        int leftIndex = 0;
        int rightIndex = 0;
        while (leftIndex < left.length() && rightIndex < right.length()) {
            int leftCodePoint = left.codePointAt(leftIndex);
            int rightCodePoint = right.codePointAt(rightIndex);
            if (leftCodePoint != rightCodePoint) return leftCodePoint < rightCodePoint ? -1 : 1;
            leftIndex += Character.charCount(leftCodePoint);
            rightIndex += Character.charCount(rightCodePoint);
        }
        if (leftIndex < left.length()) return 1;
        if (rightIndex < right.length()) return -1;
        return 0;
    }

    static MessageDigest newSha256() {
        try {
            return MessageDigest.getInstance("SHA-256");
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("SHA-256 non disponibile.", error);
        }
    }

    static String hex(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) result.append(String.format("%02x", value & 0xff));
        return result.toString();
    }

    private static Comparator<Row> comparator(final EntitySchema schema) {
        return new Comparator<Row>() {
            @Override
            public int compare(Row left, Row right) {
                return EntityCanonicalizer.compare(schema, left, right);
            }
        };
    }

    private static int compareValue(EntitySchema.Field field, Object left, Object right) {
        if ("integer".equals(field.type)) {
            return Long.compare(((Long) left).longValue(), ((Long) right).longValue());
        }
        return compareUnicode((String) left, (String) right);
    }

    private static void validateValue(EntitySchema.Field field, Object value) {
        if ("integer".equals(field.type)) {
            if (!(value instanceof Long)) throw new IllegalArgumentException("Intero JSON richiesto.");
            long number = ((Long) value).longValue();
            if (number < field.minimum || number > field.maximum) {
                throw new IllegalArgumentException("Intero JSON fuori dominio.");
            }
            return;
        }
        if (!(value instanceof String)) throw new IllegalArgumentException("Stringa JSON richiesta.");
        String text = (String) value;
        int length = text.codePointCount(0, text.length());
        if (!validUnicode(text) || length < field.minLength || length > field.maxLength) {
            throw new IllegalArgumentException("Stringa JSON non valida.");
        }
        if ("date".equals(field.type)) {
            if (!CIVIL_DATE.matcher(text).matches()) throw new IllegalArgumentException("Data civile non valida.");
            try {
                LocalDate date = LocalDate.parse(text);
                if (date.getYear() < 1) throw new IllegalArgumentException("Data civile non valida.");
            } catch (DateTimeParseException error) {
                throw new IllegalArgumentException("Data civile non valida.", error);
            }
        } else if ("decimal2".equals(field.type) && !DECIMAL_2.matcher(text).matches()) {
            throw new IllegalArgumentException("Decimale monetario non valido.");
        }
    }

    private static boolean validUnicode(String value) {
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            if (character == '\0') return false;
            if (Character.isHighSurrogate(character)) {
                if (index + 1 >= value.length() || !Character.isLowSurrogate(value.charAt(index + 1))) {
                    return false;
                }
                index++;
            } else if (Character.isLowSurrogate(character)) {
                return false;
            }
        }
        return true;
    }

    private static java.util.Set<String> fieldNames(EntitySchema schema) {
        java.util.LinkedHashSet<String> names = new java.util.LinkedHashSet<String>();
        for (EntitySchema.Field field : schema.fields) names.add(field.name);
        return names;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> object(Object value) {
        if (!(value instanceof Map)) throw new IllegalArgumentException("Oggetto riga richiesto.");
        return (Map<String, Object>) value;
    }

    private static void requireSchema(EntitySchema schema, Row row) {
        if (row.schema != schema) throw new IllegalArgumentException("Schema riga non coerente.");
    }

    public static final class Row {
        private final EntitySchema schema;
        private final LinkedHashMap<String, Object> values;

        private Row(EntitySchema schema, LinkedHashMap<String, Object> values) {
            this.schema = schema;
            this.values = values;
        }

        public Map<String, Object> toJsonObject() {
            return new LinkedHashMap<String, Object>(values);
        }

        public Object value(String field) {
            return values.get(field);
        }
    }

    public static final class Key {
        private final EntitySchema schema;
        private final List<Object> values;

        private Key(EntitySchema schema, List<Object> values) {
            this.schema = schema;
            this.values = Collections.unmodifiableList(new ArrayList<Object>(values));
        }

        public List<Object> toJsonArray() {
            return new ArrayList<Object>(values);
        }
    }
}
