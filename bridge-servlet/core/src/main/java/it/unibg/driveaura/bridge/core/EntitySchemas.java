package it.unibg.driveaura.bridge.core;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Loads the single shared schema resource used by all Java migration logic. */
public final class EntitySchemas {
    private static final List<String> REQUIRED_ORDER = Collections.unmodifiableList(Arrays.asList(
            "cittadino",
            "patologia",
            "patologia_cronica",
            "patologia_mortale",
            "ospedale",
            "ricovero",
            "patologia_ricovero",
            "progressivo_ricovero"));

    private EntitySchemas() {
    }

    public static List<EntitySchema> ordered() {
        return Holder.ORDERED;
    }

    public static EntitySchema require(String name) {
        EntitySchema schema = Holder.BY_NAME.get(name);
        if (schema == null) throw new IllegalArgumentException("Entita non prevista dallo schema.");
        return schema;
    }

    public static List<String> names() {
        return REQUIRED_ORDER;
    }

    private static final class Holder {
        private static final List<EntitySchema> ORDERED = load();
        private static final Map<String, EntitySchema> BY_NAME = index(ORDERED);
    }

    @SuppressWarnings("unchecked")
    private static List<EntitySchema> load() {
        InputStream input = openSchema();
        try {
            Object parsed = Json.parse(readUtf8(input));
            Map<String, Object> root = object(parsed);
            exactFields(root, "apiVersion", "entityOrder", "entities");
            if (!"1.0".equals(string(root, "apiVersion"))) {
                throw new IllegalArgumentException("Versione schema non valida.");
            }
            List<Object> rawOrder = list(root, "entityOrder");
            if (rawOrder.size() != REQUIRED_ORDER.size()) {
                throw new IllegalArgumentException("Ordine entita incompleto.");
            }
            for (int index = 0; index < REQUIRED_ORDER.size(); index++) {
                if (!REQUIRED_ORDER.get(index).equals(rawOrder.get(index))) {
                    throw new IllegalArgumentException("Ordine entita non valido.");
                }
            }
            Map<String, Object> entities = object(root.get("entities"));
            if (!entities.keySet().equals(new LinkedHashSet<String>(REQUIRED_ORDER))) {
                throw new IllegalArgumentException("Entita schema non valide.");
            }
            ArrayList<EntitySchema> schemas = new ArrayList<EntitySchema>();
            String previous = null;
            for (String name : REQUIRED_ORDER) {
                Map<String, Object> raw = object(entities.get(name));
                exactFields(raw, "table", "key", "previousEntity", "fields", "foreignKeys", "unique");
                if (!name.equals(string(raw, "table"))) {
                    throw new IllegalArgumentException("Tabella schema non valida.");
                }
                Object declaredPrevious = raw.get("previousEntity");
                if (previous == null ? declaredPrevious != null : !previous.equals(declaredPrevious)) {
                    throw new IllegalArgumentException("Dipendenza schema non valida.");
                }
                if (!(raw.get("foreignKeys") instanceof List) || !(raw.get("unique") instanceof List)) {
                    throw new IllegalArgumentException("Relazioni schema non valide.");
                }
                List<String> keys = strings(list(raw, "key"));
                List<Object> rawFields = list(raw, "fields");
                ArrayList<EntitySchema.Field> fields = new ArrayList<EntitySchema.Field>();
                for (Object item : rawFields) fields.add(field(object(item)));
                schemas.add(new EntitySchema(name, fields, keys));
                previous = name;
            }
            return Collections.unmodifiableList(schemas);
        } catch (IOException error) {
            throw new IllegalStateException("Schema entita non leggibile.", error);
        } finally {
            try {
                input.close();
            } catch (IOException ignored) {
                // The schema was already consumed; there is no recovery action.
            }
        }
    }

