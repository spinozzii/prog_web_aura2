<?php

declare(strict_types=1);

namespace DriveAura\Remote;

interface EntitySource
{
    /** @return list<array<string, mixed>> */
    public function allRows(EntitySchema $schema): array;

    /**
     * @param list<string|int>|null $after
     * @return list<array<string, mixed>>
     */
    public function rowsAfter(EntitySchema $schema, ?array $after, int $limit): array;
}
