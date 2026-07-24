<?php

declare(strict_types=1);

namespace DriveAura\Remote;

use PDO;

/**
 * Read-only MySQL/MariaDB adapter driven exclusively by the schema whitelist.
 */
final class PdoEntitySource implements EntitySource
{
    private const MAX_PAGE_FETCH = 101;

    private ?PDO $pdo;

    /** @var array{dsn: mixed, user: mixed, password: mixed}|null */
    private ?array $connectionConfig;

    /** @param array{dsn: mixed, user: mixed, password: mixed}|null $connectionConfig */
    public function __construct(?PDO $pdo = null, ?array $connectionConfig = null)
    {
        if (($pdo === null) === ($connectionConfig === null)) {
            throw new \InvalidArgumentException('Configurare PDO oppure i parametri di connessione.');
        }
        $this->pdo = $pdo;
        $this->connectionConfig = $connectionConfig;
    }

    public static function fromEnvironment(): self
    {
        return new self(null, [
            'dsn' => getenv('REMOTE_DB_DSN'),
            'user' => getenv('REMOTE_DB_USER'),
            'password' => getenv('REMOTE_DB_PASSWORD'),
        ]);
    }

    public function allRows(EntitySchema $schema): array
    {
        $sql = 'SELECT ' . $this->selectFields($schema)
            . ' FROM ' . self::identifier($schema->table)
            . ' ORDER BY ' . $this->orderBy($schema);
        return $this->execute($schema, $sql, [], true, null);
    }

    public function rowsAfter(EntitySchema $schema, ?array $after, int $limit): array
    {
        if ($limit < 1 || $limit > self::MAX_PAGE_FETCH) {
            throw new \InvalidArgumentException('Limite interno non valido.');
        }

        $parameters = [];
        $sql = 'SELECT ' . $this->selectFields($schema)
            . ' FROM ' . self::identifier($schema->table);
        $normalizedAfter = null;
        if ($after !== null) {
            $normalizedAfter = $schema->normalizeKeyTuple($after);
            $sql .= ' WHERE ' . $this->keysetCondition($schema, $normalizedAfter, $parameters);
        }
        $sql .= ' ORDER BY ' . $this->orderBy($schema) . ' LIMIT :page_limit';
        $parameters[':page_limit'] = [$limit, PDO::PARAM_INT];

        return $this->execute($schema, $sql, $parameters, true, $normalizedAfter);
    }

    private function selectFields(EntitySchema $schema): string
    {
        return implode(', ', array_map(
            static fn (string $field): string => self::identifier($field),
            $schema->fieldNames()
        ));
    }

    private function orderBy(EntitySchema $schema): string
    {
        $parts = [];
        foreach ($schema->keyFields as $fieldName) {
            $field = $schema->field($fieldName);
            $parts[] = $this->keyExpression($field, self::identifier($fieldName)) . ' ASC';
        }
        return implode(', ', $parts);
    }

    /**
     * Expands tuple comparison into portable lexicographic OR terms.
     * Each occurrence gets a distinct placeholder because native PDO MySQL
     * prepared statements cannot reuse a named parameter.
     *
     * @param list<string|int> $after
     * @param array<string, array{0: string|int, 1: int}> $parameters
     */
    private function keysetCondition(EntitySchema $schema, array $after, array &$parameters): string
    {
        $terms = [];
        $placeholderIndex = 0;
        foreach ($schema->keyFields as $greaterIndex => $fieldName) {
            $parts = [];
            for ($equalIndex = 0; $equalIndex < $greaterIndex; $equalIndex++) {
                $equalName = $schema->keyFields[$equalIndex];
                $equalField = $schema->field($equalName);
                $placeholder = ':key_' . $placeholderIndex++;
                $parts[] = $this->comparison(
                    $equalField,
                    self::identifier($equalName),
                    '=',
                    $placeholder
                );
                $parameters[$placeholder] = [
                    $after[$equalIndex],
                    $equalField['type'] === 'integer' ? PDO::PARAM_INT : PDO::PARAM_STR,
                ];
            }

            $field = $schema->field($fieldName);
            $placeholder = ':key_' . $placeholderIndex++;
            $parts[] = $this->comparison(
                $field,
                self::identifier($fieldName),
                '>',
                $placeholder
            );
            $parameters[$placeholder] = [
                $after[$greaterIndex],
                $field['type'] === 'integer' ? PDO::PARAM_INT : PDO::PARAM_STR,
            ];
            $terms[] = '(' . implode(' AND ', $parts) . ')';
        }
        return implode(' OR ', $terms);
    }

    /** @param array<string, mixed> $field */
    private function comparison(array $field, string $column, string $operator, string $placeholder): string
    {
        return $this->keyExpression($field, $column)
            . ' ' . $operator . ' '
            . $this->keyExpression($field, $placeholder);
    }

    /** @param array<string, mixed> $field */
    private function keyExpression(array $field, string $expression): string
    {
        return $field['type'] === 'string'
            ? 'CAST(' . $expression . ' AS BINARY)'
            : $expression;
    }

    /**
     * @param array<string, array{0: string|int, 1: int}> $parameters
     * @param list<string|int>|null $after
     * @return list<array<string, mixed>>
     */
    private function execute(
        EntitySchema $schema,
        string $sql,
        array $parameters,
        bool $requireSorted,
        ?array $after
    ): array {
        try {
            $statement = $this->connection()->prepare($sql);
            foreach ($parameters as $placeholder => [$value, $type]) {
                $statement->bindValue($placeholder, $value, $type);
            }
            $statement->execute();
            $rows = $statement->fetchAll();
            if (!is_array($rows)) {
                throw new \RuntimeException();
            }
            return $schema->normalizeRows($rows, $requireSorted, $after, true);
        } catch (ApiException $error) {
            throw $error;
        } catch (\Throwable) {
            throw new ApiException(
                503,
                'SOURCE_UNAVAILABLE',
                'La sorgente dati remota non è disponibile.'
            );
        }
    }

    private function connection(): PDO
    {
        if ($this->pdo !== null) {
            return $this->pdo;
        }

        $config = $this->connectionConfig;
        $dsn = $config['dsn'] ?? null;
        if (!is_string($dsn) || $dsn === '' || strncmp($dsn, 'mysql:', 6) !== 0) {
            throw new ApiException(
                503,
                'SERVICE_NOT_CONFIGURED',
                'Il database remoto non è configurato.'
            );
        }
        if (stripos($dsn, 'charset=') === false) {
            $dsn .= substr($dsn, -1) === ';' ? 'charset=utf8mb4' : ';charset=utf8mb4';
        }

        try {
            $this->pdo = new PDO(
                $dsn,
                is_string($config['user'] ?? null) ? $config['user'] : '',
                is_string($config['password'] ?? null) ? $config['password'] : '',
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_EMULATE_PREPARES => false,
                    PDO::ATTR_STRINGIFY_FETCHES => false,
                ]
            );
        } catch (\Throwable) {
            throw new ApiException(
                503,
                'SOURCE_UNAVAILABLE',
                'La sorgente dati remota non è disponibile.'
            );
        }
        $this->connectionConfig = null;
        return $this->pdo;
    }

    private static function identifier(string $identifier): string
    {
        if (preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $identifier) !== 1) {
            throw new \LogicException('Identificatore SQL fuori whitelist.');
        }
        return '`' . $identifier . '`';
    }
}