    private static EntitySchema.Field field(Map<String, Object> raw) {
        Set<String> allowed = new LinkedHashSet<String>(
                Arrays.asList("name", "type", "minLength", "maxLength", "minimum", "maximum"));
        if (!allowed.containsAll(raw.keySet()) || !raw.keySet().containsAll(Arrays.asList("name", "type"))) {
            throw new IllegalArgumentException("Definizione campo non valida.");
        }
        String name = string(raw, "name");
        String type = string(raw, "type");
        if (!name.matches("[a-z][a-z0-9_]{0,63}")
                || (!"string".equals(type) && !"date".equals(type)
                && !"integer".equals(type) && !"decimal2".equals(type))) {
            throw new IllegalArgumentException("Tipo campo non valido.");
        }
        int minLength = 1;
        int maxLength = optionalInteger(raw, "maxLength", 1, 1000000, Integer.MAX_VALUE);
        long minimum = Long.MIN_VALUE;
        long maximum = Long.MAX_VALUE;
        if ("string".equals(type)) {
            minLength = optionalInteger(raw, "minLength", 1, 1000000, -1);
            if (minLength != 1 || minLength > maxLength) {
                throw new IllegalArgumentException("Lunghezza stringa non valida.");
            }
        } else if (raw.containsKey("minLength") || raw.containsKey("maxLength")) {
            throw new IllegalArgumentException("Lunghezza campo non valida.");
        }
        if ("integer".equals(type)) {
            minimum = optionalLong(raw, "minimum", Long.MIN_VALUE);
            maximum = optionalLong(raw, "maximum", Long.MAX_VALUE);
            if (minimum > maximum) throw new IllegalArgumentException("Dominio intero non valido.");
        } else if ("decimal2".equals(type)) {
            if (!"0.00".equals(raw.get("minimum")) || raw.containsKey("maximum")) {
                throw new IllegalArgumentException("Dominio decimale non valido.");
            }
        } else if (raw.containsKey("minimum") || raw.containsKey("maximum")) {
            throw new IllegalArgumentException("Dominio campo non valido.");
        }
        return new EntitySchema.Field(name, type, minLength, maxLength, minimum, maximum);
    }

    private static InputStream openSchema() {
        InputStream resource = EntitySchemas.class.getResourceAsStream("/entity-schema.json");
        if (resource != null) return resource;
        String configured = System.getProperty("driveaura.entitySchema");
        List<File> candidates = new ArrayList<File>();
        if (configured != null && !configured.isEmpty()) candidates.add(new File(configured));
        candidates.add(new File("shared/entity-schema.json"));
        candidates.add(new File("../shared/entity-schema.json"));
        for (File candidate : candidates) {
            if (candidate.isFile()) {
                try {
                    return new FileInputStream(candidate);
                } catch (IOException error) {
                    throw new IllegalStateException("Schema entita non leggibile.", error);
                }
            }
        }
        throw new IllegalStateException("Risorsa entity-schema.json mancante.");
    }

    private static String readUtf8(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096];
        int read;
        while ((read = input.read(buffer)) != -1) {
            if (output.size() + read > 1024 * 1024) {
                throw new IOException("Schema entita troppo grande.");
            }
            output.write(buffer, 0, read);
        }
        return new String(output.toByteArray(), StandardCharsets.UTF_8);
    }

    private static Map<String, EntitySchema> index(List<EntitySchema> schemas) {
        LinkedHashMap<String, EntitySchema> result = new LinkedHashMap<String, EntitySchema>();
        for (EntitySchema schema : schemas) result.put(schema.name, schema);
        return Collections.unmodifiableMap(result);
    }

    private static List<String> strings(List<Object> values) {
        ArrayList<String> result = new ArrayList<String>();
        for (Object value : values) {
            if (!(value instanceof String) || ((String) value).isEmpty()) {
                throw new IllegalArgumentException("Stringa schema non valida.");
            }
            result.add((String) value);
        }
        return result;
    }

    private static int optionalInteger(
            Map<String, Object> value, String key, int minimum, int maximum, int fallback) {
        if (!value.containsKey(key)) return fallback;
        long number = longValue(value.get(key));
        if (number < minimum || number > maximum) {
            throw new IllegalArgumentException("Intero schema fuori dominio.");
        }
        return (int) number;
    }

    private static long optionalLong(Map<String, Object> value, String key, long fallback) {
        return value.containsKey(key) ? longValue(value.get(key)) : fallback;
    }

    private static long longValue(Object value) {
        if (!(value instanceof Long)) throw new IllegalArgumentException("Intero schema richiesto.");
        return ((Long) value).longValue();
    }

    private static void exactFields(Map<String, Object> value, String... fields) {
        if (!value.keySet().equals(new LinkedHashSet<String>(Arrays.asList(fields)))) {
            throw new IllegalArgumentException("Campi schema non validi.");
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> object(Object value) {
        if (!(value instanceof Map)) throw new IllegalArgumentException("Oggetto schema richiesto.");
        return (Map<String, Object>) value;
    }

    @SuppressWarnings("unchecked")
    private static List<Object> list(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof List)) throw new IllegalArgumentException("Array schema richiesto.");
        return (List<Object>) item;
    }

    private static String string(Map<String, Object> value, String key) {
        Object item = value.get(key);
        if (!(item instanceof String)) throw new IllegalArgumentException("Stringa schema richiesta.");
        return (String) item;
    }
}
