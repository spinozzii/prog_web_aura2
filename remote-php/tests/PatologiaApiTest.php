<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/ApiException.php';
require_once __DIR__ . '/../src/ApiResponse.php';
require_once __DIR__ . '/../src/EntitySchema.php';
require_once __DIR__ . '/../src/SchemaRegistry.php';
require_once __DIR__ . '/../src/EntityCanonicalizer.php';
require_once __DIR__ . '/../src/EntitySource.php';
require_once __DIR__ . '/../src/DatasetIdentity.php';
require_once __DIR__ . '/../src/CursorCodec.php';
require_once __DIR__ . '/../src/MigrationApi.php';
require_once __DIR__ . '/FixtureEntitySource.php';

use DriveAura\Remote\ApiException;
use DriveAura\Remote\ApiResponse;
use DriveAura\Remote\CursorCodec;
use DriveAura\Remote\DatasetIdentity;
use DriveAura\Remote\EntityCanonicalizer;
use DriveAura\Remote\MigrationApi;
use DriveAura\Remote\SchemaRegistry;
use DriveAura\Remote\Tests\FixtureEntitySource;

set_error_handler(static function (int $severity, string $message, string $file, int $line): never {
    throw new ErrorException($message, 0, $severity, $file, $line);
});

function failTest(string $message): never
{
    fwrite(STDERR, $message . "\n");
    exit(1);
}

function assertSameValue(mixed $expected, mixed $actual, string $case): void
{
    if ($expected !== $actual) {
        failTest($case . ': valore inatteso.');
    }
}

function assertStatus(int $expected, ApiResponse $response, string $case): void
{
    if ($expected !== $response->status) {
        failTest("{$case}: HTTP {$response->status}, atteso {$expected}.");
    }
}

function assertError(int $status, string $code, ApiResponse $response, string $case): void
{
    assertStatus($status, $response, $case);
    assertSameValue('1.0', $response->body['apiVersion'] ?? null, $case . ' apiVersion');
    assertSameValue($code, $response->body['error']['code'] ?? null, $case . ' error code');
    if (!is_string($response->body['error']['message'] ?? null)) {
        failTest($case . ': messaggio di errore assente.');
    }
}

/** @param array<string, mixed> $query */
function exportQuery(string $datasetId, array $query = []): array
{
    return ['datasetId' => $datasetId] + $query;
}

/** @return array<string, mixed> */
function loadFixture(): array
{
    return json_decode(
        (string) file_get_contents(dirname(__DIR__, 2) . '/tests/fixtures/t03-dataset.json'),
        true,
        64,
        JSON_THROW_ON_ERROR
    );
}

/** @param array<string, array<mixed>> $rowsByEntity */
function newApi(
    array $rowsByEntity,
    SchemaRegistry $registry,
    CursorCodec $codec,
    ?FixtureEntitySource &$source = null
): MigrationApi {
    $source = new FixtureEntitySource($rowsByEntity);
    return new MigrationApi(
        $source,
        $registry,
        'test-api-secret',
        $codec,
        static fn (): string => '2026-07-24T12:00:00Z'
    );
}

$fixture = loadFixture();
$registry = SchemaRegistry::fromFile(dirname(__DIR__, 2) . '/shared/entity-schema.json');
$rowsByEntity = $fixture['rowsByEntity'];
$datasetId = $fixture['expectedDatasetId'];
$now = 1_721_822_400;
$cursorSecret = 'test-cursor-secret';
$codec = new CursorCodec($cursorSecret, static function () use (&$now): int {
    return $now;
}, 300);
$api = newApi($rowsByEntity, $registry, $codec, $source);
$auth = ['Authorization' => 'Bearer test-api-secret'];

assertError(401, 'UNAUTHORIZED', $api->handle('GET', '/api/v1/manifest', [], []), 'segreto assente');
assertError(
    401,
    'UNAUTHORIZED',
    $api->handle('GET', '/api/v1/manifest', [], ['authorization' => 'Bearer errato']),
    'segreto errato'
);
assertStatus(
    200,
    $api->handle('GET', '/api/v1/manifest', [], ['authorization' => 'bearer test-api-secret']),
    'schema Bearer case-insensitive'
);
assertError(405, 'METHOD_NOT_ALLOWED', $api->handle('POST', '/api/v1/manifest', [], $auth), 'metodo');
assertError(404, 'NOT_FOUND', $api->handle('GET', '/api/v1/non-esiste', [], $auth), 'rotta');
assertError(
    400,
    'INVALID_REQUEST',
    $api->handle('GET', '/api/v1/manifest', ['unexpected' => '1'], $auth),
    'query manifest'
);
assertError(
    400,
    'INVALID_ENTITY',
    $api->handle('GET', '/api/v1/export/non_ammessa', ['limit' => '1'], $auth),
    'entita non ammessa'
);

