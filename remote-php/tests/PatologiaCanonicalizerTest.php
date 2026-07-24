<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/PatologiaCanonicalizer.php';

use DriveAura\Remote\PatologiaCanonicalizer;

$fixturePath = dirname(__DIR__, 2) . '/tests/fixtures/patologia-canonical.json';
$fixture = json_decode((string) file_get_contents($fixturePath), true, 512, JSON_THROW_ON_ERROR);
$rows = array_reverse($fixture['rows']);
$canonical = PatologiaCanonicalizer::canonicalize($rows);

if ($canonical !== $fixture['expectedCanonical']) {
    fwrite(STDERR, "Byte canonici PHP non validi.\n");
    exit(1);
}
if (PatologiaCanonicalizer::sha256($rows) !== $fixture['expectedSha256']) {
    fwrite(STDERR, "Digest PHP non valido.\n");
    exit(1);
}

echo "Canonicalizzazione Patologia PHP valida.\n";
