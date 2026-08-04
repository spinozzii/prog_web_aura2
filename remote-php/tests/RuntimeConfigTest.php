<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/ApiException.php';
require_once __DIR__ . '/../src/ApiResponse.php';
require_once __DIR__ . '/../src/RuntimeConfig.php';

use DriveAura\Remote\ApiException;
use DriveAura\Remote\ApiResponse;
use DriveAura\Remote\RuntimeConfig;

function configFail(string $message): never
{
    fwrite(STDERR, $message . "\n");
    exit(1);
}

function configSame(mixed $expected, mixed $actual, string $label): void
{
    if ($expected !== $actual) {
        configFail($label . ': valore inatteso.');
    }
}

function configWrite(string $directory, string $name, string $body): string
{
    $path = $directory . DIRECTORY_SEPARATOR . $name;
    if (file_put_contents($path, $body) === false) {
        configFail('Impossibile preparare la fixture temporanea.');
    }
    return $path;
}

function configExpectInvalid(string $path, string $privateValue): void
{
    try {
        RuntimeConfig::fromSources([], $path);
        configFail('Configurazione locale non valida accettata.');
    } catch (ApiException $error) {
        configSame(503, $error->httpStatus, 'stato configurazione locale');
        configSame('SERVICE_NOT_CONFIGURED', $error->errorCode, 'codice configurazione locale');
        $publicValues = [];
        $publicBody = ApiResponse::error($error)->body;
        array_walk_recursive(
            $publicBody,
            static function (mixed $value) use (&$publicValues): void {
                if (is_string($value)) {
                    $publicValues[] = $value;
                }
            }
        );
        $public = implode("\n", $publicValues);
        foreach ([$privateValue, $path, dirname($path)] as $private) {
            if ($private !== '' && str_contains($public, $private)) {
                configFail('La risposta pubblica contiene dettagli riservati.');
            }
        }
    }
}

$directory = sys_get_temp_dir() . DIRECTORY_SEPARATOR
    . 'drive-aura-runtime-config-' . bin2hex(random_bytes(8));
if (!mkdir($directory, 0700)) {
    configFail('Impossibile creare la directory temporanea.');
}

