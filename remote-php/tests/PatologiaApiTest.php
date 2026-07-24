<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/ApiException.php';
require_once __DIR__ . '/../src/ApiResponse.php';
require_once __DIR__ . '/../src/PatologiaCanonicalizer.php';
require_once __DIR__ . '/../src/PatologiaSource.php';
require_once __DIR__ . '/../src/CursorCodec.php';
require_once __DIR__ . '/../src/PatologiaApi.php';
require_once __DIR__ . '/FixturePatologiaSource.php';

use DriveAura\Remote\ApiResponse;
use DriveAura\Remote\CursorCodec;
use DriveAura\Remote\PatologiaApi;
use DriveAura\Remote\PatologiaCanonicalizer;
use DriveAura\Remote\Tests\FixturePatologiaSource;

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

/** @param array<string, mixed> $payload */
function signedCursor(array $payload, string $secret): string
{
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    $encoded = rtrim(strtr(base64_encode($json), '+/', '-_'), '=');
    $signature = hash_hmac('sha256', "drive-aura-cursor-v1\n" . $encoded, $secret, true);
    return $encoded . '.' . rtrim(strtr(base64_encode($signature), '+/', '-_'), '=');
}

$rows = [
    ['cod' => 'P003', 'nome' => 'Tre', 'criticita' => 3],
    ['cod' => 'P001', 'nome' => 'Uno', 'criticita' => 1],
    ['cod' => 'P002', 'nome' => 'Dùe', 'criticita' => 5],
];
$source = new FixturePatologiaSource($rows);
$now = 1_721_822_400;
$cursorSecret = 'test-cursor-secret';
$codec = new CursorCodec($cursorSecret, static function () use (&$now): int {
    return $now;
}, 300);
$api = new PatologiaApi(
    $source,
    'test-api-secret',
    $codec,
    static fn (): string => '2026-07-24T12:00:00Z'
);
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
assertError(405, 'METHOD_NOT_ALLOWED', $api->handle('POST', '/api/v1/manifest', [], $auth), 'metodo errato');
assertError(404, 'NOT_FOUND', $api->handle('GET', '/api/v1/non-esiste', [], $auth), 'rotta assente');
assertError(
    400,
    'INVALID_REQUEST',
    $api->handle('GET', '/api/v1/manifest', ['unexpected' => '1'], $auth),
    'query manifest inattesa'
);

$manifest = $api->handle('GET', '/api/v1/manifest', [], $auth);
assertStatus(200, $manifest, 'manifest');
$expectedDatasetDigest = PatologiaCanonicalizer::sha256($rows);
assertSameValue('1.0', $manifest->body['apiVersion'] ?? null, 'manifest apiVersion');
assertSameValue($expectedDatasetDigest, $manifest->body['datasetId'] ?? null, 'manifest datasetId');
assertSameValue('2026-07-24T12:00:00Z', $manifest->body['generatedAt'] ?? null, 'manifest generatedAt');
assertSameValue(['patologia'], $manifest->body['entityOrder'] ?? null, 'manifest entityOrder');
assertSameValue(100, $manifest->body['maxBatchSize'] ?? null, 'manifest maxBatchSize');
assertSameValue('patologia', $manifest->body['entities'][0]['entity'] ?? null, 'manifest entity');
assertSameValue(3, $manifest->body['entities'][0]['rowCount'] ?? null, 'manifest rowCount');
assertSameValue($expectedDatasetDigest, $manifest->body['entities'][0]['digest'] ?? null, 'manifest digest');

