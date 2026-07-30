<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Manifest and paginated export API for the complete ordered dataset. */
final class MigrationApi
{
    public const MAX_BATCH_SIZE = 100;
    private const DEFAULT_BATCH_SIZE = 50;

    private readonly \Closure $clock;

    /** @param callable(): string $clock */
    public function __construct(
        private readonly EntitySource $source,
        private readonly SchemaRegistry $registry,
        private readonly string $apiSecret,
        private readonly CursorCodec $cursorCodec,
        callable $clock
    ) {
        if ($apiSecret === '') {
            throw new ApiException(
                503,
                'SERVICE_NOT_CONFIGURED',
                'Il segreto API remoto non è configurato.'
            );
        }
        $this->clock = \Closure::fromCallable($clock);
    }

    /**
     * @param array<string, mixed> $query
     * @param array<string, mixed> $headers
     */
    public function handle(string $method, string $path, array $query, array $headers): ApiResponse
    {
        try {
            $this->authorize($headers);
            if ($method !== 'GET') {
                throw new ApiException(405, 'METHOD_NOT_ALLOWED', 'Metodo non consentito.');
            }
            if ($path === '/api/v1/manifest') {
                if ($query !== []) {
                    throw new ApiException(400, 'INVALID_REQUEST', 'La richiesta non è valida.');
                }
                return new ApiResponse(200, $this->manifest());
            }
            $prefix = '/api/v1/export/';
            if (strncmp($path, $prefix, strlen($prefix)) === 0) {
                return new ApiResponse(200, $this->export(substr($path, strlen($prefix)), $query));
            }
            throw new ApiException(404, 'NOT_FOUND', 'Risorsa non trovata.');
        } catch (ApiException $error) {
            return ApiResponse::error($error);
        } catch (\Throwable) {
            return ApiResponse::error(
                new ApiException(500, 'INTERNAL_ERROR', 'Errore interno del servizio remoto.')
            );
        }
    }

    /** @return array<string, mixed> */
    private function manifest(): array
    {
        $snapshot = DatasetIdentity::capture($this->registry, $this->source);
        return [
            'apiVersion' => '1.0',
            'datasetId' => $snapshot['datasetId'],
            'generatedAt' => ($this->clock)(),
            'entityOrder' => $this->registry->order(),
            'entities' => $snapshot['entities'],
            'maxBatchSize' => self::MAX_BATCH_SIZE,
        ];
    }

    /**
     * @param array<string, mixed> $query
     * @return array<string, mixed>
     */
    private function export(string $entity, array $query): array
    {
        if (!$this->registry->has($entity)) {
            throw new ApiException(400, 'INVALID_ENTITY', 'Entità non ammessa.');
        }
        $schema = $this->registry->get($entity);
        foreach (array_keys($query) as $name) {
            if (
                !is_string($name)
                || ($name !== 'limit' && $name !== 'cursor' && $name !== 'datasetId')
            ) {
                throw new ApiException(400, 'INVALID_REQUEST', 'La richiesta non è valida.');
            }
        }

        $datasetId = $query['datasetId'] ?? null;
        if (
            !is_string($datasetId)
            || preg_match('/\A[0-9a-f]{64}\z/D', $datasetId) !== 1
        ) {
            throw new ApiException(400, 'INVALID_DATASET', 'Il dataset non è valido.');
        }
        $rawLimit = $query['limit'] ?? (string) self::DEFAULT_BATCH_SIZE;
        if (!is_string($rawLimit) || preg_match('/\A[1-9][0-9]*\z/D', $rawLimit) !== 1) {
            throw new ApiException(400, 'INVALID_LIMIT', 'Il limite non è valido.');
        }
        $limit = (int) $rawLimit;
        if ($limit > self::MAX_BATCH_SIZE) {
            throw new ApiException(400, 'INVALID_LIMIT', 'Il limite supera il massimo consentito.');
        }

        $cursor = null;
        $after = null;
        if (array_key_exists('cursor', $query)) {
            if (!is_string($query['cursor']) || $query['cursor'] === '') {
                throw self::invalidCursor();
            }
            $cursor = $query['cursor'];
            // This endpoint is already Bearer-authenticated. A persisted,
            // correctly signed checkpoint remains resumable after its nominal
            // expiry; tampering and dataset/entity changes are still rejected.
            $decoded = $this->cursorCodec->decodeForResume($cursor);
            if ($decoded['entity'] !== $entity) {
                throw self::invalidCursor();
            }
            if ($decoded['datasetId'] !== $datasetId) {
                throw new ApiException(409, 'DATASET_CHANGED', 'Il dataset remoto è cambiato.');
            }
            try {
                $after = $schema->normalizeKeyTuple($decoded['after']);
            } catch (\InvalidArgumentException) {
                throw self::invalidCursor();
            }
        } else {
            // Validate the pinned manifest at each entity boundary.  Continuation
            // pages rely on the authenticated cursor; Java re-reads the complete
            // manifest before declaring the migration successful.
            $snapshot = DatasetIdentity::capture($this->registry, $this->source);
            if ($snapshot['datasetId'] !== $datasetId) {
                throw new ApiException(409, 'DATASET_CHANGED', 'Il dataset remoto è cambiato.');
            }
        }

        $page = $schema->normalizeRows(
            $this->source->rowsAfter($schema, $after, $limit + 1),
            true,
            $after
        );
        if (count($page) > $limit + 1) {
            throw new ApiException(
                500,
                'INVALID_SOURCE_DATA',
                'La sorgente remota non rispetta il contratto.'
            );
        }

        $hasMore = count($page) > $limit;
        $rows = array_slice($page, 0, $limit);
        $nextCursor = null;
        if ($hasMore) {
            if ($rows === []) {
                throw new ApiException(
                    500,
                    'INVALID_SOURCE_DATA',
                    'La sorgente remota non rispetta il contratto.'
                );
            }
            $nextCursor = $this->cursorCodec->encode(
                $entity,
                $datasetId,
                $schema->keyOf($rows[count($rows) - 1])
            );
        }

        return [
            'apiVersion' => '1.0',
            'datasetId' => $datasetId,
            'entity' => $entity,
            'cursor' => $cursor,
            'nextCursor' => $nextCursor,
            'hasMore' => $hasMore,
            'rowCount' => count($rows),
            'rows' => $rows,
            'digest' => EntityCanonicalizer::sha256($schema, $rows),
        ];
    }

    /** @param array<string, mixed> $headers */
    private function authorize(array $headers): void
    {
        $authorization = null;
        foreach ($headers as $name => $value) {
            if (is_string($name) && strtolower($name) === 'authorization') {
                $authorization = $value;
                break;
            }
        }
        if (
            !is_string($authorization)
            || preg_match('/\ABearer[ \t]+([^\r\n]+)\z/iD', $authorization, $matches) !== 1
            || !hash_equals($this->apiSecret, $matches[1])
        ) {
            throw new ApiException(401, 'UNAUTHORIZED', 'Autenticazione richiesta.');
        }
    }

    private static function invalidCursor(): ApiException
    {
        return new ApiException(400, 'INVALID_CURSOR', 'Il cursore non è valido.');
    }
}
