<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/**
 * Immutable executable view of one entity from the shared schema.
 *
 * Identifiers are validated when the registry is loaded and never originate
 * from an HTTP request. Values are normalized here so PDO, fixtures and the
 * canonicalizer share exactly the same contract.
 */
final class EntitySchema
{
    /**
     * @param list<array<string, mixed>> $fields
     * @param list<string> $keyFields
     */
    public function __construct(
        public readonly string $name,
        public readonly string $table,
        public readonly array $fields,
        public readonly array $keyFields
    ) {
    }

    /** @return list<string> */
    public function fieldNames(): array
    {
        return array_map(static fn (array $field): string => $field['name'], $this->fields);
    }

    /** @return array<string, mixed> */
    public function field(string $name): array
    {
        foreach ($this->fields as $field) {
            if ($field['name'] === $name) {
                return $field;
            }
        }
        throw new \LogicException('Campo non presente nello schema.');
    }

    /**
     * @param array<mixed> $rows
     * @param list<mixed>|null $after
     * @return list<array<string, mixed>>
     */
    public function normalizeRows(
        array $rows,
        bool $requireSorted = false,
        ?array $after = null,
        bool $databaseValues = false
    ): array {
        if (!array_is_list($rows)) {
            $this->invalidSource();
        }

        $result = [];
        $seen = [];
        $previous = $after;
        foreach ($rows as $rawRow) {
            if (!is_array($rawRow)) {
                $this->invalidSource();
            }
            $row = $this->normalizeRow($rawRow, $databaseValues);
            $key = $this->keyOf($row);
            $identity = self::keyIdentity($key);
            if (isset($seen[$identity])) {
                $this->invalidSource();
            }
            if ($requireSorted && $previous !== null && $this->compareKeys($key, $previous) <= 0) {
                $this->invalidSource();
            }
            $seen[$identity] = true;
            $previous = $key;
            $result[] = $row;
        }

        return $result;
    }

    /**
     * @param array<mixed> $rawRow
     * @return array<string, mixed>
     */
    public function normalizeRow(array $rawRow, bool $databaseValues = false): array
    {
        if (count($rawRow) !== count($this->fields)) {
            $this->invalidSource();
        }

        $row = [];
        foreach ($this->fields as $field) {
            $name = $field['name'];
            if (!array_key_exists($name, $rawRow)) {
                $this->invalidSource();
            }
            $row[$name] = $this->normalizeValue($field, $rawRow[$name], $databaseValues, false);
        }

        return $row;
    }

    /**
     * @param list<mixed> $tuple
     * @return list<string|int>
     */
    public function normalizeKeyTuple(array $tuple): array
    {
        if (!array_is_list($tuple) || count($tuple) !== count($this->keyFields)) {
            throw new \InvalidArgumentException('Tupla del cursore non valida.');
        }

        $result = [];
        foreach ($this->keyFields as $index => $fieldName) {
            $result[] = $this->normalizeValue($this->field($fieldName), $tuple[$index], false, true);
        }
        return $result;
    }

    /**
     * @param array<string, mixed> $row
     * @return list<string|int>
     */
    public function keyOf(array $row): array
    {
        $key = [];
        foreach ($this->keyFields as $field) {
            if (!array_key_exists($field, $row) || (!is_string($row[$field]) && !is_int($row[$field]))) {
                throw new \LogicException('Riga normalizzata senza chiave valida.');
            }
            $key[] = $row[$field];
        }
        return $key;
    }

    /**
     * @param list<string|int> $left
     * @param list<string|int> $right
     */
    public function compareKeys(array $left, array $right): int
    {
        if (count($left) !== count($this->keyFields) || count($right) !== count($this->keyFields)) {
            throw new \InvalidArgumentException('Tupla chiave non valida.');
        }
        foreach ($this->keyFields as $index => $fieldName) {
            $type = $this->field($fieldName)['type'];
            if ($type === 'integer') {
                if (!is_int($left[$index]) || !is_int($right[$index])) {
                    throw new \InvalidArgumentException('Componente numerica della chiave non valida.');
                }
                $comparison = $left[$index] <=> $right[$index];
            } else {
                if (!is_string($left[$index]) || !is_string($right[$index])) {
                    throw new \InvalidArgumentException('Componente testuale della chiave non valida.');
                }
                $comparison = strcmp($left[$index], $right[$index]);
            }
            if ($comparison !== 0) {
                return $comparison;
            }
        }
        return 0;
    }

    /**
     * @param list<array<string, mixed>> $rows
     * @return list<array<string, mixed>>
     */
    public function sorted(array $rows): array
    {
        usort(
            $rows,
            fn (array $left, array $right): int => $this->compareKeys(
                $this->keyOf($left),
                $this->keyOf($right)
            )
        );
        return $rows;
    }

    /** @param list<string|int> $key */
    public static function keyIdentity(array $key): string
    {
        return json_encode(
            $key,
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
                | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR
        );
    }

    /**
     * @param array<string, mixed> $field
     * @return string|int
     */
    private function normalizeValue(array $field, mixed $value, bool $databaseValue, bool $cursorValue): string|int
    {
        $type = $field['type'];
        if ($type === 'integer') {
            if ($databaseValue && is_string($value) && preg_match('/\A(?:0|[1-9][0-9]*)\z/D', $value) === 1) {
                $converted = (int) $value;
                if ((string) $converted !== $value) {
                    $this->invalidValue($cursorValue);
                }
                $value = $converted;
            }
            if (!is_int($value)) {
                $this->invalidValue($cursorValue);
            }
            if (isset($field['minimum']) && $value < $field['minimum']) {
                $this->invalidValue($cursorValue);
            }
            if (isset($field['maximum']) && $value > $field['maximum']) {
                $this->invalidValue($cursorValue);
            }
            return $value;
        }

        if (!is_string($value) || strpos($value, "\0") !== false || preg_match('//u', $value) !== 1) {
            $this->invalidValue($cursorValue);
        }
        if (isset($field['minLength']) || isset($field['maxLength'])) {
            $length = preg_match_all('/./us', $value, $characters);
            if (
                $length === false
                || (isset($field['minLength']) && $length < $field['minLength'])
                || (isset($field['maxLength']) && $length > $field['maxLength'])
            ) {
                $this->invalidValue($cursorValue);
            }
        }

        if ($type === 'date') {
            if (preg_match('/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/D', $value, $parts) !== 1) {
                $this->invalidValue($cursorValue);
            }
            $year = (int) $parts[1];
            if ($year < 1 || !checkdate((int) $parts[2], (int) $parts[3], $year)) {
                $this->invalidValue($cursorValue);
            }
        } elseif ($type === 'decimal2') {
            if (preg_match('/\A(?:0|[1-9][0-9]*)\.[0-9]{2}\z/D', $value) !== 1) {
                $this->invalidValue($cursorValue);
            }
        } elseif ($type !== 'string') {
            throw new \LogicException('Tipo di campo non supportato.');
        }

        return $value;
    }

    private function invalidValue(bool $cursor): never
    {
        if ($cursor) {
            throw new \InvalidArgumentException('Tupla del cursore non valida.');
        }
        $this->invalidSource();
    }

    private function invalidSource(): never
    {
        throw new ApiException(
            500,
            'INVALID_SOURCE_DATA',
            'La sorgente remota non rispetta il contratto.'
        );
    }
}
