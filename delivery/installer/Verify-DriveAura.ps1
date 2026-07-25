[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StatePath,
    [guid]$MigrationId = '00000000-0000-4000-8000-000000000009'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'DriveAura.Common.psm1') -Force

$timer = [Diagnostics.Stopwatch]::StartNew()
$state = Get-DriveAuraState -Path $StatePath
Assert-DriveAuraSecrets
& (Join-Path $PSScriptRoot 'Test-PackageIntegrity.ps1') -PackageRoot ([string]$state.packageRoot)
$wheelhouse = Test-DriveAuraWheelhouse -Wheelhouse (Join-Path ([string]$state.packageRoot) 'wheelhouse')
$postgres = Get-DriveAuraPostgresRuntime -PostgresBin ([string]$state.postgresBin)
Test-DriveAuraPostgresReady -PostgresRuntime $postgres `
    -HostName ([string]$state.postgresHost) `
    -Port ([int]$state.postgresPort) `
    -User ([string]$state.postgresUser) `
    -Database ([string]$state.postgresDatabase)

function Invoke-InstalledAudit {
    param([switch]$AllowFailure)
    $environment = @{
        POSTGRES_DB = [string]$state.postgresDatabase
        POSTGRES_USER = [string]$state.postgresUser
        POSTGRES_PASSWORD = $env:POSTGRES_PASSWORD
        POSTGRES_HOST = [string]$state.postgresHost
        POSTGRES_PORT = [string]$state.postgresPort
        LOCAL_API_SECRET = $env:LOCAL_API_SECRET
        DJANGO_SECRET_KEY = $env:DJANGO_SECRET_KEY
    }
    $previous = Set-DriveAuraProcessEnvironment -Values $environment
    try {
        Push-Location ([string]$state.djangoRoot)
        try {
            return Invoke-DriveAuraExternal -FilePath ([string]$state.venvPython) `
                -Arguments @(
                    'manage.py',
                    'audit_migration',
                    '--migration-id',
                    $MigrationId.ToString()
                ) -AllowFailure:$AllowFailure
        } finally {
            Pop-Location
        }
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $previous
    }
}

$existingRows = Get-DriveAuraDomainRowCount -PostgresRuntime $postgres `
    -HostName ([string]$state.postgresHost) `
    -Port ([int]$state.postgresPort) `
    -User ([string]$state.postgresUser) `
    -Database ([string]$state.postgresDatabase)
if ($existingRows -ne 0) {
    if ($existingRows -ne 22) {
        throw ("Il database dedicato contiene {0} righe. Usare un database vuoto; la verifica non cancella dati." -f
            $existingRows)
    }
    $existingAudit = Invoke-InstalledAudit -AllowFailure
    if ($existingAudit.ExitCode -ne 0) {
        throw 'Il database non e vuoto e non contiene la fixture sintetica gia verificata. Usare un database dedicato.'
    }
    try {
        $existingBody = $existingAudit.Output | ConvertFrom-Json
    } catch {
        throw 'Audit del database esistente non interpretabile.'
    }
    if ($existingBody.datasetId -ne '1994520ec6762723e7c1b32a9d8b40d8f4028f2c137a0aaa950298da680418a7' -or
        $existingBody.status -ne 'completed' -or $existingBody.totalRowCount -ne 22) {
        throw 'Il database esistente non coincide con la fixture sintetica autorizzata.'
    }
}

Assert-DriveAuraPortAvailable -Port ([int]$state.syntheticRemotePort) `
    -Label 'Porta sorgente sintetica'
$mockScript = Join-Path ([string]$state.packageRoot) 'installer\mock_remote.py'
$fixture = Join-Path ([string]$state.packageRoot) 'source\tests\fixtures\t03-dataset.json'
$schema = Join-Path ([string]$state.packageRoot) 'source\shared\entity-schema.json'
$logRoot = Join-Path ([string]$state.installRoot) 'logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$oldCursorSecret = $env:REMOTE_CURSOR_SECRET
$env:REMOTE_CURSOR_SECRET = $env:REMOTE_API_SECRET
try {
    $mockProcess = Start-Process `
        -FilePath ([string]$state.venvPython) `
        -ArgumentList @(
            ('"{0}"' -f $mockScript),
            '--port', [string]$state.syntheticRemotePort,
            '--fixture', ('"{0}"' -f $fixture),
            '--schema', ('"{0}"' -f $schema)
        ) `
        -WorkingDirectory ([string]$state.packageRoot) `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $logRoot 'synthetic-remote.out.log') `
        -RedirectStandardError (Join-Path $logRoot 'synthetic-remote.err.log') `
        -PassThru
} finally {
    $env:REMOTE_CURSOR_SECRET = $oldCursorSecret
}

$servicesStarted = $false
try {
    $remoteUrl = ("http://127.0.0.1:{0}" -f $state.syntheticRemotePort)
    Wait-DriveAuraHealth -BaseUrl $remoteUrl -ExpectedService 'remote-php' -TimeoutSeconds 15
    & (Join-Path $PSScriptRoot 'Start-DriveAura.ps1') `
        -StatePath $StatePath `
        -RemoteApiUrl $remoteUrl `
        -BatchSize 1 `
        -MaxRetries 2
    $servicesStarted = $true

    $localUrl = ("http://127.0.0.1:{0}" -f $state.djangoPort)
    $bridgeUrl = ("http://127.0.0.1:{0}" -f $state.tomcatPort)
    Wait-DriveAuraHealth -BaseUrl $localUrl -ExpectedService 'local-django' -TimeoutSeconds 5
    Wait-DriveAuraHealth -BaseUrl $bridgeUrl -ExpectedService 'bridge-servlet' -TimeoutSeconds 5
    Test-DriveAuraPostgresReady -PostgresRuntime $postgres `
        -HostName ([string]$state.postgresHost) `
        -Port ([int]$state.postgresPort) `
        -User ([string]$state.postgresUser) `
        -Database ([string]$state.postgresDatabase)

    $headers = @{ Authorization = "Bearer $($env:BRIDGE_API_SECRET)" }
    $body = @{
        apiVersion = '1.0'
        migrationId = $MigrationId.ToString()
    } | ConvertTo-Json -Compress

    function Invoke-SyntheticMigration {
        return Invoke-RestMethod `
            -Method Post `
            -Uri ($bridgeUrl + '/api/v1/migrations') `
            -Headers $headers `
            -ContentType 'application/json; charset=utf-8' `
            -Body $body `
            -TimeoutSec 120
    }

    $expectedDataset = '1994520ec6762723e7c1b32a9d8b40d8f4028f2c137a0aaa950298da680418a7'
    $result = Invoke-SyntheticMigration
    if ($result.apiVersion -ne '1.0' -or
        $result.migrationId -ne $MigrationId.ToString() -or
        $result.status -ne 'completed' -or
        $result.datasetId -ne $expectedDataset -or
        $result.totalRowCount -ne 22 -or
        $result.totalBatchCount -ne 22 -or
        @($result.entities).Count -ne 8 -or
        -not $result.verification.rowCountMatches -or
        -not $result.verification.digestMatches -or
        -not $result.verification.constraintsValid) {
        throw 'Risultato della migrazione sintetica non conforme.'
    }

    $repeat = Invoke-SyntheticMigration
    if ($repeat.status -ne 'completed' -or
        $repeat.datasetId -ne $result.datasetId -or
        $repeat.totalRowCount -ne $result.totalRowCount -or
        $repeat.totalBatchCount -ne $result.totalBatchCount) {
        throw 'Rilancio sintetico non idempotente.'
    }

    $audit = Invoke-InstalledAudit
    $auditBody = $audit.Output | ConvertFrom-Json
    if ($auditBody.status -ne 'completed' -or
        $auditBody.datasetId -ne $expectedDataset -or
        $auditBody.totalRowCount -ne 22 -or
        -not $auditBody.verification.rowCountMatches -or
        -not $auditBody.verification.digestMatches -or
        -not $auditBody.verification.constraintsValid) {
        throw 'Audit PostgreSQL della migrazione sintetica non conforme.'
    }
    Write-Host ("PASS: verifica sintetica; righe=22; lotti=22; dataset={0}." -f
        $expectedDataset)
    Write-Host 'NOTA: questa prova usa una sorgente contrattuale loopback; la migrazione massiva PHP/PDO resta una verifica separata.'
} finally {
    $cleanupErrors = New-Object System.Collections.Generic.List[string]
    if ($servicesStarted -or
        (Test-Path -LiteralPath (Join-Path ([string]$state.installRoot) 'processes.json'))) {
        try {
            & (Join-Path $PSScriptRoot 'Stop-DriveAura.ps1') -StatePath $StatePath
        } catch {
            $cleanupErrors.Add(("servizi locali: {0}" -f $_.Exception.Message))
        }
    }
    $runningMock = Get-Process -Id $mockProcess.Id -ErrorAction SilentlyContinue
    if ($null -ne $runningMock) {
        $commandLine = Get-DriveAuraProcessCommandLine -ProcessId $mockProcess.Id
        if (-not [string]::IsNullOrWhiteSpace($commandLine) -and
            $commandLine.IndexOf($mockScript, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Stop-Process -Id $mockProcess.Id -Force
        } else {
            $cleanupErrors.Add(
                "mock PID $($mockProcess.Id): command line non riconducibile a Drive Aura"
            )
        }
    }
    Start-Sleep -Milliseconds 500
    try {
        Assert-DriveAuraPortAvailable -Port ([int]$state.syntheticRemotePort) `
            -Label 'Porta sorgente sintetica'
    } catch {
        $cleanupErrors.Add(("sorgente sintetica: {0}" -f $_.Exception.Message))
    }
    if ($cleanupErrors.Count -gt 0) {
        throw ("Pulizia della verifica non riuscita: {0}" -f ($cleanupErrors -join ' | '))
    }
}

$timer.Stop()
Write-Host ("PASS: salute, readiness, migrazione e audit completati in {0:N3} secondi." -f
    $timer.Elapsed.TotalSeconds)
