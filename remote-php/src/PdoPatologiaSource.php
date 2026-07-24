<?php

declare(strict_types=1);

namespace DriveAura\Remote;

use PDO;

/** Read-only MySQL/MariaDB adapter. Table and fields are a fixed whitelist. */
final class PdoPatologiaSource implements PatologiaSource
{
    private const SELECT_FIELDS = 'cod, nome, criticita';
    private const ORDER_BY_KEY = 'CAST(cod AS BINARY) ASC';
    private const MAX_PAGE_FETCH = 101;

    private ?PDO $pdo;

    /** @var array{dsn: mixed, user: mixed, password: mixed}|null */
    private ?array $connectionConfig;

    /** @param array{dsn: mixed, user: mixed, password: mixed}|null $connectionConfig */
    public function __construct(?PDO $pdo = null, ?array $connectionConfig = null)
    {
        if (($pdo === null) === ($connectionConfig === null)) {
            throw new \InvalidArgumentException('Configurare PDO oppure i parametri di connessione.');
        }
        $this->pdo = $pdo;
        $this->connectionConfig = $connectionConfig;
    }

    public static function fromEnvironment(): self
    {
        return new self(null, [
            'dsn' => getenv('REMOTE_DB_DSN'),
            'user' => getenv('REMOTE_DB_USER'),
            'password' => getenv('REMOTE_DB_PASSWORD'),
        ]);
    }

    public function allRows(): array
    {
        return $this->execute(
            'SELECT ' . self::SELECT_FIELDS
            . ' FROM patologia ORDER BY ' . self::ORDER_BY_KEY
        );
    }

    public function rowsAfter(?string $afterCod, int $limit): array
    {
        if ($limit < 1 || $limit > self::MAX_PAGE_FETCH) {
            throw new \InvalidArgumentException('Limite interno non valido.');
        }

        if ($afterCod === null) {
            return $this->execute(
                'SELECT ' . self::SELECT_FIELDS
                . ' FROM patologia ORDER BY ' . self::ORDER_BY_KEY
                . ' LIMIT :limit',
                null,
                $limit
            );
        }
        if ($afterCod === '') {
            throw new \InvalidArgumentException('Chiave del cursore non valida.');
        }

        return $this->execute(
            'SELECT ' . self::SELECT_FIELDS
            . ' FROM patologia'
            . ' WHERE CAST(cod AS BINARY) > CAST(:after AS BINARY)'
            . ' ORDER BY ' . self::ORDER_BY_KEY
            . ' LIMIT :limit',
            $afterCod,
            $limit
        );
    }

    /**
     * @return list<array{cod: string, nome: string, criticita: int}>
     */
    private function execute(string $sql, ?string $afterCod = null, ?int $limit = null): array
    {
        try {
            $statement = $this->connection()->prepare($sql);
            if ($afterCod !== null) {
                $statement->bindValue(':after', $afterCod, PDO::PARAM_STR);
            }
            if ($limit !== null) {
                $statement->bindValue(':limit', $limit, PDO::PARAM_INT);
            }
            $statement->execute();
            $rows = $statement->fetchAll();
        } catch (ApiException $error) {
            throw $error;
        } catch (\Throwable) {
            throw new ApiException(503, 'SOURCE_UNAVAILABLE', 'La sorgente dati remota non è disponibile.');
        }

        return $this->normalize($rows);
    }

    private function connection(): PDO
    {
        if ($this->pdo !== null) {
            return $this->pdo;
        }

        $config = $this->connectionConfig;
        $dsn = $config['dsn'] ?? null;
        if (!is_string($dsn) || $dsn === '' || strncmp($dsn, 'mysql:', 6) !== 0) {
            throw new ApiException(503, 'SERVICE_NOT_CONFIGURED', 'Il database remoto non è configurato.');
        }
        if (stripos($dsn, 'charset=') === false) {
            $dsn .= substr($dsn, -1) === ';' ? 'charset=utf8mb4' : ';charset=utf8mb4';
        }

        try {
            $this->pdo = new PDO(
                $dsn,
                is_string($config['user'] ?? null) ? $config['user'] : '',
                is_string($config['password'] ?? null) ? $config['password'] : '',
                [
                    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                    PDO::ATTR_EMULATE_PREPARES => false,
                    PDO::ATTR_STRINGIFY_FETCHES => false,
                ]
            );
        } catch (\Throwable) {
            throw new ApiException(503, 'SOURCE_UNAVAILABLE', 'La sorgente dati remota non è disponibile.');
        }
        $this->connectionConfig = null;

        return $this->pdo;
    }

    /**
     * @param array<mixed> $rows
     * @return list<array{cod: string, nome: string, criticita: int}>
     */
    private function normalize(array $rows): array
    {
        if (!array_is_list($rows)) {
            throw new ApiException(500, 'INVALID_SOURCE_DATA', 'La sorgente remota non rispetta il contratto.');
        }

        $result = [];
        foreach ($rows as $row) {
            if (
                !is_array($row)
                || !array_key_exists('cod', $row)
                || !array_key_exists('nome', $row)
                || !array_key_exists('criticita', $row)
                || !is_string($row['cod'])
                || !is_string($row['nome'])
            ) {
                throw new ApiException(500, 'INVALID_SOURCE_DATA', 'La sorgente remota non rispetta il contratto.');
            }
            $criticita = $row['criticita'];
            if (is_string($criticita) && preg_match('/\A[1-5]\z/D', $criticita) === 1) {
                $criticita = (int) $criticita;
            }
            if (!is_int($criticita)) {
                throw new ApiException(500, 'INVALID_SOURCE_DATA', 'La sorgente remota non rispetta il contratto.');
            }
            $result[] = [
                'cod' => $row['cod'],
                'nome' => $row['nome'],
                'criticita' => $criticita,
            ];
        }

        return $result;
    }
}