try {
    $valid = configWrite($directory, 'valid.php', <<<'PHP'
<?php
return [
    'REMOTE_DB_DSN' => 'mysql:host=local;dbname=test',
    'REMOTE_DB_USER' => 'local-user',
    'REMOTE_DB_PASSWORD' => '',
    'REMOTE_API_SECRET' => 'local-api-secret',
    'REMOTE_CURSOR_SECRET' => 'local-cursor-secret',
    'REMOTE_CURSOR_TTL_SECONDS' => '600',
    'REMOTE_DB_CONNECT_TIMEOUT_SECONDS' => '4',
    'REMOTE_DB_QUERY_TIMEOUT_SECONDS' => '9',
];
PHP);

    $config = RuntimeConfig::fromSources([
        'REMOTE_API_SECRET' => 'environment-api-secret',
        'REMOTE_DB_CONNECT_TIMEOUT_SECONDS' => '',
        'UNRELATED_VALUE' => 'ignored',
    ], $valid);
    configSame('environment-api-secret', $config->get('REMOTE_API_SECRET'), 'precedenza ambiente');
    configSame('', $config->get('REMOTE_DB_CONNECT_TIMEOUT_SECONDS'), 'vuoto ambiente esplicito');
    configSame('local-user', $config->get('REMOTE_DB_USER'), 'fallback file');
    configSame('', $config->get('REMOTE_DB_PASSWORD'), 'password database facoltativa');
    configSame('600', $config->get('REMOTE_CURSOR_TTL_SECONDS'), 'fallback TTL');
    configSame(8, count($config->all()), 'whitelist completa');

    $completeEnvironment = [
        'REMOTE_DB_DSN' => 'mysql:host=environment;dbname=test',
        'REMOTE_DB_USER' => 'environment-user',
        'REMOTE_DB_PASSWORD' => 'environment-password',
        'REMOTE_API_SECRET' => 'environment-api-secret',
        'REMOTE_CURSOR_SECRET' => 'environment-cursor-secret',
        'REMOTE_CURSOR_TTL_SECONDS' => '700',
        'REMOTE_DB_CONNECT_TIMEOUT_SECONDS' => '5',
        'REMOTE_DB_QUERY_TIMEOUT_SECONDS' => '10',
    ];
    $ignoredFile = configWrite(
        $directory,
        'ignored.php',
        "<?php echo 'file-must-not-run'; return 'invalid';\n"
    );
    ob_start();
    $environmentOnly = RuntimeConfig::fromSources($completeEnvironment, $ignoredFile);
    $ignoredOutput = (string) ob_get_clean();
    configSame('', $ignoredOutput, 'file non letto con ambiente completo');
    configSame(
        'environment-user',
        $environmentOnly->get('REMOTE_DB_USER'),
        'ambiente completo'
    );

    $missing = RuntimeConfig::fromSources([], $directory . DIRECTORY_SEPARATOR . 'missing.php');
    configSame(false, $missing->get('REMOTE_API_SECRET'), 'valore mancante');

    try {
        RuntimeConfig::fromSources(['REMOTE_API_SECRET' => 123], null);
        configFail('Tipo ambiente non valido accettato.');
    } catch (ApiException $error) {
        configSame('SERVICE_NOT_CONFIGURED', $error->errorCode, 'tipo ambiente non valido');
    }

    try {
        $missing->get('UNRELATED_VALUE');
        configFail('Accesso fuori whitelist accettato.');
    } catch (LogicException) {
        // Expected.
    }

    $unknownSecret = 'do-not-expose-unknown-secret';
    $unknown = configWrite(
        $directory,
        'unknown.php',
        "<?php return ['REMOTE_API_SECRET' => 'valid', 'UNKNOWN_SECRET' => '"
            . $unknownSecret . "'];\n"
    );
    configExpectInvalid($unknown, $unknownSecret);

    $invalidTypeSecret = 'do-not-expose-nested-secret';
    $invalidType = configWrite(
        $directory,
        'invalid-type.php',
        "<?php return ['REMOTE_DB_PASSWORD' => ['" . $invalidTypeSecret . "']];\n"
    );
    configExpectInvalid($invalidType, $invalidTypeSecret);

    $placeholderSecret = 'replace-with-a-real-secret';
    $placeholder = configWrite(
        $directory,
        'placeholder.php',
        "<?php return ['REMOTE_API_SECRET' => '" . $placeholderSecret . "'];\n"
    );
    configExpectInvalid($placeholder, $placeholderSecret);

    $empty = configWrite(
        $directory,
        'empty.php',
        "<?php return ['REMOTE_API_SECRET' => ''];\n"
    );
    configExpectInvalid($empty, 'empty.php');

    $unsafeSecret = 'do-not-expose-output-secret';
    $unsafeReturn = configWrite(
        $directory,
        'unsafe-return.php',
        "<?php echo '" . $unsafeSecret . "'; return 'not-an-array';\n"
    );
    ob_start();
    configExpectInvalid($unsafeReturn, $unsafeSecret);
    $leakedOutput = (string) ob_get_clean();
    configSame('', $leakedOutput, 'output file locale scartato');

    $syntaxSecret = 'do-not-expose-syntax-secret';
    $syntaxError = configWrite(
        $directory,
        'syntax-error.php',
        "<?php return ['REMOTE_API_SECRET' => '" . $syntaxSecret . "'\n"
    );
    configExpectInvalid($syntaxError, $syntaxSecret);
} finally {
    foreach (glob($directory . DIRECTORY_SEPARATOR . '*.php') ?: [] as $file) {
        unlink($file);
    }
    rmdir($directory);
}

echo "Configurazione runtime PHP valida.\n";
