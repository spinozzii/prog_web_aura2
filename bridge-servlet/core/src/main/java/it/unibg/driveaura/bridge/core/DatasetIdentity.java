package it.unibg.driveaura.bridge.core;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;

/** Aggregate identity derived from ordered per-entity counts and digests. */
public final class DatasetIdentity {
    private DatasetIdentity() {
    }

    public static String sha256(List<Descriptor> descriptors) {
        MessageDigest digest = EntityCanonicalizer.newSha256();
        for (Descriptor descriptor : descriptors) {
            LinkedHashMap<String, Object> line = new LinkedHashMap<String, Object>();
            line.put("entity", descriptor.entity);
            line.put("rowCount", Long.valueOf(descriptor.rowCount));
            line.put("digest", descriptor.digest);
            digest.update((Json.stringify(line) + "\n").getBytes(StandardCharsets.UTF_8));
        }
        return EntityCanonicalizer.hex(digest.digest());
    }

    public static List<Descriptor> descriptors(
            List<String> entities, List<Integer> rowCounts, List<String> digests) {
        if (entities.size() != rowCounts.size() || entities.size() != digests.size()) {
            throw new IllegalArgumentException("Descrittori dataset non allineati.");
        }
        ArrayList<Descriptor> result = new ArrayList<Descriptor>();
        for (int index = 0; index < entities.size(); index++) {
            result.add(new Descriptor(entities.get(index), rowCounts.get(index), digests.get(index)));
        }
        return result;
    }

    public static final class Descriptor {
        public final String entity;
        public final int rowCount;
        public final String digest;

        public Descriptor(String entity, int rowCount, String digest) {
            if (entity == null || rowCount < 0 || digest == null || !digest.matches("[0-9a-f]{64}")) {
                throw new IllegalArgumentException("Descrittore dataset non valido.");
            }
            this.entity = entity;
            this.rowCount = rowCount;
            this.digest = digest;
        }
    }
}
