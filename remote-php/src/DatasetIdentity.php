<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Builds a deterministic identity from ordered per-entity counts and digests. */
final class DatasetIdentity
{
    /**
     * @return array{
     *   datasetId: string,
     *   canonical: string,
     *   entities: list<array{entity: string, rowCount: int, digest: string}>,
     *   rowsByEntity: array<string, list<array<string, mixed>>>
     * }
     */
    public static function capture(SchemaRegistry $registry, EntitySource $source): array
    {
        $rowsByEntity = [];
        foreach ($registry->all() as $schema) {
            $rowsByEntity[$schema->name] = $schema->normalizeRows(
                $source->allRows($schema),
                true
            );
        }
        return self::fromRows($registry, $rowsByEntity);
    }

    /**
     * @param array<string, array<mixed>> $rowsByEntity
     * @return array{
     *   datasetId: string,
     *   canonical: string,
     *   entities: list<array{entity: string, rowCount: int, digest: string}>,
     *   rowsByEntity: array<string, list<array<string, mixed>>>
     * }
     */
    public static function fromRows(SchemaRegistry $registry, array $rowsByEntity): array
    {
        $normalizedByEntity = [];
        $entities = [];
        $lines = [];
        foreach ($registry->all() as $schema) {
            if (!array_key_exists($schema->name, $rowsByEntity) || !is_array($rowsByEntity[$schema->name])) {
                throw new ApiException(
                    500,
                    'INVALID_SOURCE_DATA',
                    'La sorgente remota non rispetta il contratto.'
                );
            }
            $rows = $schema->normalizeRows($rowsByEntity[$schema->name]);
            $rows = $schema->sorted($rows);
            $digest = EntityCanonicalizer::sha256($schema, $rows);
            $descriptor = [
                'entity' => $schema->name,
                'rowCount' => count($rows),
                'digest' => $digest,
            ];
            $lines[] = json_encode(
                $descriptor,
                JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
                    | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR
            );
            $entities[] = $descriptor;
            $normalizedByEntity[$schema->name] = $rows;
        }
        if (count($rowsByEntity) !== count($normalizedByEntity)) {
            throw new ApiException(
                500,
                'INVALID_SOURCE_DATA',
                'La sorgente remota non rispetta il contratto.'
            );
        }
        $canonical = implode("\n", $lines) . ($lines === [] ? '' : "\n");
        return [
            'datasetId' => hash('sha256', $canonical),
            'canonical' => $canonical,
            'entities' => $entities,
            'rowsByEntity' => $normalizedByEntity,
        ];
    }
}
