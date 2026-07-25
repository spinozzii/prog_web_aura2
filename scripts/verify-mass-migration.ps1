param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$LocalBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$BridgeBaseUrl,

    [guid]$MigrationId = [guid]::NewGuid(),

    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 1800,

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
$expectedCounts = [ordered]@{
    cittadino = 3200
    patologia = 200
    patologia_cronica = 143
    patologia_mortale = 81
    ospedale = 30
    ricovero = 12000
    patologia_ricovero = 20492
    progressivo_ricovero = 30
}

function Join-Endpoint {
    param([string]$BaseUrl, [string]$Path)
    return $BaseUrl.TrimEnd('/') + $Path
}

function Get-SecretHeaders {
    param([string]$EnvironmentName)
    $value = [Environment]::GetEnvironmentVariable($EnvironmentName)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Impostare $EnvironmentName nell'ambiente."
    }
    return @{ Authorization = "Bearer $value" }
}

function Assert-Health {
    param([string]$BaseUrl, [string]$ExpectedService)
    $response = Invoke-RestMethod `
        -Method Get `
        -Uri (Join-Endpoint $BaseUrl '/health') `
        -TimeoutSec 10
    if ($response.apiVersion -ne '1.0' -or
        $response.service -ne $ExpectedService -or
        $response.status -ne 'ok') {
        throw "Contratto /health non valido per $ExpectedService."
    }
}

function Get-Manifest {
    $response = Invoke-RestMethod `
        -Method Get `
        -Uri (Join-Endpoint $RemoteBaseUrl '/api/v1/manifest') `
        -Headers (Get-SecretHeaders 'REMOTE_API_SECRET') `
        -TimeoutSec $TimeoutSeconds
    if ($response.apiVersion -ne '1.0' -or
        $response.datasetId -notmatch '^[0-9a-f]{64}$' -or
        (@($response.entityOrder) -join ',') -ne ($entityOrder -join ',') -or
        @($response.entities).Count -ne $entityOrder.Count) {
        throw 'Manifest massivo non valido.'
    }
    for ($index = 0; $index -lt $entityOrder.Count; $index++) {
        $name = $entityOrder[$index]
        $descriptor = @($response.entities)[$index]
        if ($descriptor.entity -ne $name -or
            $descriptor.rowCount -ne $expectedCounts[$name] -or
            $descriptor.digest -notmatch '^[0-9a-f]{64}$') {
            throw "Descrittore massivo non valido per $name."
        }
    }
    return $response
}

function Invoke-Migration {
    $body = @{
        apiVersion = '1.0'
        migrationId = $MigrationId.ToString()
    } | ConvertTo-Json -Compress
    return Invoke-RestMethod `
        -Method Post `
        -Uri (Join-Endpoint $BridgeBaseUrl '/api/v1/migrations') `
        -Headers (Get-SecretHeaders 'BRIDGE_API_SECRET') `
        -ContentType 'application/json; charset=utf-8' `
        -Body $body `
        -TimeoutSec $TimeoutSeconds
}

function Assert-Result {
    param([object]$Result, [object]$Manifest)
    if ($Result.apiVersion -ne '1.0' -or
        $Result.migrationId -ne $MigrationId.ToString() -or
        $Result.datasetId -ne $Manifest.datasetId -or
        $Result.status -ne 'completed' -or
        (@($Result.entityOrder) -join ',') -ne ($entityOrder -join ',') -or
        @($Result.entities).Count -ne $entityOrder.Count) {
        throw 'Risultato massivo non valido.'
    }
    $rows = 0
    $batches = 0
    for ($index = 0; $index -lt $entityOrder.Count; $index++) {
        $expected = @($Manifest.entities)[$index]
        $actual = @($Result.entities)[$index]
        if ($actual.entity -ne $expected.entity -or
            $actual.rowCount -ne $expected.rowCount -or
            $actual.digest -ne $expected.digest -or
            $actual.batchCount -lt 0) {
            throw "Risultato non valido per $($expected.entity)."
        }
        $rows += [int]$actual.rowCount
        $batches += [int]$actual.batchCount
    }
    if ($rows -ne 36176 -or
        $Result.totalRowCount -ne $rows -or
        $Result.totalBatchCount -ne $batches -or
        -not $Result.verification.rowCountMatches -or
        -not $Result.verification.digestMatches -or
        -not $Result.verification.constraintsValid) {
        throw 'Totali o verifica aggregata non validi.'
    }
}

function Assert-Status {
    $status = Invoke-RestMethod `
        -Method Get `
        -Uri (Join-Endpoint $BridgeBaseUrl "/api/v1/migrations/$($MigrationId.ToString())") `
        -Headers (Get-SecretHeaders 'BRIDGE_API_SECRET') `
        -TimeoutSec 30
    if ($status.apiVersion -ne '1.0' -or
        $status.migrationId -ne $MigrationId.ToString() -or
        $status.status -ne 'completed' -or
        @($status.entities).Count -ne $entityOrder.Count) {
        throw 'Stato globale massivo non completato.'
    }
    $rowsImported = 0
    for ($index = 0; $index -lt $entityOrder.Count; $index++) {
        $name = $entityOrder[$index]
        $checkpoint = @($status.entities)[$index]
        if ($checkpoint.entity -ne $name -or
            $checkpoint.status -ne 'completed' -or
            $checkpoint.rowsImported -ne $expectedCounts[$name]) {
            throw "Checkpoint massivo non valido per $name."
        }
        $rowsImported += [int]$checkpoint.rowsImported
    }
    if ($rowsImported -ne 36176) {
        throw 'Totale dei checkpoint massivi non valido.'
    }
}

Assert-Health $RemoteBaseUrl 'remote-php'
Assert-Health $LocalBaseUrl 'local-django'
Assert-Health $BridgeBaseUrl 'bridge-servlet'
$manifest = Get-Manifest

$watch = [Diagnostics.Stopwatch]::StartNew()
$first = Invoke-Migration
$watch.Stop()
Assert-Result $first $manifest
Assert-Status
Write-Output (
    'PASS: massivo migrationId={0}; dataset={1}; righe={2}; lotti={3}; secondi={4:N3}' -f
    $first.migrationId,
    $first.datasetId,
    $first.totalRowCount,
    $first.totalBatchCount,
    $watch.Elapsed.TotalSeconds
)
foreach ($entity in @($first.entities)) {
    Write-Output (
        'ENTITY: {0}; righe={1}; lotti={2}; digest={3}' -f
        $entity.entity,
        $entity.rowCount,
        $entity.batchCount,
        $entity.digest
    )
}

if ($Repeat) {
    $repeatWatch = [Diagnostics.Stopwatch]::StartNew()
    $second = Invoke-Migration
    $repeatWatch.Stop()
    Assert-Result $second $manifest
    Assert-Status
    if ((@($second.entities) | ConvertTo-Json -Compress) -ne
        (@($first.entities) | ConvertTo-Json -Compress)) {
        throw 'Il rilancio idempotente non coincide con la prima esecuzione.'
    }
    Write-Output (
        'PASS: rilancio idempotente; secondi={0:N3}' -f
        $repeatWatch.Elapsed.TotalSeconds
    )
}