$first = $api->handle('GET', '/api/v1/export/patologia', ['limit' => '2'], $auth);
assertStatus(200, $first, 'prima pagina');
assertSameValue(null, $first->body['cursor'] ?? null, 'prima pagina cursor');
assertSameValue(2, $first->body['rowCount'] ?? null, 'prima pagina rowCount');
assertSameValue(true, $first->body['hasMore'] ?? null, 'prima pagina hasMore');
assertSameValue('P001', $first->body['rows'][0]['cod'] ?? null, 'prima pagina ordine 1');
assertSameValue('P002', $first->body['rows'][1]['cod'] ?? null, 'prima pagina ordine 2');
assertSameValue(
    PatologiaCanonicalizer::sha256($first->body['rows']),
    $first->body['digest'] ?? null,
    'prima pagina digest'
);
if (!is_string($first->body['nextCursor'] ?? null) || $first->body['nextCursor'] === '') {
    failTest('Prima pagina: nextCursor assente.');
}

$cursor = $first->body['nextCursor'];
$second = $api->handle(
    'GET',
    '/api/v1/export/patologia',
    ['limit' => '2', 'cursor' => $cursor],
    $auth
);
assertStatus(200, $second, 'seconda pagina');
assertSameValue($cursor, $second->body['cursor'] ?? null, 'seconda pagina cursor echo');
assertSameValue(1, $second->body['rowCount'] ?? null, 'seconda pagina rowCount');
assertSameValue(false, $second->body['hasMore'] ?? null, 'seconda pagina hasMore');
assertSameValue(null, $second->body['nextCursor'] ?? null, 'seconda pagina nextCursor');
assertSameValue('P003', $second->body['rows'][0]['cod'] ?? null, 'seconda pagina ordine');
assertSameValue(
    PatologiaCanonicalizer::sha256($second->body['rows']),
    $second->body['digest'] ?? null,
    'seconda pagina digest'
);

$defaultLimit = $api->handle('GET', '/api/v1/export/patologia', [], $auth);
assertStatus(200, $defaultLimit, 'limite predefinito');
assertSameValue(3, $defaultLimit->body['rowCount'] ?? null, 'limite predefinito rowCount');

assertError(
    400,
    'INVALID_ENTITY',
    $api->handle('GET', '/api/v1/export/ospedale', ['limit' => '1'], $auth),
    'entità non valida'
);
foreach (['0', '-1', '101', '1.0', 'abc', ' 1', str_repeat('9', 100)] as $invalidLimit) {
    assertError(
        400,
        'INVALID_LIMIT',
        $api->handle('GET', '/api/v1/export/patologia', ['limit' => $invalidLimit], $auth),
        'limite non valido ' . $invalidLimit
    );
}
assertError(
    400,
    'INVALID_LIMIT',
    $api->handle('GET', '/api/v1/export/patologia', ['limit' => ['1']], $auth),
    'limite array'
);
assertError(
    400,
    'INVALID_REQUEST',
    $api->handle('GET', '/api/v1/export/patologia', ['limit' => '1', 'other' => 'x'], $auth),
    'parametro export inatteso'
);
assertError(
    400,
    'INVALID_CURSOR',
    $api->handle('GET', '/api/v1/export/patologia', ['limit' => '1', 'cursor' => ''], $auth),
    'cursore vuoto'
);
assertError(
    400,
    'INVALID_CURSOR',
    $api->handle('GET', '/api/v1/export/patologia', ['limit' => '1', 'cursor' => ['x']], $auth),
    'cursore array'
);

foreach ([
    $cursor . 'x',
    substr($cursor, 0, -1),
    '*.' . str_repeat('A', 43),
    str_repeat('A', 1025),
] as $invalidCursor) {
    assertError(
        400,
        'INVALID_CURSOR',
        $api->handle(
            'GET',
            '/api/v1/export/patologia',
            ['limit' => '1', 'cursor' => $invalidCursor],
            $auth
        ),
        'cursore alterato'
    );
}

$malformedSignedCursor = signedCursor([
    'v' => 1,
    'entity' => 'patologia',
    'datasetId' => $expectedDatasetDigest,
    'after' => 'P001',
], $cursorSecret);
assertError(
    400,
    'INVALID_CURSOR',
    $api->handle(
        'GET',
        '/api/v1/export/patologia',
        ['limit' => '1', 'cursor' => $malformedSignedCursor],
        $auth
    ),
    'payload cursore incompleto'
);

