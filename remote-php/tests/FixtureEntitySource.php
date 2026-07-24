<?php

declare(strict_types=1);

namespace DriveAura\Remote\Tests;

use DriveAura\Remote\ApiException;
use DriveAura\Remote\EntitySchema;
use DriveAura\Remote\EntitySource;

/** Explicit test-only multi-entity source; production always uses PDO. */
final class FixtureEntitySource implements EntitySource
{
    private ?\Closure $afterPageHook = null;

    /** @param array<string, array<mixed>> $rowsByEntity */
    public function __construct(public array $rowsByEntity)
    {
    }

    /** @param callable(self, EntitySchema): void $hook */
    public function afterNextPage(callable $hook): void
    {
        $this->afterPageHook = \Closure::fromCallable($hook);
    }

    public function allRows(EntitySchema $schema): array
    {
        if (!array_key_exists($schema->name, $this->rowsByEntity) || !is_array($this->rowsByEntity[$schema->name])) {
            throw new ApiException(
                500,
                'INVALID_SOURCE_DATA',
                'La sorgente remota non rispetta il contratto.'
            );
        }
        return $schema->sorted($schema->normalizeRows($this->rowsByEntity[$schema->name]));
    }

    public function rowsAfter(EntitySchema $schema, ?array $after, int $limit): array
    {
        if ($limit < 1 || $limit > 101) {
            throw new \InvalidArgumentException('Limite interno non valido.');
        }
        $rows = array_values(array_filter(
            $this->allRows($schema),
            fn (array $row): bool => $after === null
                || $schema->compareKeys($schema->keyOf($row), $after) > 0
        ));
        $page = array_slice($rows, 0, $limit);

        if ($this->afterPageHook !== null) {
            $hook = $this->afterPageHook;
            $this->afterPageHook = null;
            $hook($this, $schema);
        }
        return $page;
    }
}
