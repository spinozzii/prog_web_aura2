package it.unibg.driveaura.bridge.core;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Reads the shared JSON fixture with a narrow parser for its fixed schema. */
public final class PatologiaCanonicalizerTest {
    private static final Pattern ROW = Pattern.compile("\\{\\s*\\\"cod\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"\\\\])*)\\\",\\s*\\\"nome\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"\\\\])*)\\\",\\s*\\\"criticita\\\"\\s*:\\s*(\\d+)\\s*\\}");
    private static final Pattern CANONICAL = Pattern.compile("\\\"expectedCanonical\\\"\\s*:\\s*\\\"((?:\\\\.|[^\\\"\\\\])*)\\\"");
    private static final Pattern DIGEST = Pattern.compile("\\\"expectedSha256\\\"\\s*:\\s*\\\"([0-9a-f]{64})\\\"");

    public void testSharedFixtures() throws Exception {
        String[] names = {
            "patologia-canonical.json",
            "patologia-empty.json",
            "patologia-line-separators.json"
        };
        String[] paths = new String[names.length];
        for (int index = 0; index < names.length; index++) {
            java.net.URL resource = PatologiaCanonicalizerTest.class
                    .getResource("/" + names[index]);
            if (resource == null) {
                throw new AssertionError("Fixture Maven mancante: " + names[index]);
            }
            paths[index] = Paths.get(resource.toURI()).toString();
        }
        main(paths);
    }

    public static void main(String[] args) throws Exception {
        for (String fixturePath : args) {
            verifyFixture(fixturePath);
        }
        if (PatologiaCanonicalizer.compareCodes("\ue000", "\ud800\udc00") >= 0) {
            throw new AssertionError("Ordine Unicode Java non compatibile con UTF-8/Python.");
        }
        System.out.println("Canonicalizzazione Patologia Java valida.");
    }

    private static void verifyFixture(String fixturePath) throws Exception {
        String fixture = new String(Files.readAllBytes(Paths.get(fixturePath)), StandardCharsets.UTF_8);
        List<PatologiaCanonicalizer.Patologia> rows = new ArrayList<PatologiaCanonicalizer.Patologia>();
        Matcher rowMatcher = ROW.matcher(fixture);
        while (rowMatcher.find()) {
            rows.add(new PatologiaCanonicalizer.Patologia(
                    unescape(rowMatcher.group(1)), unescape(rowMatcher.group(2)), Integer.parseInt(rowMatcher.group(3))));
        }
        boolean emptyFixture = fixturePath.endsWith("patologia-empty.json");
        if ((emptyFixture && !rows.isEmpty()) || (!emptyFixture && rows.isEmpty())) {
            throw new AssertionError("Fixture Patologia non valida.");
        }
        Collections.reverse(rows);
        String canonical = PatologiaCanonicalizer.canonicalize(rows);
        String expectedCanonical = unescape(required(CANONICAL, fixture));
        String expectedDigest = required(DIGEST, fixture);
        if (!canonical.equals(expectedCanonical)) {
            throw new AssertionError("Byte canonici Java non validi.");
        }
        if (!PatologiaCanonicalizer.sha256(rows).equals(expectedDigest)) {
            throw new AssertionError("Digest Java non valido.");
        }
    }

    private static String required(Pattern pattern, String source) {
        Matcher matcher = pattern.matcher(source);
        if (!matcher.find()) {
            throw new AssertionError("Valore atteso mancante nella fixture.");
        }
        return matcher.group(1);
    }

    private static String unescape(String value) {
        StringBuilder result = new StringBuilder();
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            if (character != '\\') {
                result.append(character);
                continue;
            }
            char escaped = value.charAt(++index);
            switch (escaped) {
                case '"': result.append('"'); break;
                case '\\': result.append('\\'); break;
                case '/': result.append('/'); break;
                case 'b': result.append('\b'); break;
                case 'f': result.append('\f'); break;
                case 'n': result.append('\n'); break;
                case 'r': result.append('\r'); break;
                case 't': result.append('\t'); break;
                case 'u':
                    result.append((char) Integer.parseInt(value.substring(index + 1, index + 5), 16));
                    index += 4;
                    break;
                default: throw new AssertionError("Escape JSON non valido.");
            }
        }
        return result.toString();
    }
}
