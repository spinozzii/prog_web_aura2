<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/PatologiaCanonicalizer.php';

use DriveAura\Remote\PatologiaCanonicalizer;

$fixtureDirectory = dirname(__DIR__, 2) . '/tests/fixtures';
foreach (['patologia-canonical.json', 'patologia-empty.json', 'patologia-line-separators.json'] as $fixtureName) {
    $fixture = json_decode((string) file_get_contents($fixtureDirectory . '/' . $fixtureName), true, 512, JSON_THROW_ON_ERROR);
    $rows = array_reverse($fixture['rows']);
    $canonical = PatologiaCanonicalizer::canonicalize($rows);
    if ($canonical !== $fixture['expectedCanonical']) {
        fwrite(STDERR, "Byte canonici PHP non validi: {$fixtureName}.\n");
        exit(1);
    }
    if (PatologiaCanonicalizer::sha256($rows) !== $fixture['expectedSha256']) {
        fwrite(STDERR, "Digest PHP non valido: {$fixtureName}.\n");
        exit(1);
    }
}

echo "Canonicalizzazione Patologia PHP valida.\n";
