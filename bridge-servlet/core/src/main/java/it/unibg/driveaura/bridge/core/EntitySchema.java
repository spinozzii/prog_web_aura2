package it.unibg.driveaura.bridge.core;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Immutable executable subset of the shared entity schema. */
public final class EntitySchema {
    public final String name;
    public final List<Field> fields;
    public final List<Field> keyFields;
    private final Map<String, Field> fieldsByName;

    EntitySchema(String name, List<Field> fields, List<String> keyNames) {
        this.name = name;
        this.fields = Collections.unmodifiableList(new ArrayList<Field>(fields));
        LinkedHashMap<String, Field> byName = new LinkedHashMap<String, Field>();
        for (Field field : fields) {
            if (byName.put(field.name, field) != null) {
                throw new IllegalArgumentException("Campo duplicato nello schema.");
            }
        }
        ArrayList<Field> keys = new ArrayList<Field>();
        for (String keyName : keyNames) {
            Field field = byName.get(keyName);
            if (field == null || (!"string".equals(field.type) && !"integer".equals(field.type))) {
                throw new IllegalArgumentException("Chiave non valida nello schema.");
            }
            keys.add(field);
        }
        if (keys.isEmpty()) throw new IllegalArgumentException("Chiave mancante nello schema.");
        this.keyFields = Collections.unmodifiableList(keys);
        this.fieldsByName = Collections.unmodifiableMap(byName);
    }

    Field field(String name) {
        return fieldsByName.get(name);
    }

    public static final class Field {
        public final String name;
        public final String type;
        public final int minLength;
        public final int maxLength;
        public final long minimum;
        public final long maximum;

        Field(
                String name,
                String type,
                int minLength,
                int maxLength,
                long minimum,
                long maximum) {
            this.name = name;
            this.type = type;
            this.minLength = minLength;
            this.maxLength = maxLength;
            this.minimum = minimum;
            this.maximum = maximum;
        }
    }
}
