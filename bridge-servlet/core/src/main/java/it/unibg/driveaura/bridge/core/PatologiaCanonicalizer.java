package it.unibg.driveaura.bridge.core;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;

/** Backward-compatible Patologia facade over the shared generic canonicalizer. */
public final class PatologiaCanonicalizer {
    private PatologiaCanonicalizer() {
    }

    public static String canonicalize(List<Patologia> rows) {
        EntitySchema schema = EntitySchemas.require("patologia");
        return new String(
                EntityCanonicalizer.canonicalBytes(schema, genericRows(schema, rows)),
                StandardCharsets.UTF_8);
    }

    public static String sha256(List<Patologia> rows) {
        EntitySchema schema = EntitySchemas.require("patologia");
        return EntityCanonicalizer.sha256(schema, genericRows(schema, rows));
    }

    static int compareCodes(String left, String right) {
        return EntityCanonicalizer.compareUnicode(left, right);
    }

    private static List<EntityCanonicalizer.Row> genericRows(
            EntitySchema schema, List<Patologia> rows) {
        ArrayList<EntityCanonicalizer.Row> result =
                new ArrayList<EntityCanonicalizer.Row>(rows.size());
        for (Patologia row : rows) {
            LinkedHashMap<String, Object> value = new LinkedHashMap<String, Object>();
            value.put("cod", row.cod);
            value.put("nome", row.nome);
            value.put("criticita", Long.valueOf(row.criticita));
            result.add(EntityCanonicalizer.validate(schema, value));
        }
        return result;
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
