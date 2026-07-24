param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$LocalBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$BridgeBaseUrl
)

$ErrorActionPreference = 'Stop'

function Join-Endpoint {
    param([string]$BaseUrl, [string]$Path)
    return $BaseUrl.TrimEnd('/') + $Path
}

function Assert-Health {
    param([string]$BaseUrl, [string]$ExpectedService)
    $response = Invoke-RestMethod -Method Get -Uri (Join-Endpoint $BaseUrl '/health') -TimeoutSec 10
    if ($response.apiVersion -ne '1.0' -or $response.service -ne $ExpectedService -or $response.status -ne 'ok') {
        throw "Contratto /health non valido per $ExpectedService."
    }
    Write-Output "PASS: /health $ExpectedService"
}

$bridgeSecret = $env:BRIDGE_API_SECRET
if ([string]::IsNullOrWhiteSpace($bridgeSecret)) {
    throw 'Impostare BRIDGE_API_SECRET nell’ambiente senza inserirlo nella riga di comando.'
}

Assert-Health $RemoteBaseUrl 'remote-php'
Assert-Health $LocalBaseUrl 'local-django'
Assert-Health $BridgeBaseUrl 'bridge-servlet'

$headers = @{ Authorization = "Bearer $bridgeSecret" }
$result = Invoke-RestMethod `
    -Method Post `
    -Uri (Join-Endpoint $BridgeBaseUrl '/api/v1/migrations') `
    -Headers $headers `
    -ContentType 'application/json; charset=utf-8' `
    -Body '{}' `
    -TimeoutSec 120

if ($result.apiVersion -ne '1.0' -or
    $result.entity -ne 'patologia' -or
    $result.status -ne 'completed' -or
    -not $result.verification.rowCountMatches -or
    -not $result.verification.digestMatches -or
    -not $result.verification.constraintsValid) {
    throw 'La migrazione verticale non ha restituito una finalizzazione verificata.'
}

Write-Output ("PASS: migrazione Patologia completata; migrationId={0}; righe={1}; digest={2}" -f `
    $result.migrationId, $result.rowCount, $result.digest)
