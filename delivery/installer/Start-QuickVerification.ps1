[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'DriveAura.Common.psm1') -Force
Repair-DriveAuraPathEnvironment | Out-Null

$packageRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path

function Read-DriveAuraText {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [string]$Default = ''
    )

    $prompt = if ([string]::IsNullOrWhiteSpace($Default)) {
        $Label
    } else {
        "{0} [{1}]" -f $Label, $Default
    }
    $value = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value.Trim()
}

function Read-DriveAuraSecret {
    param([Parameter(Mandatory = $true)][string]$Label)

    $secure = Read-Host $Label -AsSecureString
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
        $secure.Dispose()
    }
}

function New-DriveAuraEphemeralSecret {
    $bytes = New-Object byte[] 30
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    } finally {
        $generator.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Set-DriveAuraTemporarySecret {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][hashtable]$Previous
    )

    $Previous[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

Write-Host 'Drive Aura 51 - verifica rapida offline'
Write-Host 'Inserire percorsi completi. Premere INVIO solo quando e indicato un valore predefinito.'
Write-Host 'Questa procedura crea soltanto due database nuovi e non elimina o svuota database esistenti.'

$pythonPath = Read-DriveAuraText -Label 'Percorso completo di python.exe (INVIO per rilevamento automatico)'
$javaHome = Read-DriveAuraText -Label 'Directory JDK (INVIO per JAVA_HOME o java nel PATH)'
$tomcatHome = Read-DriveAuraText -Label 'Directory Tomcat 9 o 11'
$postgresBin = Read-DriveAuraText -Label 'Directory bin di PostgreSQL'
$postgresHost = Read-DriveAuraText -Label 'Host PostgreSQL' -Default '127.0.0.1'
$postgresPortText = Read-DriveAuraText -Label 'Porta PostgreSQL' -Default '5432'
$postgresUser = Read-DriveAuraText -Label 'Utente PostgreSQL' -Default 'postgres'
$postgresDatabase = Read-DriveAuraText -Label 'Nuovo database operativo' -Default 'drive_aura_51'
$verificationDatabase = Read-DriveAuraText -Label 'Nuovo database di verifica' -Default ($postgresDatabase + '_verify')

$postgresPort = 0
if (-not [int]::TryParse($postgresPortText, [ref]$postgresPort) -or
    $postgresPort -lt 1 -or $postgresPort -gt 65535) {
    throw 'Porta PostgreSQL non valida: usare un intero fra 1 e 65535.'
}
if ($postgresDatabase.Equals($verificationDatabase, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Il database di verifica deve avere un nome diverso dal database operativo.'
}

$previousSecrets = @{}
try {
    $postgresPassword = Read-DriveAuraSecret -Label 'Password dell''utente PostgreSQL locale'
    if ([string]::IsNullOrWhiteSpace($postgresPassword)) {
        throw 'Password PostgreSQL mancante.'
    }
    Set-DriveAuraTemporarySecret -Name 'POSTGRES_PASSWORD' -Value $postgresPassword -Previous $previousSecrets
    Set-DriveAuraTemporarySecret -Name 'DJANGO_SECRET_KEY' -Value (New-DriveAuraEphemeralSecret) -Previous $previousSecrets
    Set-DriveAuraTemporarySecret -Name 'LOCAL_API_SECRET' -Value (New-DriveAuraEphemeralSecret) -Previous $previousSecrets
    # This is deliberately a synthetic-source secret, not the Altervista bearer.
    Set-DriveAuraTemporarySecret -Name 'REMOTE_API_SECRET' -Value (New-DriveAuraEphemeralSecret) -Previous $previousSecrets
    Set-DriveAuraTemporarySecret -Name 'BRIDGE_API_SECRET' -Value (New-DriveAuraEphemeralSecret) -Previous $previousSecrets

    $postgres = Get-DriveAuraPostgresRuntime -PostgresBin $postgresBin
    Test-DriveAuraPostgresReady -PostgresRuntime $postgres -HostName $postgresHost `
        -Port $postgresPort -User $postgresUser -Database 'postgres'
    foreach ($database in @($postgresDatabase, $verificationDatabase)) {
        if (Test-DriveAuraDatabaseExists -PostgresRuntime $postgres -HostName $postgresHost `
                -Port $postgresPort -User $postgresUser -Database $database) {
            throw ("Il database '{0}' esiste gia'. Scegliere un nome nuovo: la verifica non cancella dati." -f $database)
        }
    }

    $configure = Join-Path $PSScriptRoot 'Configure-DriveAura.ps1'
    & $configure `
        -PythonPath $pythonPath `
        -JavaHome $javaHome `
        -TomcatHome $tomcatHome `
        -PostgresBin $postgresBin `
        -PostgresHost $postgresHost `
        -PostgresPort $postgresPort `
        -PostgresUser $postgresUser `
        -PostgresDatabase $postgresDatabase `
        -VerificationDatabase $verificationDatabase
} finally {
    foreach ($name in $previousSecrets.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousSecrets[$name], 'Process')
    }
}
