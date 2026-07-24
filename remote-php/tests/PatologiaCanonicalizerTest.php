<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/ApiException.php';
require_once __DIR__ . '/../src/EntitySchema.php';
require_once __DIR__ . '/../src/SchemaRegistry.php';
require_once __DIR__ . '/../src/EntityCanonicalizer.php';
require_once __DIR__ . '/../src/EntitySource.php';
require_once __DIR__ . '/../src/DatasetIdentity.php';
require_once __DIR__ . '/../src/PatologiaCanonicalizer.php';

use DriveAura\Remote\DatasetIdentity;
use DriveAura\Remote\EntityCanonicalizer;
use DriveAura\Remote\PatologiaCanonicalizer;
use DriveAura\Remote\SchemaRegistry;

$fixtureDirectory = dirname(__DIR__, 2) . '/tests/fixtures';
$registry = SchemaRegistry::fromFile(dirname(__DIR__, 2) . '/shared/entity-schema.json');

$datasetFixture = json_decode(
    (string) file_get_contents($fixtureDirectory . '/t03-dataset.json'),
    true,
    64,
    JSON_THROW_ON_ERROR
);
$reversedRows = [];
foreach ($registry->all() as $schema) {
    $expected = $datasetFixture['expectedByEntity'][$schema->name] ?? null;
    $rows = array_reverse($datasetFixture['rowsByEntity'][$schema->name] ?? []);
    if (!is_array($expected) || !is_array($rows)) {
        fwrite(STDERR, "Fixture T03 incompleta per {$schema->name}.\n");
        exit(1);
    }
    $canonical = EntityCanonicalizer::canonicalize($schema, $rows);
    if ($canonical !== $expected['expectedCanonical']) {
        fwrite(STDERR, "Byte canonici PHP non validi: {$schema->name}.\n");
        exit(1);
    }
    if (EntityCanonicalizer::sha256($schema, $rows) !== $expected['expectedSha256']) {
        fwrite(STDERR, "Digest PHP non valido: {$schema->name}.\n");
        exit(1);
    }
    if (count($rows) !== $expected['rowCount']) {
        fwrite(STDERR, "Conteggio fixture PHP non valido: {$schema->name}.\n");
        exit(1);
    }
    $reversedRows[$schema->name] = $rows;
}

$dataset = DatasetIdentity::fromRows($registry, $reversedRows);
if ($dataset['canonical'] !== $datasetFixture['expectedDatasetCanonical']) {
    fwrite(STDERR, "Descrittore canonico del dataset PHP non valido.\n");
    exit(1);
}
if ($dataset['datasetId'] !== $datasetFixture['expectedDatasetId']) {
    fwrite(STDERR, "Dataset ID PHP non valido.\n");
    exit(1);
}

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

echo "Canonicalizzazione multi-entità PHP valida.\n";
