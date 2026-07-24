<?php

declare(strict_types=1);

namespace DriveAura\Remote;

interface PatologiaSource
{
    /** @return list<array{cod: string, nome: string, criticita: int}> */
    public function allRows(): array;

    /** @return list<array{cod: string, nome: string, criticita: int}> */
    public function rowsAfter(?string $afterCod, int $limit): array;
}
