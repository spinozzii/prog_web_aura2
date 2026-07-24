<?php

declare(strict_types=1);

namespace DriveAura\Remote\Tests;

use DriveAura\Remote\PatologiaSource;

/** Explicit test-only source; production always uses PdoPatologiaSource. */
final class FixturePatologiaSource implements PatologiaSource
{
    /** @param list<array{cod: string, nome: string, criticita: int}> $rows */
    public function __construct(public array $rows)
    {
    }

    public function allRows(): array
    {
        $rows = $this->rows;
        usort($rows, static fn (array $left, array $right): int => strcmp($left['cod'], $right['cod']));
        return $rows;
    }

    public function rowsAfter(?string $afterCod, int $limit): array
    {
        $rows = array_values(array_filter($this->allRows(), static fn (array $row): bool => $afterCod === null || strcmp($row['cod'], $afterCod) > 0));
        return array_slice($rows, 0, $limit);
    }
}
