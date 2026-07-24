param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$LocalBaseUrl,

    [Parameter(Mandatory = $true)]
    [string]$BridgeBaseUrl
)

# Alias mantenuto per chi usava la verticale T02.2. Da T03 il medesimo
# endpoint migra il dataset completo, che comprende anche Patologia.
& (Join-Path $PSScriptRoot 'verify-full-migration.ps1') `
    -RemoteBaseUrl $RemoteBaseUrl `
    -LocalBaseUrl $LocalBaseUrl `
    -BridgeBaseUrl $BridgeBaseUrl
