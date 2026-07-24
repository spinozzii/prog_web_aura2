<?php

declare(strict_types=1);

// DirectoryIndex makes /health work on Apache/Altervista and PHP's built-in
// server without relying on a development-only routing option.
require dirname(__DIR__) . '/index.php';