$manifest = $api->handle('GET', '/api/v1/manifest', [], $auth);
assertStatus(200, $manifest, 'manifest');
assertSameValue('1.0', $manifest->body['apiVersion'] ?? null, 'manifest apiVersion');
assertSameValue($datasetId, $manifest->body['datasetId'] ?? null, 'manifest datasetId');
assertSameValue('2026-07-24T12:00:00Z', $manifest->body['generatedAt'] ?? null, 'manifest generatedAt');
assertSameValue($registry->order(), $manifest->body['entityOrder'] ?? null, 'manifest ordine');
assertSameValue(MigrationApi::MAX_BATCH_SIZE, $manifest->body['maxBatchSize'] ?? null, 'manifest massimo');
foreach ($registry->order() as $index => $entity) {
    $expected = $fixture['expectedByEntity'][$entity];
    assertSameValue($entity, $manifest->body['entities'][$index]['entity'] ?? null, "manifest {$entity}");
    assertSameValue($expected['rowCount'], $manifest->body['entities'][$index]['rowCount'] ?? null, "conteggio {$entity}");
    assertSameValue($expected['expectedSha256'], $manifest->body['entities'][$index]['digest'] ?? null, "digest {$entity}");
}

// Traverse every entity one row at a time. This exercises both simple and
// complete composite key tuples across equal prefixes and entity boundaries.
foreach ($registry->all() as $schema) {
    $cursor = null;
    $collected = [];
    do {
        $query = exportQuery($datasetId, ['limit' => '1']);
        if ($cursor !== null) {
            $query['cursor'] = $cursor;
        }
        $response = $api->handle('GET', '/api/v1/export/' . $schema->name, $query, $auth);
        assertStatus(200, $response, 'pagina ' . $schema->name);
        assertSameValue($datasetId, $response->body['datasetId'] ?? null, 'dataset pagina ' . $schema->name);
        assertSameValue($cursor, $response->body['cursor'] ?? null, 'echo cursore ' . $schema->name);
        assertSameValue(
            EntityCanonicalizer::sha256($schema, $response->body['rows']),
            $response->body['digest'] ?? null,
            'digest pagina ' . $schema->name
        );
        array_push($collected, ...$response->body['rows']);
        $cursor = $response->body['nextCursor'];
        if (($response->body['hasMore'] ?? null) !== ($cursor !== null)) {
            failTest('Coerenza hasMore/cursore non valida: ' . $schema->name);
        }
    } while ($cursor !== null);

    assertSameValue(
        $schema->sorted($schema->normalizeRows($rowsByEntity[$schema->name])),
        $collected,
        'raccolta completa ' . $schema->name
    );
}

$ricoveroFirst = $api->handle(
    'GET',
    '/api/v1/export/ricovero',
    exportQuery($datasetId, ['limit' => '1']),
    $auth
);
assertStatus(200, $ricoveroFirst, 'prima pagina ricovero');
$decodedRicovero = $codec->decode($ricoveroFirst->body['nextCursor']);
assertSameValue(['H001', 1], $decodedRicovero['after'], 'tupla cursore ricovero');

$relationFirst = $api->handle(
    'GET',
    '/api/v1/export/patologia_ricovero',
    exportQuery($datasetId, ['limit' => '1']),
    $auth
);
assertStatus(200, $relationFirst, 'prima pagina relazione');
$decodedRelation = $codec->decode($relationFirst->body['nextCursor']);
assertSameValue(['H001', 1, 'P001'], $decodedRelation['after'], 'tupla cursore relazione');

foreach (['0', '-1', '101', '1.0', 'abc', ' 1', str_repeat('9', 100)] as $invalidLimit) {
    assertError(
        400,
        'INVALID_LIMIT',
        $api->handle(
            'GET',
            '/api/v1/export/patologia',
            exportQuery($datasetId, ['limit' => $invalidLimit]),
            $auth
        ),
        'limite ' . $invalidLimit
    );
}
assertError(
    400,
    'INVALID_LIMIT',
    $api->handle(
        'GET',
        '/api/v1/export/patologia',
        exportQuery($datasetId, ['limit' => ['1']]),
        $auth
    ),
    'limite array'
);
assertError(
    400,
    'INVALID_REQUEST',
    $api->handle('GET', '/api/v1/export/patologia', ['other' => 'x'], $auth),
    'query export'
);
assertError(
    400,
    'INVALID_CURSOR',
    $api->handle(
        'GET',
        '/api/v1/export/patologia',
        exportQuery($datasetId, ['cursor' => '']),
        $auth
    ),
    'cursore vuoto'
);
assertError(
    400,
    'INVALID_CURSOR',
    $api->handle(
        'GET',
        '/api/v1/export/patologia',
        exportQuery($datasetId, ['cursor' => ['x']]),
        $auth
    ),
    'cursore array'
);
assertError(
    400,
    'INVALID_DATASET',
    $api->handle('GET', '/api/v1/export/patologia', ['limit' => '1'], $auth),
    'dataset assente'
);
assertError(
    400,
    'INVALID_DATASET',
    $api->handle(
        'GET',
        '/api/v1/export/patologia',
        ['limit' => '1', 'datasetId' => 'non-valido'],
        $auth
    ),
    'dataset malformato'
);

