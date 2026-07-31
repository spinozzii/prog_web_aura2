<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/ApiException.php';
require_once __DIR__ . '/../src/ApiResponse.php';
require_once __DIR__ . '/../src/PdoTimeoutPolicy.php';

use DriveAura\Remote\ApiException;
use DriveAura\Remote\ApiResponse;
use DriveAura\Remote\PdoTimeoutPolicy;

function timeoutFail(string $message): never
{
    fwrite(STDERR, $message . "\n");
    exit(1);
}

function timeoutSame(mixed $expected, mixed $actual, string $label): void
{
    if ($expected !== $actual) {
        timeoutFail($label . ': valore inatteso.');
    }
}

$defaults = PdoTimeoutPolicy::fromArray([]);
timeoutSame(3, $defaults->connectSeconds, 'default connessione');
timeoutSame(8, $defaults->querySeconds, 'default query');
timeoutSame([PDO::ATTR_TIMEOUT => 3], $defaults->connectionOptions(), 'opzioni PDO');

$boundaries = PdoTimeoutPolicy::fromArray([
    'REMOTE_DB_CONNECT_TIMEOUT_SECONDS' => '30',
    'REMOTE_DB_QUERY_TIMEOUT_SECONDS' => '1',
]);
timeoutSame(30, $boundaries->connectSeconds, 'limite connessione');
timeoutSame(1, $boundaries->querySeconds, 'limite query');

foreach ([
    ['REMOTE_DB_CONNECT_TIMEOUT_SECONDS', ''],
    ['REMOTE_DB_CONNECT_TIMEOUT_SECONDS', '0'],
    ['REMOTE_DB_CONNECT_TIMEOUT_SECONDS', '31'],
    ['REMOTE_DB_CONNECT_TIMEOUT_SECONDS', ' 3'],
    ['REMOTE_DB_QUERY_TIMEOUT_SECONDS', '-1'],
    ['REMOTE_DB_QUERY_TIMEOUT_SECONDS', '1.5'],
    ['REMOTE_DB_QUERY_TIMEOUT_SECONDS', '121'],
] as [$name, $value]) {
    try {
        PdoTimeoutPolicy::fromArray([$name => $value]);
        timeoutFail('Configurazione non valida accettata: ' . $name);
    } catch (ApiException $error) {
        timeoutSame(503, $error->httpStatus, 'stato configurazione');
        timeoutSame('SERVICE_NOT_CONFIGURED', $error->errorCode, 'codice configurazione');
    }
}

timeoutSame(
    'SELECT /*+ MAX_EXECUTION_TIME(8000) */ 1',
    $defaults->limitSelectForServer('mysql', '8.0.36', 'SELECT 1'),
    'limite MySQL'
);
timeoutSame(
    'SET STATEMENT max_statement_time=8 FOR SELECT 1',
    $defaults->limitSelectForServer(
        'mysql',
        '5.5.5-10.11.8-MariaDB-0ubuntu0.22.04.1',
        'SELECT 1'
    ),
    'limite MariaDB'
);

foreach ([
    ['mysql', '5.7.7', 'SELECT 1'],
    ['mysql', '5.5.5-10.0.38-MariaDB-0ubuntu0.16.04.1', 'SELECT 1'],
    ['pgsql', '18.4', 'SELECT 1'],
    ['mysql', '8.0.36', 'UPDATE tabella SET valore=1'],
] as [$driver, $version, $sql]) {
    try {
        $defaults->limitSelectForServer($driver, $version, $sql);
        timeoutFail('Server o query non supportati accettati.');
    } catch (ApiException $error) {
        $response = ApiResponse::error($error);
        $public = json_encode($response->body, JSON_THROW_ON_ERROR);
        timeoutSame('SOURCE_TIMEOUT_UNSUPPORTED', $error->errorCode, 'codice supporto');
        foreach ([$version, $sql, 'password', 'dsn=', __DIR__] as $private) {
            if (str_contains($public, $private)) {
                timeoutFail('La risposta pubblica contiene dettagli riservati.');
            }
        }
    }
}

echo "Timeout PDO PHP validi.\n";
