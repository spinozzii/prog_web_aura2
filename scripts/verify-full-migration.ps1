param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$LocalBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$BridgeBaseUrl,

    [guid]$MigrationId = [guid]::NewGuid(),

    [switch]$Repeat
)

$ErrorActionPreference = 'Stop'
$entityOrder = @(
    'cittadino',
    'patologia',
    'patologia_cronica',
    'patologia_mortale',
    'ospedale',
    'ricovero',
    'patologia_ricovero',
    'progressivo_ricovero'
)

function Join-Endpoint {
    param([string]$BaseUrl, [string]$Path)
    return $BaseUrl.TrimEnd('/') + $Path
}

function Assert-Health {
    param([string]$BaseUrl, [string]$ExpectedService)
    $response = Invoke-RestMethod -Method Get -Uri (Join-Endpoint $BaseUrl '/health') -TimeoutSec 10
    if ($response.apiVersion -ne '1.0' -or
        $response.service -ne $ExpectedService -or
        $response.status -ne 'ok') {
        throw "Contratto /health non valido per $ExpectedService."
    }
    Write-Output "PASS: /health $ExpectedService"
}

function Assert-Result {
    param([object]$Result)

    if ($Result.apiVersion -ne '1.0' -or
        $Result.migrationId -ne $MigrationId.ToString() -or
        $Result.status -ne 'completed') {
        throw 'La migrazione completa non ha restituito lo stato atteso.'
    }
    if ($Result.datasetId -notmatch '^[0-9a-f]{64}$') {
        throw 'Il datasetId finale non è un digest SHA-256 valido.'
    }
    if (@($Result.entityOrder).Count -ne $entityOrder.Count -or
        (@($Result.entityOrder) -join ',') -ne ($entityOrder -join ',')) {
        throw 'L’ordine finale delle entità non coincide con il contratto.'
    }
    if (@($Result.entities).Count -ne $entityOrder.Count) {
        throw 'Il risultato non contiene tutte le entità.'
    }

    $totalRows = 0
    $totalBatches = 0
    for ($index = 0; $index -lt $entityOrder.Count; $index++) {
        $entity = @($Result.entities)[$index]
        if ($entity.entity -ne $entityOrder[$index] -or
            $entity.rowCount -lt 0 -or
            $entity.batchCount -lt 0 -or
            $entity.digest -notmatch '^[0-9a-f]{64}$') {
            throw "Risultato non valido per $($entityOrder[$index])."
        }
        $totalRows += [int]$entity.rowCount
        $totalBatches += [int]$entity.batchCount
    }

    if ($Result.totalRowCount -ne $totalRows -or
        $Result.totalBatchCount -ne $totalBatches -or
        -not $Result.verification.rowCountMatches -or
        -not $Result.verification.digestMatches -or
        -not $Result.verification.constraintsValid) {
        throw 'La verifica aggregata non coincide con i risultati per entità.'
    }
}

function Invoke-Migration {
    $bridgeSecret = $env:BRIDGE_API_SECRET
    if ([string]::IsNullOrWhiteSpace($bridgeSecret)) {
        throw 'Impostare BRIDGE_API_SECRET nell’ambiente senza inserirlo nella riga di comando.'
    }
    $headers = @{ Authorization = "Bearer $bridgeSecret" }
    $body = @{
        apiVersion = '1.0'
        migrationId = $MigrationId.ToString()
    } | ConvertTo-Json -Compress

    return Invoke-RestMethod `
        -Method Post `
        -Uri (Join-Endpoint $BridgeBaseUrl '/api/v1/migrations') `
        -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body `
        -TimeoutSec 120
}

Assert-Health $RemoteBaseUrl 'remote-php'
Assert-Health $LocalBaseUrl 'local-django'
Assert-Health $BridgeBaseUrl 'bridge-servlet'

$firstResult = Invoke-Migration
Assert-Result $firstResult
Write-Output ("PASS: migrazione completa; migrationId={0}; dataset={1}; righe={2}; lotti={3}" -f `
    $firstResult.migrationId,
    $firstResult.datasetId,
    $firstResult.totalRowCount,
    $firstResult.totalBatchCount)

if ($Repeat) {
    $secondResult = Invoke-Migration
    Assert-Result $secondResult
    if ($secondResult.datasetId -ne $firstResult.datasetId -or
        $secondResult.totalRowCount -ne $firstResult.totalRowCount -or
        $secondResult.totalBatchCount -ne $firstResult.totalBatchCount -or
        ((@($secondResult.entities) | ConvertTo-Json -Compress) -ne
            (@($firstResult.entities) | ConvertTo-Json -Compress))) {
        throw 'Il rilancio idempotente non coincide con la prima esecuzione.'
    }
    Write-Output 'PASS: rilancio idempotente completo.'
}
