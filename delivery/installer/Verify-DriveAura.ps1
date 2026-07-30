[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StatePath,
    [guid]$MigrationId = '00000000-0000-4000-8000-000000000009',
    [ValidateRange(60, 240)][int]$TimeoutSeconds = 180,
    [switch]$Worker
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'DriveAura.Common.psm1') -Force

Repair-DriveAuraPathEnvironment | Out-Null
if (-not $Worker) {
    $powershellPath = (Get-Process -Id $PID -ErrorAction Stop).Path
    $workerArguments = @(
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $PSCommandPath,
        '-StatePath', $StatePath,
        '-MigrationId', $MigrationId.ToString(),
        '-TimeoutSeconds', "$TimeoutSeconds",
        '-Worker'
    )
    try {
        $workerResult = Invoke-DriveAuraExternal -FilePath $powershellPath `
            -Arguments $workerArguments -TimeoutSeconds $TimeoutSeconds
        if (-not [string]::IsNullOrWhiteSpace($workerResult.Output)) {
            Write-Host $workerResult.Output
        }
        return
    } catch {
        $primaryMessage = $_.Exception.Message
        $recoveryErrors = New-Object System.Collections.Generic.List[string]
        try {
            $recoveryState = Get-DriveAuraState -Path $StatePath
            $processPath = Join-Path ([string]$recoveryState.installRoot) 'processes.json'
            if (Test-Path -LiteralPath $processPath -PathType Leaf) {
                & (Join-Path $PSScriptRoot 'Stop-DriveAura.ps1') -StatePath $StatePath
            }
            Assert-DriveAuraPortAvailable -Port ([int]$recoveryState.syntheticRemotePort) `
                -Label 'Porta sorgente sintetica'
            $diagnosticRoot = Join-Path ([string]$recoveryState.installRoot) 'logs'
            if (Test-Path -LiteralPath $diagnosticRoot -PathType Container) {
                foreach ($log in Get-ChildItem -LiteralPath $diagnosticRoot -File |
                        Sort-Object Name) {
                    $tail = @(Get-Content -LiteralPath $log.FullName -Tail 20)
                    if ($tail.Count -gt 0) {
                        Write-Warning ("Ultime righe {0}:{1}{2}" -f
                            $log.Name, [Environment]::NewLine,
                            ($tail -join [Environment]::NewLine))
                    }
                }
            }
        } catch {
            $recoveryErrors.Add($_.Exception.Message)
        }
        $suffix = if ($recoveryErrors.Count -gt 0) {
            " | Pulizia watchdog: $($recoveryErrors -join ' | ')"
        } else {
            ''
        }
        throw ("Verifica terminata entro il limite di {0} secondi: {1}{2}" -f
            $TimeoutSeconds, $primaryMessage, $suffix)
    }
}

$timer = [Diagnostics.Stopwatch]::StartNew()
$operationDeadline = [DateTime]::UtcNow.AddSeconds([Math]::Max(30, $TimeoutSeconds - 20))
function Get-DriveAuraVerificationRemaining {
    param(
        [ValidateRange(1, 120)][int]$Maximum,
        [Parameter(Mandatory = $true)][string]$Operation
    )
    $remaining = [Math]::Floor(($operationDeadline - [DateTime]::UtcNow).TotalSeconds)
    if ($remaining -lt 1) {
        throw "Timeout complessivo durante $Operation."
    }
    return [Math]::Max(1, [Math]::Min($Maximum, [int]$remaining))
}

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
                ) -AllowFailure:$AllowFailure `
                -TimeoutSeconds (Get-DriveAuraVerificationRemaining `
                    -Maximum 30 -Operation 'audit PostgreSQL')
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

$mockWrapper = Join-Path ([string]$state.installRoot) 'run-synthetic-remote.bat'
$mockOut = Join-Path $logRoot 'synthetic-remote.out.log'
$mockErr = Join-Path $logRoot 'synthetic-remote.err.log'
@(
    '@echo off',
    ('"{0}" "{1}" --port {2} --fixture "{3}" --schema "{4}" 1>>"{5}" 2>>"{6}" <NUL' -f
        [string]$state.venvPython, $mockScript, [int]$state.syntheticRemotePort,
        $fixture, $schema, $mockOut, $mockErr)
) | Set-Content -LiteralPath $mockWrapper -Encoding ASCII

