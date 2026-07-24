<?php

declare(strict_types=1);

namespace DriveAura\Remote;

final class PatologiaApi
{
    public const MAX_BATCH_SIZE = 100;
    public const ENTITY = 'patologia';

    private const DEFAULT_BATCH_SIZE = 50;

    private readonly \Closure $clock;

    /** @param callable(): string $clock */
    public function __construct(
        private readonly PatologiaSource $source,
        private readonly string $apiSecret,
        private readonly CursorCodec $cursorCodec,
        callable $clock
    ) {
        if ($apiSecret === '') {
            throw new ApiException(503, 'SERVICE_NOT_CONFIGURED', 'Il segreto API remoto non è configurato.');
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
            $exportPrefix = '/api/v1/export/';
            if (strncmp($path, $exportPrefix, strlen($exportPrefix)) === 0) {
                $entity = substr($path, strlen($exportPrefix));
                return new ApiResponse(200, $this->export($entity, $query));
            }
            throw new ApiException(404, 'NOT_FOUND', 'Risorsa non trovata.');
        } catch (ApiException $error) {
            return ApiResponse::error($error);
        } catch (\Throwable) {
            return ApiResponse::error(new ApiException(500, 'INTERNAL_ERROR', 'Errore interno del servizio remoto.'));
        }
    }

    /** @return array<string, mixed> */
    private function manifest(): array
    {
        $rows = $this->validatedRows($this->source->allRows());
        $digest = PatologiaCanonicalizer::sha256($rows);

        return [
            'apiVersion' => '1.0',
            'datasetId' => $digest,
            'generatedAt' => ($this->clock)(),
            'entityOrder' => [self::ENTITY],
            'entities' => [[
                'entity' => self::ENTITY,
                'rowCount' => count($rows),
                'digest' => $digest,
            ]],
            'maxBatchSize' => self::MAX_BATCH_SIZE,
        ];
    }

    /**
     * @param array<string, mixed> $query
     * @return array<string, mixed>
     */
    private function export(string $entity, array $query): array
    {
        if ($entity !== self::ENTITY) {
            throw new ApiException(400, 'INVALID_ENTITY', 'Entità non ammessa.');
        }
        foreach (array_keys($query) as $name) {
            if (!is_string($name) || ($name !== 'limit' && $name !== 'cursor')) {
                throw new ApiException(400, 'INVALID_REQUEST', 'La richiesta non è valida.');
            }
        }

        $rawLimit = $query['limit'] ?? (string) self::DEFAULT_BATCH_SIZE;
        if (!is_string($rawLimit) || preg_match('/\A[1-9][0-9]*\z/D', $rawLimit) !== 1) {
            throw new ApiException(400, 'INVALID_LIMIT', 'Il limite non è valido.');
        }
        $limit = (int) $rawLimit;
        if ($limit > self::MAX_BATCH_SIZE) {
            throw new ApiException(400, 'INVALID_LIMIT', 'Il limite supera il massimo consentito.');
        }

        $allRows = $this->validatedRows($this->source->allRows());
        $datasetId = PatologiaCanonicalizer::sha256($allRows);
        $cursor = null;
        $after = null;
        if (array_key_exists('cursor', $query)) {
            if (!is_string($query['cursor']) || $query['cursor'] === '') {
                throw new ApiException(400, 'INVALID_CURSOR', 'Il cursore non è valido.');
            }
            $cursor = $query['cursor'];
            $decoded = $this->cursorCodec->decode($cursor);
            if ($decoded['entity'] !== self::ENTITY) {
                throw new ApiException(400, 'INVALID_CURSOR', 'Il cursore non è valido.');
            }
            if ($decoded['datasetId'] !== $datasetId) {
                throw new ApiException(409, 'DATASET_CHANGED', 'Il dataset remoto è cambiato.');
            }
            $after = $decoded['after'];
        }

        $page = $this->validatedRows($this->source->rowsAfter($after, $limit + 1), true, $after);
        if (count($page) > $limit + 1) {
            throw new ApiException(500, 'INVALID_SOURCE_DATA', 'La sorgente remota non rispetta il contratto.');
        }

        // A second digest closes the race between the snapshot used by the
        // cursor and the page query without exposing database internals.
        $confirmedRows = $this->validatedRows($this->source->allRows());
        if (PatologiaCanonicalizer::sha256($confirmedRows) !== $datasetId) {
            throw new ApiException(409, 'DATASET_CHANGED', 'Il dataset remoto è cambiato.');
        }
        $knownRows = [];
        foreach ($confirmedRows as $knownRow) {
            $knownRows[$knownRow['cod']] = $knownRow;
        }
        foreach ($page as $row) {
            if (!isset($knownRows[$row['cod']]) || $knownRows[$row['cod']] !== $row) {
                throw new ApiException(409, 'DATASET_CHANGED', 'Il dataset remoto è cambiato.');
            }
        }

        $hasMore = count($page) > $limit;
        $rows = array_slice($page, 0, $limit);
        $nextCursor = null;
        if ($hasMore) {
            if ($rows === []) {
                throw new ApiException(500, 'INVALID_SOURCE_DATA', 'La sorgente remota non rispetta il contratto.');
            }
            $nextCursor = $this->cursorCodec->encode(
                self::ENTITY,
                $datasetId,
                $rows[count($rows) - 1]['cod']
            );
        }

        return [
            'apiVersion' => '1.0',
            'datasetId' => $datasetId,
            'entity' => self::ENTITY,
            'cursor' => $cursor,
            'nextCursor' => $nextCursor,
            'hasMore' => $hasMore,
            'rowCount' => count($rows),
            'rows' => $rows,
            'digest' => PatologiaCanonicalizer::sha256($rows),
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

    /**
     * @param array<mixed> $rows
     * @return list<array{cod: string, nome: string, criticita: int}>
     */
    private function validatedRows(array $rows, bool $requireSorted = false, ?string $after = null): array
    {
        if (!array_is_list($rows)) {
            throw new ApiException(500, 'INVALID_SOURCE_DATA', 'La sorgente remota non rispetta il contratto.');
        }

        $result = [];
        $seen = [];
        $previous = $after;
        foreach ($rows as $row) {
            if (
                !is_array($row)
                || count($row) !== 3
                || !array_key_exists('cod', $row)
                || !array_key_exists('nome', $row)
                || !array_key_exists('criticita', $row)
                || !is_string($row['cod'])
                || !is_string($row['nome'])
                || !is_int($row['criticita'])
                || $row['cod'] === ''
                || $row['nome'] === ''
                || strpos($row['cod'], "\0") !== false
                || strpos($row['nome'], "\0") !== false
                || preg_match('//u', $row['cod']) !== 1
                || preg_match('//u', $row['nome']) !== 1
                || preg_match_all('/./us', $row['cod'], $characters) > 20
                || $row['criticita'] < 1
                || $row['criticita'] > 5
                || isset($seen['#' . $row['cod']])
                || ($requireSorted && $previous !== null && strcmp($row['cod'], $previous) <= 0)
            ) {
                throw new ApiException(500, 'INVALID_SOURCE_DATA', 'La sorgente remota non rispetta il contratto.');
            }
            $seen['#' . $row['cod']] = true;
            $previous = $row['cod'];
            $result[] = [
                'cod' => $row['cod'],
                'nome' => $row['nome'],
                'criticita' => $row['criticita'],
            ];
        }

        return $result;
    }
}
