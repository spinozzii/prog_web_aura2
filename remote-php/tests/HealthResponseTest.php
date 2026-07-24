<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/HealthResponse.php';

use DriveAura\Remote\HealthResponse;

$expected = ['apiVersion' => '1.0', 'service' => 'remote-php', 'status' => 'ok'];
if (HealthResponse::body() !== $expected) {
    fwrite(STDERR, "Contratto salute PHP non valido.\n");
    exit(1);
}

echo "Contratto salute PHP valido.\n";