$validCursor = $ricoveroFirst->body['nextCursor'];
foreach ([$validCursor . 'x', substr($validCursor, 0, -1), '*.' . str_repeat('A', 43), str_repeat('A', 4097)] as $bad) {
    assertError(
        400,
        'INVALID_CURSOR',
        $api->handle(
            'GET',
            '/api/v1/export/ricovero',
            exportQuery($datasetId, ['limit' => '1', 'cursor' => $bad]),
            $auth
        ),
        'cursore alterato'
    );
}
assertError(
    400,
    'INVALID_CURSOR',
    $api->handle(
        'GET',
        '/api/v1/export/ricovero',
        exportQuery(
            $datasetId,
            ['limit' => '1', 'cursor' => $codec->encode('ospedale', $datasetId, ['H001'])]
        ),
        $auth
    ),
    'cursore altra entita'
);
foreach ([['H001'], ['H001', '1'], ['H001', 1, 'P001']] as $wrongTuple) {
    assertError(
        400,
        'INVALID_CURSOR',
        $api->handle(
            'GET',
            '/api/v1/export/ricovero',
            exportQuery(
                $datasetId,
                ['limit' => '1', 'cursor' => $codec->encode('ricovero', $datasetId, $wrongTuple)]
            ),
            $auth
        ),
        'forma cursore'
    );
}
assertError(
    409,
    'DATASET_CHANGED',
    $api->handle(
        'GET',
        '/api/v1/export/ricovero',
        [
            'limit' => '1',
            'datasetId' => $datasetId,
            'cursor' => $codec->encode('ricovero', str_repeat('0', 64), ['H001', 1]),
        ],
        $auth
    ),
    'cursore altro dataset'
);

$expiryNow = 1000;
$expiryCodec = new CursorCodec($cursorSecret, static function () use (&$expiryNow): int {
    return $expiryNow;
}, 10);
$expiryApi = newApi($rowsByEntity, $registry, $expiryCodec, $expirySource);
$expiring = $expiryApi->handle(
    'GET',
    '/api/v1/export/ricovero',
    exportQuery($datasetId, ['limit' => '1']),
    $auth
);
assertStatus(200, $expiring, 'cursore a scadenza');
$expiryNow = 1011;
$strictExpiryRejected = false;
try {
    $expiryCodec->decode($expiring->body['nextCursor']);
} catch (ApiException $error) {
    $strictExpiryRejected = $error->httpStatus === 400
        && $error->errorCode === 'INVALID_CURSOR';
}
if (!$strictExpiryRejected) {
    failTest('Il decoder generale deve rifiutare un cursore scaduto.');
}
$resumedAfterExpiry = $expiryApi->handle(
    'GET',
    '/api/v1/export/ricovero',
    exportQuery(
        $datasetId,
        ['limit' => '1', 'cursor' => $expiring->body['nextCursor']]
    ),
    $auth
);
assertStatus(200, $resumedAfterExpiry, 'ripresa autenticata dopo scadenza');
assertSameValue(
    $expiring->body['nextCursor'],
    $resumedAfterExpiry->body['cursor'] ?? null,
    'checkpoint scaduto ripreso senza riscrittura'
);

// Continuation pages use the already authenticated dataset pin.  The next
// entity boundary (and Java's final manifest refresh) detects any change.
$changedApi = newApi($rowsByEntity, $registry, $codec, $changedSource);
$changedFirst = $changedApi->handle(
    'GET',
    '/api/v1/export/ricovero',
    exportQuery($datasetId, ['limit' => '1']),
    $auth
);
$changedSource->rowsByEntity['cittadino'][0]['indirizzo'] = 'Indirizzo cambiato';
assertStatus(
    200,
    $changedApi->handle(
        'GET',
        '/api/v1/export/ricovero',
        exportQuery(
            $datasetId,
            ['limit' => '1', 'cursor' => $changedFirst->body['nextCursor']]
        ),
        $auth
    ),
    'pagina con dataset fissato'
);
assertError(
    409,
    'DATASET_CHANGED',
    $changedApi->handle(
        'GET',
        '/api/v1/export/ospedale',
        exportQuery($datasetId, ['limit' => '1']),
        $auth
    ),
    'dataset cambiato al confine entita'
);

