<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Loads and validates the executable entity whitelist shared by all layers. */
final class SchemaRegistry
{
    /** @param array<string, EntitySchema> $entities */
    private function __construct(
        private readonly array $entities,
        private readonly array $entityOrder
    ) {
    }

    public static function fromFile(string $path): self
    {
        try {
            $raw = file_get_contents($path);
            if (!is_string($raw)) {
                throw new \RuntimeException();
            }
            $document = json_decode($raw, true, 64, JSON_THROW_ON_ERROR);
            return self::fromArray($document);
        } catch (ApiException $error) {
            throw $error;
        } catch (\Throwable) {
            throw self::invalidSchema();
        }
    }

    /** @param mixed $document */
    public static function fromArray(mixed $document): self
    {
        if (
            !is_array($document)
            || ($document['apiVersion'] ?? null) !== '1.0'
            || !isset($document['entityOrder'], $document['entities'])
            || !is_array($document['entityOrder'])
            || !array_is_list($document['entityOrder'])
            || !is_array($document['entities'])
        ) {
            throw self::invalidSchema();
        }

        $order = [];
        $entities = [];
        foreach ($document['entityOrder'] as $name) {
            if (
                !is_string($name)
                || preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $name) !== 1
                || isset($entities[$name])
                || !isset($document['entities'][$name])
                || !is_array($document['entities'][$name])
            ) {
                throw self::invalidSchema();
            }
            $definition = $document['entities'][$name];
            $table = $definition['table'] ?? null;
            $key = $definition['key'] ?? null;
            $fields = $definition['fields'] ?? null;
            if (
                !is_string($table)
                || preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $table) !== 1
                || !is_array($key)
                || !array_is_list($key)
                || $key === []
                || !is_array($fields)
                || !array_is_list($fields)
                || $fields === []
            ) {
                throw self::invalidSchema();
            }

            $normalizedFields = [];
            $fieldNames = [];
            foreach ($fields as $field) {
                if (!is_array($field)) {
                    throw self::invalidSchema();
                }
                $fieldName = $field['name'] ?? null;
                $type = $field['type'] ?? null;
                if (
                    !is_string($fieldName)
                    || preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $fieldName) !== 1
                    || isset($fieldNames[$fieldName])
                    || !is_string($type)
                    || !in_array($type, ['string', 'integer', 'date', 'decimal2'], true)
                ) {
                    throw self::invalidSchema();
                }
                self::validateFieldOptions($field, $type);
                $fieldNames[$fieldName] = true;
                $normalizedFields[] = $field;
            }

            foreach ($key as $keyField) {
                if (
                    !is_string($keyField)
                    || !isset($fieldNames[$keyField])
                    || (!in_array(self::fieldType($normalizedFields, $keyField), ['string', 'integer'], true))
                ) {
                    throw self::invalidSchema();
                }
            }

            $entities[$name] = new EntitySchema($name, $table, $normalizedFields, $key);
            $order[] = $name;
        }

        if (count($entities) !== count($document['entities'])) {
            throw self::invalidSchema();
        }
        return new self($entities, $order);
    }

    /** @return list<string> */
    public function order(): array
    {
        return $this->entityOrder;
    }

    public function has(string $name): bool
    {
        return isset($this->entities[$name]);
    }

    public function get(string $name): EntitySchema
    {
        if (!isset($this->entities[$name])) {
            throw new ApiException(400, 'INVALID_ENTITY', 'Entità non ammessa.');
        }
        return $this->entities[$name];
    }

    /** @return list<EntitySchema> */
    public function all(): array
    {
        $result = [];
        foreach ($this->entityOrder as $name) {
            $result[] = $this->entities[$name];
        }
        return $result;
    }

    /** @param list<array<string, mixed>> $fields */
    private static function fieldType(array $fields, string $name): string
    {
        foreach ($fields as $field) {
            if ($field['name'] === $name) {
                return $field['type'];
            }
        }
        throw self::invalidSchema();
    }

    /** @param array<string, mixed> $field */
    private static function validateFieldOptions(array $field, string $type): void
    {
        $allowed = match ($type) {
            'string' => ['name', 'type', 'minLength', 'maxLength'],
            'integer' => ['name', 'type', 'minimum', 'maximum'],
            'date' => ['name', 'type'],
            'decimal2' => ['name', 'type', 'minimum'],
            default => [],
        };
        if (array_diff(array_keys($field), $allowed) !== []) {
            throw self::invalidSchema();
        }

        if ($type === 'string') {
            if (
                (isset($field['minLength']) && (!is_int($field['minLength']) || $field['minLength'] < 0))
                || (isset($field['maxLength']) && (!is_int($field['maxLength']) || $field['maxLength'] < 1))
                || (
                    isset($field['minLength'], $field['maxLength'])
                    && $field['minLength'] > $field['maxLength']
                )
            ) {
                throw self::invalidSchema();
            }
            return;
        }
        if ($type === 'integer') {
            if (
                (isset($field['minimum']) && !is_int($field['minimum']))
                || (isset($field['maximum']) && !is_int($field['maximum']))
                || (
                    isset($field['minimum'], $field['maximum'])
                    && $field['minimum'] > $field['maximum']
                )
            ) {
                throw self::invalidSchema();
            }
            return;
        }
        if ($type === 'decimal2' && (($field['minimum'] ?? null) !== '0.00')) {
            throw self::invalidSchema();
        }
    }

    private static function invalidSchema(): ApiException
    {
        return new ApiException(
            500,
            'INVALID_SCHEMA',
            'Lo schema delle entità non è valido.'
        );
    }
}
