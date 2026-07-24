<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Canonical JSON Lines and SHA-256 for every entity in the shared schema. */
final class EntityCanonicalizer
{
    /** @param array<mixed> $rows */
    public static function canonicalize(EntitySchema $schema, array $rows): string
    {
        $normalized = $schema->normalizeRows($rows);
        if ($normalized === []) {
            return '';
        }

        $lines = [];
        foreach ($schema->sorted($normalized) as $row) {
            $ordered = [];
            foreach ($schema->fieldNames() as $field) {
                $ordered[$field] = $row[$field];
            }
            $lines[] = json_encode(
                $ordered,
                JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
                    | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR
            );
        }
        return implode("\n", $lines) . "\n";
    }

    /** @param array<mixed> $rows */
    public static function sha256(EntitySchema $schema, array $rows): string
    {
        return hash('sha256', self::canonicalize($schema, $rows));
    }
}
