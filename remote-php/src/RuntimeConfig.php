<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/**
 * Loads the fixed remote-service configuration without exporting secrets to
 * the process environment. Environment values always take precedence; the
 * server-only file supplies only keys which are genuinely absent.
 */
final class RuntimeConfig
{
    /** @var list<string> */
    private const KEYS = [
        'REMOTE_DB_DSN',
        'REMOTE_DB_USER',
        'REMOTE_DB_PASSWORD',
        'REMOTE_API_SECRET',
        'REMOTE_CURSOR_SECRET',
        'REMOTE_CURSOR_TTL_SECONDS',
        'REMOTE_DB_CONNECT_TIMEOUT_SECONDS',
        'REMOTE_DB_QUERY_TIMEOUT_SECONDS',
    ];

    /** @param array<string, string|false> $values */
    private function __construct(private readonly array $values)
    {
    }

    public static function fromEnvironment(?string $localFile = null): self
    {
        $environment = [];
        foreach (self::KEYS as $name) {
            $environment[$name] = getenv($name);
        }
        return self::fromSources(
            $environment,
            $localFile ?? dirname(__DIR__) . '/config/local.php'
        );
    }

    /**
     * Explicit source injection keeps the loader testable without mutating
     * the real process environment. Unknown environment keys are ignored;
     * unknown file keys are a configuration error.
     *
     * @param array<string, mixed> $environment
     */
    public static function fromSources(array $environment, ?string $localFile): self
    {
        $values = [];
        foreach (self::KEYS as $name) {
            $raw = array_key_exists($name, $environment) ? $environment[$name] : false;
            if ($raw !== false && !is_string($raw)) {
                throw self::invalid();
            }
            $values[$name] = $raw;
        }

        $local = in_array(false, $values, true)
            ? self::loadLocalFile($localFile)
            : [];
        foreach ($local as $name => $value) {
            if ($values[$name] === false) {
                if (!is_string($value)
                    || ($value === '' && $name !== 'REMOTE_DB_PASSWORD')
                    || strncmp($value, 'replace-with-', 13) === 0) {
                    throw self::invalid();
                }
                $values[$name] = $value;
            }
        }
        return new self($values);
    }

    public function get(string $name): string|false
    {
        if (!in_array($name, self::KEYS, true)) {
            throw new \LogicException('Chiave di configurazione fuori whitelist.');
        }
        return $this->values[$name];
    }

    /** @return array<string, string|false> */
    public function all(): array
    {
        return $this->values;
    }

    /** @return array<string, mixed> */
    private static function loadLocalFile(?string $localFile): array
    {
        if ($localFile === null || !file_exists($localFile)) {
            return [];
        }
        if (!is_file($localFile) || !is_readable($localFile)) {
            throw self::invalid();
        }

        $outputLevel = ob_get_level();
        if (!ob_start()) {
            throw self::invalid();
        }
        try {
            $loaded = (static function (string $path): mixed {
                return require $path;
            })($localFile);
        } catch (\Throwable) {
            throw self::invalid();
        } finally {
            $buffersToClose = ob_get_level() - $outputLevel;
            for ($index = 0; $index < $buffersToClose; $index++) {
                ob_end_clean();
            }
        }

        if (!is_array($loaded)) {
            throw self::invalid();
        }
        $values = [];
        foreach ($loaded as $name => $value) {
            if (!is_string($name) || !in_array($name, self::KEYS, true)) {
                throw self::invalid();
            }
            $values[$name] = $value;
        }
        return $values;
    }

    private static function invalid(): ApiException
    {
        return new ApiException(
            503,
            'SERVICE_NOT_CONFIGURED',
            'La configurazione locale del servizio non è valida.'
        );
    }
}
