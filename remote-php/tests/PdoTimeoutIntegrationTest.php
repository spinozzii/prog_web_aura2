<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/ApiException.php';
require_once __DIR__ . '/../src/ApiResponse.php';
require_once __DIR__ . '/../src/EntitySchema.php';
require_once __DIR__ . '/../src/SchemaRegistry.php';
require_once __DIR__ . '/../src/EntitySource.php';
require_once __DIR__ . '/../src/PdoTimeoutPolicy.php';
require_once __DIR__ . '/../src/PdoEntitySource.php';

use DriveAura\Remote\ApiException;
use DriveAura\Remote\ApiResponse;
use DriveAura\Remote\PdoEntitySource;
use DriveAura\Remote\PdoTimeoutPolicy;
use DriveAura\Remote\SchemaRegistry;

if (getenv('RUN_PDO_TIMEOUT_INTEGRATION') !== '1') {
    echo "SKIP: integrazione timeout PDO non richiesta.\n";
    exit(0);
}

$dsn = getenv('REMOTE_TEST_DB_DSN');
$user = getenv('REMOTE_TEST_DB_USER');
$password = getenv('REMOTE_TEST_DB_PASSWORD');
if (!is_string($dsn) || !str_starts_with($dsn, 'mysql:')) {
    fwrite(STDERR, "REMOTE_TEST_DB_DSN di test mancante.\n");
    exit(1);
}

$policy = PdoTimeoutPolicy::fromArray([
    'REMOTE_DB_CONNECT_TIMEOUT_SECONDS' => '1',
    'REMOTE_DB_QUERY_TIMEOUT_SECONDS' => '1',
]);
$pdo = new PDO(
    $dsn,
    is_string($user) ? $user : '',
    is_string($password) ? $password : '',
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION] + $policy->connectionOptions()
);
$limited = $policy->limitSelect($pdo, 'SELECT SLEEP(3) AS delayed_value');
$started = microtime(true);
$timedOut = false;
try {
    $pdo->query($limited);
} catch (PDOException) {
    $timedOut = true;
}
$elapsed = microtime(true) - $started;
if (!$timedOut || $elapsed > 2.5) {
    fwrite(STDERR, "La query lenta non e terminata entro il limite server.\n");
    exit(1);
}

$unreachablePort = getenv('REMOTE_TEST_UNREACHABLE_PORT');
if (!is_string($unreachablePort) || preg_match('/\A[1-9][0-9]*\z/D', $unreachablePort) !== 1) {
    fwrite(STDERR, "Porta irraggiungibile di test mancante.\n");
    exit(1);
}
putenv('REMOTE_DB_DSN=mysql:host=127.0.0.1;port=' . $unreachablePort . ';dbname=unreachable');
putenv('REMOTE_DB_USER=timeout-test-user');
putenv('REMOTE_DB_PASSWORD=timeout-test-password');
putenv('REMOTE_DB_CONNECT_TIMEOUT_SECONDS=1');
putenv('REMOTE_DB_QUERY_TIMEOUT_SECONDS=1');
$source = PdoEntitySource::fromEnvironment();
$registry = SchemaRegistry::fromFile(dirname(__DIR__, 2) . '/shared/entity-schema.json');
$connectStarted = microtime(true);
try {
    $source->allRows($registry->get('patologia'));
    fwrite(STDERR, "La connessione irraggiungibile non e stata rifiutata.\n");
    exit(1);
} catch (ApiException $error) {
    $connectElapsed = microtime(true) - $connectStarted;
    if ($connectElapsed > 3.0 || $error->httpStatus !== 503) {
        fwrite(STDERR, "Connessione irraggiungibile oltre deadline.\n");
        exit(1);
    }
    $public = json_encode(ApiResponse::error($error)->body, JSON_THROW_ON_ERROR);
    foreach (['timeout-test-user', 'timeout-test-password', 'unreachable', 'SELECT', __DIR__] as $private) {
        if (str_contains($public, $private)) {
            fwrite(STDERR, "Risposta PDO non sanitizzata.\n");
            exit(1);
        }
    }
}

echo "PASS: timeout query e connessione PDO reali; query="
    . number_format($elapsed, 3, '.', '') . "s.\n";
