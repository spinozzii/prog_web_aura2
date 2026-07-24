<?php

declare(strict_types=1);

require_once __DIR__ . '/../src/HealthResponse.php';

use DriveAura\Remote\HealthResponse;

header('Content-Type: application/json; charset=utf-8');

$path = rtrim((string) parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH), '/') ?: '/';
if ($_SERVER['REQUEST_METHOD'] === 'GET' && $path === '/health') {
    http_response_code(200);
    echo json_encode(HealthResponse::body(), JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    exit;
}

http_response_code(404);
echo json_encode([
    'apiVersion' => HealthResponse::API_VERSION,
    'error' => ['code' => 'NOT_FOUND', 'message' => 'Risorsa non trovata.'],
], JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
