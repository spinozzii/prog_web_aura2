<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Authenticated keyset cursor whose contents are private API details. */
final class CursorCodec
{
    private const SIGNATURE_CONTEXT = "drive-aura-cursor-v1\n";
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

    public function encode(string $entity, string $datasetId, string $afterCod): string
    {
        if (
            preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $entity) !== 1
            || preg_match('/\A[0-9a-f]{64}\z/D', $datasetId) !== 1
            || $afterCod === ''
            || strlen($afterCod) > 80
        ) {
            throw new \InvalidArgumentException('Dati interni del cursore non validi.');
        }

        $payload = json_encode([
            'v' => 1,
            'entity' => $entity,
            'datasetId' => $datasetId,
            'after' => $afterCod,
            'exp' => ($this->clock)() + $this->ttlSeconds,
        ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
        $encoded = self::base64UrlEncode($payload);
        $signature = hash_hmac('sha256', self::SIGNATURE_CONTEXT . $encoded, $this->secret, true);

        return $encoded . '.' . self::base64UrlEncode($signature);
    }

    /** @return array{entity: string, datasetId: string, after: string} */
    public function decode(string $cursor): array
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
            || count($payload) !== 5
            || !array_key_exists('v', $payload)
            || !array_key_exists('entity', $payload)
            || !array_key_exists('datasetId', $payload)
            || !array_key_exists('after', $payload)
            || !array_key_exists('exp', $payload)
            || $payload['v'] !== 1
            || !is_string($payload['entity'])
            || preg_match('/\A[a-z][a-z0-9_]{0,63}\z/D', $payload['entity']) !== 1
            || !is_string($payload['datasetId'])
            || preg_match('/\A[0-9a-f]{64}\z/D', $payload['datasetId']) !== 1
            || !is_string($payload['after'])
            || $payload['after'] === ''
            || strlen($payload['after']) > 80
            || !is_int($payload['exp'])
            || $payload['exp'] <= ($this->clock)()
        ) {
            throw self::invalidCursor();
        }

        return [
            'entity' => $payload['entity'],
            'datasetId' => $payload['datasetId'],
            'after' => $payload['after'],
        ];
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
