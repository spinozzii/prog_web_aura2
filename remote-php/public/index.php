<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/HealthResponse.php';
require_once __DIR__ . '/../src/ApiException.php';
require_once __DIR__ . '/../src/ApiResponse.php';
require_once __DIR__ . '/../src/EntitySchema.php';
require_once __DIR__ . '/../src/SchemaRegistry.php';
require_once __DIR__ . '/../src/EntityCanonicalizer.php';
require_once __DIR__ . '/../src/EntitySource.php';
require_once __DIR__ . '/../src/PdoTimeoutPolicy.php';
require_once __DIR__ . '/../src/PdoEntitySource.php';
require_once __DIR__ . '/../src/DatasetIdentity.php';
require_once __DIR__ . '/../src/CursorCodec.php';
require_once __DIR__ . '/../src/MigrationApi.php';

use DriveAura\Remote\ApiException;
use DriveAura\Remote\ApiResponse;
use DriveAura\Remote\CursorCodec;
use DriveAura\Remote\HealthResponse;
use DriveAura\Remote\MigrationApi;
use DriveAura\Remote\PdoEntitySource;
use DriveAura\Remote\SchemaRegistry;

ini_set('display_errors', '0');
header('Content-Type: application/json; charset=utf-8');

$requestUri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
$parsedPath = parse_url($requestUri, PHP_URL_PATH);
$path = is_string($parsedPath) ? (rtrim($parsedPath, '/') ?: '/') : '/';
$publicRoot = realpath(__DIR__);
$scriptFilename = realpath((string) ($_SERVER['SCRIPT_FILENAME'] ?? ''));
$scriptPath = parse_url((string) ($_SERVER['SCRIPT_NAME'] ?? ''), PHP_URL_PATH);
if (is_string($publicRoot) && is_string($scriptFilename)
    && is_string($scriptPath) && strncmp($scriptFilename, $publicRoot, strlen($publicRoot)) === 0) {
    $relativeScript = str_replace('\\', '/', substr($scriptFilename, strlen($publicRoot)));
    if ($relativeScript !== '' && strlen($scriptPath) >= strlen($relativeScript)
        && substr($scriptPath, -strlen($relativeScript)) === $relativeScript) {
        $basePath = rtrim(substr($scriptPath, 0, -strlen($relativeScript)), '/');
        if ($basePath !== '' && ($path === $basePath
            || strncmp($path, $basePath . '/', strlen($basePath) + 1) === 0)) {
            $path = substr($path, strlen($basePath)) ?: '/';
        }
    }
}
$method = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($method === 'GET' && $path === '/health') {
    http_response_code(200);
    echo json_encode(
        HealthResponse::body(),
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
            | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR
    );
    exit;
}

header('Cache-Control: no-store');

try {
    $headers = [];
    $rawHeaders = function_exists('getallheaders') ? getallheaders() : [];
    if (is_array($rawHeaders)) {
        foreach ($rawHeaders as $name => $value) {
            if (is_string($name) && is_string($value)) {
                $headers[strtolower($name)] = $value;
            }
        }
    }
    foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION'] as $serverName) {
        if (isset($_SERVER[$serverName]) && is_string($_SERVER[$serverName])) {
            $headers['authorization'] = $_SERVER[$serverName];
            break;
        }
    }

    $query = [];
    foreach ($_GET as $name => $value) {
        $query[(string) $name] = $value;
    }

    $apiSecret = getenv('REMOTE_API_SECRET');
    $cursorSecret = getenv('REMOTE_CURSOR_SECRET');
    $rawCursorTtl = getenv('REMOTE_CURSOR_TTL_SECONDS');
    $cursorTtl = 900;
    if ($rawCursorTtl !== false && $rawCursorTtl !== '') {
        if (!is_string($rawCursorTtl) || preg_match('/\A[1-9][0-9]*\z/D', $rawCursorTtl) !== 1) {
            throw new ApiException(503, 'SERVICE_NOT_CONFIGURED', 'La durata dei cursori non è configurata correttamente.');
        }
        $cursorTtl = (int) $rawCursorTtl;
    }

    $cursorCodec = new CursorCodec(is_string($cursorSecret) ? $cursorSecret : '', null, $cursorTtl);
    $registry = SchemaRegistry::fromFile(dirname(__DIR__, 2) . '/shared/entity-schema.json');
    $api = new MigrationApi(
        PdoEntitySource::fromEnvironment(),
        $registry,
        is_string($apiSecret) ? $apiSecret : '',
        $cursorCodec,
        static fn (): string => gmdate('Y-m-d\TH:i:s\Z')
    );
    $response = $api->handle($method, $path, $query, $headers);
} catch (ApiException $error) {
    $response = ApiResponse::error($error);
} catch (Throwable) {
    $response = ApiResponse::error(
        new ApiException(500, 'INTERNAL_ERROR', 'Errore interno del servizio remoto.')
    );
}

if ($response->status === 401) {
    header('WWW-Authenticate: Bearer');
}
if ($response->status === 405) {
    header('Allow: GET');
}
http_response_code($response->status);
echo json_encode(
    $response->body,
    JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR
);
