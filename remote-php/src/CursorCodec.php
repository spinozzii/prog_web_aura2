<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Authenticated keyset cursor whose contents are private API details. */
final class CursorCodec
{
    private const SIGNATURE_CONTEXT = "drive-aura-cursor-v2\n";
    private const MAX_CURSOR_LENGTH = 1024;

    private readonly \Closure $clock;

    /** @param null|callable(): int $clock */
    public function __construct(
        private readonly string $secret,
        ?callable $clock = null,
        private readonly int $ttlSeconds = 900
    ) {
        if ($secret === '') {
            throw new ApiException(503, 'SERVICE_NOT_CONFIGURED', 'Il segreto del cursore non è configurato.');
        }
        if ($ttlSeconds < 1 || $ttlSeconds > 86400) {
            throw new ApiException(503, 'SERVICE_NOT_CONFIGURED', 'La durata dei cursori non è configurata correttamente.');
        }
        $this->clock = $clock === null
            ? static fn (): int => time()
            : \Closure::fromCallable($clock);
    }

    /** @param list<string|int> $after */
    public function encode(string $entity, string $datasetId, array $after): string
    {
        if (
            preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $entity) !== 1
            || preg_match('/\A[0-9a-f]{64}\z/D', $datasetId) !== 1
            || !self::validTuple($after)
        ) {
            throw new \InvalidArgumentException('Dati interni del cursore non validi.');
        }

        $payload = json_encode(
            [2, $entity, $datasetId, $after, ($this->clock)() + $this->ttlSeconds],
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
                | JSON_UNESCAPED_LINE_TERMINATORS | JSON_THROW_ON_ERROR
        );
        $encoded = self::base64UrlEncode($payload);
        $signature = hash_hmac('sha256', self::SIGNATURE_CONTEXT . $encoded, $this->secret, true);

        $cursor = $encoded . '.' . self::base64UrlEncode($signature);
        if (strlen($cursor) > self::MAX_CURSOR_LENGTH) {
            throw new \InvalidArgumentException('Dati interni del cursore non validi.');
        }
        return $cursor;
    }

    /** @return array{entity: string, datasetId: string, after: list<string|int>} */
    public function decode(string $cursor): array
    {
        return $this->decodePayload($cursor, false);
    }

    /**
     * Decode an already authenticated, persisted checkpoint. Its HMAC and
     * dataset binding remain mandatory, while expiry does not prevent resume.
     *
     * @return array{entity: string, datasetId: string, after: list<string|int>}
     */
    public function decodeForResume(string $cursor): array
    {
        return $this->decodePayload($cursor, true);
    }

    /** @return array{entity: string, datasetId: string, after: list<string|int>} */
    private function decodePayload(string $cursor, bool $allowExpired): array
    {
        if (
            $cursor === ''
            || strlen($cursor) > self::MAX_CURSOR_LENGTH
            || preg_match('/\A[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z/D', $cursor) !== 1
        ) {
            throw self::invalidCursor();
        }

        [$encoded, $encodedSignature] = explode('.', $cursor, 2);
        $signature = self::base64UrlDecode($encodedSignature);
        $expected = hash_hmac('sha256', self::SIGNATURE_CONTEXT . $encoded, $this->secret, true);
        if (strlen($signature) !== 32 || !hash_equals($expected, $signature)) {
            throw self::invalidCursor();
        }

        try {
            $payload = json_decode(self::base64UrlDecode($encoded), true, 16, JSON_THROW_ON_ERROR);
        } catch (\Throwable) {
            throw self::invalidCursor();
        }
        if (
            !is_array($payload)
            || !array_is_list($payload)
            || count($payload) !== 5
            || $payload[0] !== 2
            || !is_string($payload[1])
            || preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $payload[1]) !== 1
            || !is_string($payload[2])
            || preg_match('/\A[0-9a-f]{64}\z/D', $payload[2]) !== 1
            || !is_array($payload[3])
            || !self::validTuple($payload[3])
            || !is_int($payload[4])
            || $payload[4] < 1
            || (!$allowExpired && $payload[4] <= ($this->clock)())
        ) {
            throw self::invalidCursor();
        }

        return [
            'entity' => $payload[1],
            'datasetId' => $payload[2],
            'after' => $payload[3],
        ];
    }

    /** @param array<mixed> $tuple */
    private static function validTuple(array $tuple): bool
    {
        if (!array_is_list($tuple) || $tuple === [] || count($tuple) > 8) {
            return false;
        }
        foreach ($tuple as $value) {
            if (is_int($value)) {
                if ($value < 0) {
                    return false;
                }
                continue;
            }
            if (
                !is_string($value)
                || $value === ''
                || strlen($value) > 1024
                || strpos($value, "\0") !== false
                || preg_match('//u', $value) !== 1
            ) {
                return false;
            }
        }
        return true;
    }

    private static function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }

    private static function base64UrlDecode(string $value): string
    {
        if (
            $value === ''
            || preg_match('/\A[A-Za-z0-9_-]+\z/D', $value) !== 1
            || strlen($value) % 4 === 1
        ) {
            throw self::invalidCursor();
        }

        $padding = (4 - strlen($value) % 4) % 4;
        $decoded = base64_decode(strtr($value, '-_', '+/') . str_repeat('=', $padding), true);
        if ($decoded === false || self::base64UrlEncode($decoded) !== $value) {
            throw self::invalidCursor();
        }

        return $decoded;
    }

    private static function invalidCursor(): ApiException
    {
        return new ApiException(400, 'INVALID_CURSOR', 'Il cursore non è valido.');
    }
}
