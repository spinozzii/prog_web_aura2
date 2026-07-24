<?php

declare(strict_types=1);

namespace DriveAura\Remote;

/** Builds the public health representation shared by the PHP entry point. */
final class HealthResponse
{
    public const API_VERSION = '1.0';
    public const SERVICE = 'remote-php';

    /** @return array{apiVersion: string, service: string, status: string} */
    public static function body(): array
    {
        return [
            'apiVersion' => self::API_VERSION,
            'service' => self::SERVICE,
            'status' => 'ok',
        ];
    }
}
