<?php

declare(strict_types=1);

namespace DriveAura\Remote;

require_once __DIR__ . '/ApiException.php';
require_once __DIR__ . '/EntitySchema.php';
require_once __DIR__ . '/SchemaRegistry.php';
require_once __DIR__ . '/EntityCanonicalizer.php';

/** Backward-compatible facade for the original executable patologia vectors. */
final class PatologiaCanonicalizer
{
    private static ?EntitySchema $schema = null;

    /** @param list<array{cod: string, nome: string, criticita: int}> $rows */
    public static function canonicalize(array $rows): string
    {
        return EntityCanonicalizer::canonicalize(self::schema(), $rows);
    }

    /** @param list<array{cod: string, nome: string, criticita: int}> $rows */
    public static function sha256(array $rows): string
    {
        return EntityCanonicalizer::sha256(self::schema(), $rows);
    }

    private static function schema(): EntitySchema
    {
        if (self::$schema === null) {
            self::$schema = SchemaRegistry::fromFile(
                dirname(__DIR__, 2) . '/shared/entity-schema.json'
            )->get('patologia');
        }
        return self::$schema;
    }
}
