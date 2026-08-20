<?php

declare(strict_types=1);

$path = dirname(__DIR__) . '/public/.htaccess';
$contents = file_get_contents($path);

if ($contents === false) {
    throw new RuntimeException('Impossibile leggere la configurazione Apache.');
}

$required = [
    '/^DirectorySlash Off$/m',
    '/^RewriteOptions AllowNoSlash$/m',
    '/^RewriteRule \^health\/\?\$ index\.php \[L,QSA\]$/m',
];
foreach ($required as $pattern) {
    if (preg_match($pattern, $contents) !== 1) {
        throw new RuntimeException('Routing Apache salute non limitato correttamente.');
    }
}

if (str_contains($contents, 'health/index.php')) {
    throw new RuntimeException('Il routing Apache dipende ancora dalla directory fisica health.');
}

fwrite(STDOUT, "PASS: routing Apache salute senza redirect\n");
