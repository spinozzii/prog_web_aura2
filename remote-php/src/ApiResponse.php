<?php

declare(strict_types=1);

namespace DriveAura\Remote;

final class ApiResponse
{
    /** @param array<string, mixed> $body */
    public function __construct(public readonly int $status, public readonly array $body)
    {
    }

    public static function error(ApiException $error): self
    {
        return new self($error->httpStatus, [
            'apiVersion' => '1.0',
            'error' => ['code' => $error->errorCode, 'message' => $error->getMessage()],
        ]);
    }
}