$raceApi = newApi($rowsByEntity, $registry, $codec, $raceSource);
$raceSource->afterNextPage(static function (FixtureEntitySource $source): void {
    $source->rowsByEntity['patologia'][0]['nome'] = 'Mutata durante la pagina';
});
assertStatus(
    200,
    $raceApi->handle(
        'GET',
        '/api/v1/export/ricovero',
        exportQuery($datasetId, ['limit' => '1']),
        $auth
    ),
    'mutazione durante pagina fissata'
);
assertError(
    409,
    'DATASET_CHANGED',
    $raceApi->handle(
        'GET',
        '/api/v1/export/ospedale',
        exportQuery($datasetId, ['limit' => '1']),
        $auth
    ),
    'dataset cambiato dopo pagina'
);

foreach ([
    ['entity' => 'cittadino', 'field' => 'data_nascita', 'value' => '2023-02-29'],
    ['entity' => 'cittadino', 'field' => 'data_nascita', 'value' => '2024-2-29'],
    ['entity' => 'ricovero', 'field' => 'costo', 'value' => '1.2'],
    ['entity' => 'ricovero', 'field' => 'costo', 'value' => '01.20'],
    ['entity' => 'ricovero', 'field' => 'durata', 'value' => 3651],
    ['entity' => 'patologia', 'field' => 'nome', 'value' => ''],
] as $invalid) {
    $invalidRows = $rowsByEntity;
    $invalidRows[$invalid['entity']][0][$invalid['field']] = $invalid['value'];
    $invalidApi = newApi($invalidRows, $registry, $codec, $invalidSource);
    assertError(
        500,
        'INVALID_SOURCE_DATA',
        $invalidApi->handle('GET', '/api/v1/manifest', [], $auth),
        'dato sorgente non valido ' . $invalid['entity'] . '.' . $invalid['field']
    );
}

$extraRows = $rowsByEntity;
$extraRows['patologia'][0]['extra'] = 'vietato';
$extraApi = newApi($extraRows, $registry, $codec, $extraSource);
assertError(
    500,
    'INVALID_SOURCE_DATA',
    $extraApi->handle('GET', '/api/v1/manifest', [], $auth),
    'campo sorgente extra'
);

$missingRows = $rowsByEntity;
unset($missingRows['ricovero'][0]['costo']);
$missingApi = newApi($missingRows, $registry, $codec, $missingSource);
assertError(
    500,
    'INVALID_SOURCE_DATA',
    $missingApi->handle('GET', '/api/v1/manifest', [], $auth),
    'campo sorgente mancante'
);

$duplicateRows = $rowsByEntity;
$duplicateRows['ricovero'][] = $duplicateRows['ricovero'][0];
$duplicateApi = newApi($duplicateRows, $registry, $codec, $duplicateSource);
assertError(
    500,
    'INVALID_SOURCE_DATA',
    $duplicateApi->handle('GET', '/api/v1/manifest', [], $auth),
    'chiave sorgente duplicata'
);

$emptyRows = [];
foreach ($registry->order() as $entity) {
    $emptyRows[$entity] = [];
}
$emptyApi = newApi($emptyRows, $registry, $codec, $emptySource);
$emptyManifest = $emptyApi->handle('GET', '/api/v1/manifest', [], $auth);
assertStatus(200, $emptyManifest, 'manifest vuoto');
foreach ($emptyManifest->body['entities'] as $metadata) {
    assertSameValue(0, $metadata['rowCount'], 'conteggio vuoto');
    assertSameValue(hash('sha256', ''), $metadata['digest'], 'digest vuoto');
}
$emptyPage = $emptyApi->handle(
    'GET',
    '/api/v1/export/patologia',
    exportQuery($emptyManifest->body['datasetId'], ['limit' => '10']),
    $auth
);
assertStatus(200, $emptyPage, 'pagina vuota');
assertSameValue([], $emptyPage->body['rows'] ?? null, 'righe vuote');
assertSameValue(false, $emptyPage->body['hasMore'] ?? null, 'hasMore vuoto');
assertSameValue(null, $emptyPage->body['nextCursor'] ?? null, 'cursore vuoto');
assertSameValue(hash('sha256', ''), $emptyPage->body['digest'] ?? null, 'digest pagina vuota');

$computed = DatasetIdentity::fromRows($registry, $rowsByEntity);
assertSameValue($fixture['expectedDatasetCanonical'], $computed['canonical'], 'descrittore dataset');
assertSameValue($fixture['expectedDatasetId'], $computed['datasetId'], 'dataset id');

restore_error_handler();
echo "API multi-entità PHP valida.\n";
