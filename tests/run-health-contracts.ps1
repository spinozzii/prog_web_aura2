param(
    [switch]$AllowPartial
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$skipped = [System.Collections.Generic.List[string]]::new()
$commonModule = @(
    (Join-Path $projectRoot 'delivery\installer\DriveAura.Common.psm1'),
    (Join-Path $projectRoot '..\installer\DriveAura.Common.psm1')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($commonModule)) {
    throw 'Modulo bounded-process Drive Aura mancante.'
}
Import-Module $commonModule -Force

function Invoke-OrSkip {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        Write-Output "PASS: $Name"
    } catch {
        if (-not $AllowPartial) { throw }
        $skipped.Add("$Name ($($_.Exception.Message))")
        Write-Warning "SKIP: $Name - $($_.Exception.Message)"
    }
}

function Get-FreePort {
    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new(
            [System.Net.IPAddress]::Loopback,
            0
        )
        $listener.Start()
        return ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Write-ExternalOutput {
    param([psobject]$Result)
    if ($null -ne $Result -and
        -not [string]::IsNullOrWhiteSpace([string]$Result.Output)) {
        Write-Output ([string]$Result.Output)
    }
}

function Start-ContractPhpServer {
    param(
        [Parameter(Mandatory = $true)][string]$PhpPath,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $process = Start-Process -FilePath $PhpPath -ArgumentList $Arguments `
        -PassThru -WindowStyle Hidden
    try {
        return New-DriveAuraProcessIdentity `
            -Process $process `
            -CommandMarker $Label `
            -ExpectedExecutablePath $PhpPath
    } finally {
        $process.Dispose()
    }
}

Invoke-OrSkip 'Java core isolated contracts' {
    $javac = Get-Command javac -ErrorAction Stop
    $java = Get-Command java -ErrorAction Stop
    $outputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("drive-aura-health-contracts-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    try {
        $javaSources = @(
            Get-ChildItem -Recurse -LiteralPath (Join-Path $projectRoot 'bridge-servlet/core/src/main/java') -Filter '*.java'
            Get-ChildItem -Recurse -LiteralPath (Join-Path $projectRoot 'bridge-servlet/core/src/test/java') -Filter '*.java'
        ) | ForEach-Object { $_.FullName }
        if ($javaSources.Count -eq 0) { throw 'Sorgenti o test Java mancanti.' }
        Write-ExternalOutput (Invoke-DriveAuraExternal `
            -FilePath $javac.Source `
            -Arguments (@('--release', '8', '-d', $outputDirectory) + $javaSources) `
            -TimeoutSeconds 60)
        Write-ExternalOutput (Invoke-DriveAuraExternal `
            -FilePath $java.Source `
            -Arguments @('-cp', $outputDirectory,
                'it.unibg.driveaura.bridge.core.HealthResponseTest') `
            -TimeoutSeconds 15)
        Write-ExternalOutput (Invoke-DriveAuraExternal `
            -FilePath $java.Source `
            -Arguments @(
                '-cp', $outputDirectory,
                'it.unibg.driveaura.bridge.core.PatologiaCanonicalizerTest',
                (Join-Path $projectRoot 'tests/fixtures/patologia-canonical.json'),
                (Join-Path $projectRoot 'tests/fixtures/patologia-empty.json'),
                (Join-Path $projectRoot 'tests/fixtures/patologia-line-separators.json')
            ) -TimeoutSeconds 15)
        Write-ExternalOutput (Invoke-DriveAuraExternal `
            -FilePath $java.Source `
            -Arguments @(
                '-cp', $outputDirectory,
                'it.unibg.driveaura.bridge.core.MigrationOrchestratorTest',
                (Join-Path $projectRoot 'shared/entity-schema.json'),
                (Join-Path $projectRoot 'tests/fixtures/t03-dataset.json')
            ) -TimeoutSeconds 30)
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $outputDirectory -ErrorAction SilentlyContinue
    }
}

Invoke-OrSkip 'PHP isolated and HTTP contracts' {
    $php = Get-Command php -ErrorAction Stop
    foreach ($testName in @(
            'HealthResponseTest.php',
            'PatologiaCanonicalizerTest.php',
            'PatologiaApiTest.php',
            'PdoTimeoutPolicyTest.php',
            'RuntimeConfigTest.php'
        )) {
        Write-ExternalOutput (Invoke-DriveAuraExternal `
            -FilePath $php.Source `
            -Arguments @((Join-Path $projectRoot "remote-php/tests/$testName")) `
            -TimeoutSeconds 30)
    }

    $port = Get-FreePort
    $documentRoot = Join-Path $projectRoot 'remote-php/public'
    $arguments = "-S 127.0.0.1:$port -t `"$documentRoot`""
    $processIdentity = Start-ContractPhpServer `
        -PhpPath $php.Source -Arguments $arguments -Label 'server PHP contratto salute'
    try {
        Wait-DriveAuraHealth -BaseUrl "http://127.0.0.1:$port" `
            -ExpectedService 'remote-php' -TimeoutSeconds 5 `
            -ProcessIdentity $processIdentity -ProcessLabel 'server PHP'
        $response = Invoke-WebRequest -UseBasicParsing `
            -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2
        if ($response.StatusCode -ne 200) { throw "HTTP PHP inatteso: $($response.StatusCode)." }
        if ($response.Headers['Content-Type'] -ne 'application/json; charset=utf-8') { throw "Content-Type PHP inatteso: $($response.Headers['Content-Type'])." }
        $body = $response.Content | ConvertFrom-Json
        if ($body.apiVersion -ne '1.0' -or $body.service -ne 'remote-php' -or $body.status -ne 'ok') { throw 'Corpo salute PHP non valido.' }
    } finally {
        Stop-DriveAuraOwnedProcessTree `
            -Identity $processIdentity -Label 'server PHP contratto salute' `
            -TimeoutSeconds 3
    }

    $prefixedPort = Get-FreePort
    $prefixedArguments = "-S 127.0.0.1:$prefixedPort -t `"$projectRoot`""
    $prefixedIdentity = Start-ContractPhpServer `
        -PhpPath $php.Source -Arguments $prefixedArguments `
        -Label 'server PHP contratto prefisso'
    try {
        $prefixedBase = "http://127.0.0.1:$prefixedPort/remote-php/public"
        Wait-DriveAuraHealth -BaseUrl $prefixedBase `
            -ExpectedService 'remote-php' -TimeoutSeconds 5 `
            -ProcessIdentity $prefixedIdentity -ProcessLabel 'server PHP con prefisso'
        $prefixedResponse = Invoke-WebRequest -UseBasicParsing `
            -Uri ($prefixedBase + '/health') -TimeoutSec 2
        if ($prefixedResponse.StatusCode -ne 200) {
            throw "HTTP PHP con prefisso inatteso: $($prefixedResponse.StatusCode)."
        }
        $prefixedBody = $prefixedResponse.Content | ConvertFrom-Json
        if ($prefixedBody.service -ne 'remote-php' -or $prefixedBody.status -ne 'ok') {
            throw 'Routing PHP in sottocartella non valido.'
        }
    } finally {
        Stop-DriveAuraOwnedProcessTree `
            -Identity $prefixedIdentity -Label 'server PHP contratto prefisso' `
            -TimeoutSeconds 3
    }
}

Invoke-OrSkip 'Django isolated contracts' {
    $python = Get-Command python -ErrorAction Stop
    $versionResult = Invoke-DriveAuraExternal -FilePath $python.Source `
        -Arguments @('-c', "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')") `
        -TimeoutSeconds 10
    $version = $versionResult.Output.Trim()
    if ($version -ne '3.12') { throw "Python 3.12 richiesto; rilevato $version." }
    Push-Location (Join-Path $projectRoot 'local-django')
    try {
        Write-ExternalOutput (Invoke-DriveAuraExternal `
            -FilePath $python.Source `
            -Arguments @('manage.py', 'test', 'health_service',
                '--settings', 'health_service.test_settings') `
            -TimeoutSeconds 120)
    } finally {
        Pop-Location
    }
}

if ($skipped.Count -gt 0) {
    Write-Warning ("Riepilogo parziale: " + ($skipped -join '; '))
    exit 0
}

Write-Output 'PASS: tutti i contratti isolati sono stati eseguiti.'