$mockIdentity = $null
$servicesStarted = $false
$verificationError = $null
$cleanupErrors = New-Object System.Collections.Generic.List[string]
try {
    $oldCursorSecret = $env:REMOTE_CURSOR_SECRET
    $env:REMOTE_CURSOR_SECRET = $env:REMOTE_API_SECRET
    try {
        $mockIdentity = Start-DriveAuraManagedProcess `
            -WrapperPath $mockWrapper `
            -WorkingDirectory ([string]$state.packageRoot)
    } finally {
        $env:REMOTE_CURSOR_SECRET = $oldCursorSecret
    }

    $remoteUrl = ("http://127.0.0.1:{0}" -f $state.syntheticRemotePort)
    Wait-DriveAuraHealth -BaseUrl $remoteUrl -ExpectedService 'remote-php' `
        -TimeoutSeconds (Get-DriveAuraVerificationRemaining `
            -Maximum 15 -Operation 'readiness sorgente sintetica') `
        -ProcessIdentity $mockIdentity -ProcessLabel 'sorgente sintetica'
    & (Join-Path $PSScriptRoot 'Start-DriveAura.ps1') `
        -StatePath $StatePath `
        -RemoteApiUrl $remoteUrl `
        -BatchSize 1 `
        -MaxRetries 2 `
        -ReadinessTimeoutSeconds (Get-DriveAuraVerificationRemaining `
            -Maximum 30 -Operation 'avvio dei servizi')
    $servicesStarted = $true

    $localUrl = ("http://127.0.0.1:{0}" -f $state.djangoPort)
    $bridgeUrl = ("http://127.0.0.1:{0}" -f $state.tomcatPort)
    Wait-DriveAuraHealth -BaseUrl $localUrl -ExpectedService 'local-django' `
        -TimeoutSeconds (Get-DriveAuraVerificationRemaining `
            -Maximum 5 -Operation 'readiness Django')
    Wait-DriveAuraHealth -BaseUrl $bridgeUrl -ExpectedService 'bridge-servlet' `
        -TimeoutSeconds (Get-DriveAuraVerificationRemaining `
            -Maximum 5 -Operation 'readiness servlet')
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
            -TimeoutSec (Get-DriveAuraVerificationRemaining `
                -Maximum 60 -Operation 'migrazione sintetica')
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
} catch {
    $verificationError = $_
} finally {
    if ($servicesStarted -or
        (Test-Path -LiteralPath (Join-Path ([string]$state.installRoot) 'processes.json'))) {
        try {
            & (Join-Path $PSScriptRoot 'Stop-DriveAura.ps1') -StatePath $StatePath
        } catch {
            $cleanupErrors.Add(("servizi locali: {0}" -f $_.Exception.Message))
        }
    }
    if ($null -ne $mockIdentity) {
        try {
            Stop-DriveAuraOwnedProcessTree -Identity $mockIdentity `
                -Label 'sorgente sintetica' -TimeoutSeconds 5
        } catch {
            $cleanupErrors.Add(("sorgente sintetica: {0}" -f $_.Exception.Message))
        }
    }
    Start-Sleep -Milliseconds 500
    try {
        Assert-DriveAuraPortAvailable -Port ([int]$state.syntheticRemotePort) `
            -Label 'Porta sorgente sintetica'
    } catch {
        $cleanupErrors.Add(("sorgente sintetica: {0}" -f $_.Exception.Message))
    }
}

if ($null -ne $verificationError) {
    $cleanupSuffix = if ($cleanupErrors.Count -gt 0) {
        " | Pulizia: $($cleanupErrors -join ' | ')"
    } else {
        ''
    }
    throw ("Verifica non riuscita: {0}{1}" -f
        $verificationError.Exception.Message, $cleanupSuffix)
}
if ($cleanupErrors.Count -gt 0) {
    throw ("Pulizia della verifica non riuscita: {0}" -f ($cleanupErrors -join ' | '))
}

$timer.Stop()
Write-Host ("PASS: salute, readiness, migrazione e audit completati in {0:N3} secondi." -f
    $timer.Elapsed.TotalSeconds)