$otherEntityCursor = $codec->encode('ospedale', $expectedDatasetDigest, 'P001');
assertError(
    400,
    'INVALID_CURSOR',
    $api->handle(
        'GET',
        '/api/v1/export/patologia',
        ['limit' => '1', 'cursor' => $otherEntityCursor],
        $auth
    ),
    'cursore altra entità'
);
$otherDatasetCursor = $codec->encode('patologia', str_repeat('0', 64), 'P001');
assertError(
    409,
    'DATASET_CHANGED',
    $api->handle(
        'GET',
        '/api/v1/export/patologia',
        ['limit' => '1', 'cursor' => $otherDatasetCursor],
        $auth
    ),
    'cursore altro dataset'
);

$expiryNow = 1000;
$expiryCodec = new CursorCodec(
    $cursorSecret,
    static function () use (&$expiryNow): int {
        return $expiryNow;
    },
    10
);
$expiredApi = new PatologiaApi(
    new FixturePatologiaSource($rows),
    'test-api-secret',
    $expiryCodec,
    static fn (): string => '2026-07-24T12:00:00Z'
);
$expiringPage = $expiredApi->handle('GET', '/api/v1/export/patologia', ['limit' => '1'], $auth);
assertStatus(200, $expiringPage, 'pagina con cursore a scadenza');
$expiryNow = 1011;
assertError(
    400,
    'INVALID_CURSOR',
    $expiredApi->handle(
        'GET',
        '/api/v1/export/patologia',
        ['limit' => '1', 'cursor' => $expiringPage->body['nextCursor']],
        $auth
    ),
    'cursore scaduto'
);

$source->rows[] = ['cod' => 'P004', 'nome' => 'Quattro', 'criticita' => 4];
assertError(
    409,
    'DATASET_CHANGED',
    $api->handle('GET', '/api/v1/export/patologia', ['limit' => '2', 'cursor' => $cursor], $auth),
    'dataset cambiato'
);

$emptyApi = new PatologiaApi(
    new FixturePatologiaSource([]),
    'test-api-secret',
    new CursorCodec($cursorSecret, static fn (): int => 1000),
    static fn (): string => '2026-07-24T12:00:00Z'
);
$emptyManifest = $emptyApi->handle('GET', '/api/v1/manifest', [], $auth);
$emptyDigest = hash('sha256', '');
assertStatus(200, $emptyManifest, 'manifest vuoto');
assertSameValue(0, $emptyManifest->body['entities'][0]['rowCount'] ?? null, 'manifest vuoto rowCount');
assertSameValue($emptyDigest, $emptyManifest->body['entities'][0]['digest'] ?? null, 'manifest vuoto digest');
$emptyExport = $emptyApi->handle('GET', '/api/v1/export/patologia', ['limit' => '10'], $auth);
assertStatus(200, $emptyExport, 'export vuoto');
assertSameValue([], $emptyExport->body['rows'] ?? null, 'export vuoto rows');
assertSameValue(0, $emptyExport->body['rowCount'] ?? null, 'export vuoto rowCount');
assertSameValue(false, $emptyExport->body['hasMore'] ?? null, 'export vuoto hasMore');
assertSameValue(null, $emptyExport->body['nextCursor'] ?? null, 'export vuoto nextCursor');
assertSameValue($emptyDigest, $emptyExport->body['digest'] ?? null, 'export vuoto digest');

$invalidSourceApi = new PatologiaApi(
    new FixturePatologiaSource([
        ['cod' => 'P001', 'nome' => 'Uno', 'criticita' => '1'],
    ]),
    'test-api-secret',
    new CursorCodec($cursorSecret, static fn (): int => 1000),
    static fn (): string => '2026-07-24T12:00:00Z'
);
assertError(
    500,
    'INVALID_SOURCE_DATA',
    $invalidSourceApi->handle('GET', '/api/v1/manifest', [], $auth),
    'riga sorgente non valida'
);

restore_error_handler();
echo "API Patologia PHP valida.\n";
