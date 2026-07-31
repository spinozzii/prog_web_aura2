<?php

declare(strict_types=1);

namespace DriveAura\Remote;

use PDO;

/** Finite PDO connection and server-side SELECT limits. */
final class PdoTimeoutPolicy
{
    private const DEFAULT_CONNECT_SECONDS = 3;
    private const DEFAULT_QUERY_SECONDS = 8;

    private function __construct(
        public readonly int $connectSeconds,
        public readonly int $querySeconds
    ) {
    }

    public static function fromEnvironment(): self
    {
        return self::fromArray([
            'REMOTE_DB_CONNECT_TIMEOUT_SECONDS' => getenv('REMOTE_DB_CONNECT_TIMEOUT_SECONDS'),
            'REMOTE_DB_QUERY_TIMEOUT_SECONDS' => getenv('REMOTE_DB_QUERY_TIMEOUT_SECONDS'),
        ]);
    }

    /** @param array<string, mixed> $environment */
    public static function fromArray(array $environment): self
    {
        return new self(
            self::readInteger(
                $environment,
                'REMOTE_DB_CONNECT_TIMEOUT_SECONDS',
                self::DEFAULT_CONNECT_SECONDS,
                1,
                30
            ),
            self::readInteger(
                $environment,
                'REMOTE_DB_QUERY_TIMEOUT_SECONDS',
                self::DEFAULT_QUERY_SECONDS,
                1,
                120
            )
        );
    }

    /** @return array<int, int> */
    public function connectionOptions(): array
    {
        // ATTR_TIMEOUT is a driver-specific connection limit. It is not a
        // query deadline, which is applied separately below.
        return [PDO::ATTR_TIMEOUT => $this->connectSeconds];
    }

    public function limitSelect(PDO $pdo, string $sql): string
    {
        try {
            $driver = $pdo->getAttribute(PDO::ATTR_DRIVER_NAME);
            $version = $pdo->getAttribute(PDO::ATTR_SERVER_VERSION);
        } catch (\Throwable) {
            throw self::unsupported();
        }
        return $this->limitSelectForServer(
            is_string($driver) ? $driver : '',
            is_string($version) ? $version : '',
            $sql
        );
    }

    public function limitSelectForServer(string $driver, string $version, string $sql): string
    {
        if ($driver !== 'mysql' || strncmp($sql, 'SELECT ', 7) !== 0) {
            throw self::unsupported();
        }

        if (stripos($version, 'MariaDB') !== false) {
            $matched = preg_match(
                '/(?:\A|[^0-9])([0-9]+)\.([0-9]+)\.([0-9]+)-MariaDB(?:-|\z)/iD',
                $version,
                $match
            );
            if ($matched !== 1 || version_compare(
                $match[1] . '.' . $match[2] . '.' . $match[3],
                '10.1.1',
                '<'
            )) {
                throw self::unsupported();
            }
            return 'SET STATEMENT max_statement_time=' . $this->querySeconds
                . ' FOR ' . $sql;
        }

        if (preg_match('/\A([0-9]+)\.([0-9]+)\.([0-9]+)/D', $version, $match) !== 1
            || version_compare($match[1] . '.' . $match[2] . '.' . $match[3], '5.7.8', '<')) {
            throw self::unsupported();
        }
        return 'SELECT /*+ MAX_EXECUTION_TIME(' . ($this->querySeconds * 1000)
            . ') */ ' . substr($sql, 7);
    }

    /** @param array<string, mixed> $environment */
    private static function readInteger(
        array $environment,
        string $name,
        int $default,
        int $minimum,
        int $maximum
    ): int {
        if (!array_key_exists($name, $environment) || $environment[$name] === false) {
            return $default;
        }
        $raw = $environment[$name];
        if (!is_string($raw) || preg_match('/\A[1-9][0-9]*\z/D', $raw) !== 1) {
            throw self::invalid($name);
        }
        $value = (int) $raw;
        if ($value < $minimum || $value > $maximum) {
            throw self::invalid($name);
        }
        return $value;
    }

    private static function invalid(string $name): ApiException
    {
        return new ApiException(
            503,
            'SERVICE_NOT_CONFIGURED',
            'La configurazione timeout ' . $name . ' non è valida.'
        );
    }

    private static function unsupported(): ApiException
    {
        return new ApiException(
            503,
            'SOURCE_TIMEOUT_UNSUPPORTED',
            'La sorgente dati remota non supporta il limite di query richiesto.'
        );
    }
}
