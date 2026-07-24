<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Canonical JSON and SHA-256 for the constrained patologia contract. */
final class PatologiaCanonicalizer
{
    /** @param list<array{cod: string, nome: string, criticita: int}> $rows */
    public static function canonicalize(array $rows): string
    {
        usort($rows, static fn (array $left, array $right): int => strcmp($left['cod'], $right['cod']));
        $lines = [];
        foreach ($rows as $row) {
            $lines[] = json_encode([
                'cod' => $row['cod'],
                'nome' => $row['nome'],
                'criticita' => $row['criticita'],
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        }
        return implode("\n", $lines) . "\n";
    }

    /** @param list<array{cod: string, nome: string, criticita: int}> $rows */
    public static function sha256(array $rows): string
    {
        return hash('sha256', self::canonicalize($rows));
    }
}
