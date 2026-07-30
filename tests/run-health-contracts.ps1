param(
    [switch]$AllowPartial
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$skipped = [System.Collections.Generic.List[string]]::new()

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
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
    $listener.Stop()
    return $port
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
        & $javac.Source --release 8 -d $outputDirectory $javaSources
        if ($LASTEXITCODE -ne 0) { throw 'javac ha restituito un errore.' }
        & $java.Source -cp $outputDirectory it.unibg.driveaura.bridge.core.HealthResponseTest
        if ($LASTEXITCODE -ne 0) { throw 'java ha restituito un errore.' }
        & $java.Source -cp $outputDirectory it.unibg.driveaura.bridge.core.PatologiaCanonicalizerTest `
            (Join-Path $projectRoot 'tests/fixtures/patologia-canonical.json') `
            (Join-Path $projectRoot 'tests/fixtures/patologia-empty.json') `
            (Join-Path $projectRoot 'tests/fixtures/patologia-line-separators.json')
        if ($LASTEXITCODE -ne 0) { throw 'Test Java di canonicalizzazione ha restituito un errore.' }
        & $java.Source -cp $outputDirectory it.unibg.driveaura.bridge.core.MigrationOrchestratorTest `
            (Join-Path $projectRoot 'shared/entity-schema.json') `
            (Join-Path $projectRoot 'tests/fixtures/t03-dataset.json')
        if ($LASTEXITCODE -ne 0) { throw "Test Java dell'orchestratore ha restituito un errore." }
    } finally {
        Remove-Item -Recurse -Force -LiteralPath $outputDirectory -ErrorAction SilentlyContinue
    }
}

Invoke-OrSkip 'PHP isolated and HTTP contracts' {
    $php = Get-Command php -ErrorAction Stop
    & $php.Source (Join-Path $projectRoot 'remote-php/tests/HealthResponseTest.php')
    if ($LASTEXITCODE -ne 0) { throw 'Il test unitario PHP ha restituito un errore.' }
    & $php.Source (Join-Path $projectRoot 'remote-php/tests/PatologiaCanonicalizerTest.php')
    if ($LASTEXITCODE -ne 0) { throw 'Il test PHP di canonicalizzazione ha restituito un errore.' }
    & $php.Source (Join-Path $projectRoot 'remote-php/tests/PatologiaApiTest.php')
    if ($LASTEXITCODE -ne 0) { throw "Il test PHP dell'API Patologia ha restituito un errore." }

    $port = Get-FreePort
    $documentRoot = Join-Path $projectRoot 'remote-php/public'
    $arguments = "-S 127.0.0.1:$port -t `"$documentRoot`""
    $process = Start-Process -FilePath $php.Source -ArgumentList $arguments -PassThru -WindowStyle Hidden
    try {
        $response = $null
        foreach ($attempt in 1..20) {
            try {
                $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1
                break
            } catch {
                if ($attempt -eq 20) { throw }
                Start-Sleep -Milliseconds 150
            }
        }
        if ($response.StatusCode -ne 200) { throw "HTTP PHP inatteso: $($response.StatusCode)." }
        if ($response.Headers['Content-Type'] -ne 'application/json; charset=utf-8') { throw "Content-Type PHP inatteso: $($response.Headers['Content-Type'])." }
        $body = $response.Content | ConvertFrom-Json
        if ($body.apiVersion -ne '1.0' -or $body.service -ne 'remote-php' -or $body.status -ne 'ok') { throw 'Corpo salute PHP non valido.' }
    } finally {
        if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }

    $prefixedPort = Get-FreePort
    $prefixedArguments = "-S 127.0.0.1:$prefixedPort -t `"$projectRoot`""
    $prefixedProcess = Start-Process -FilePath $php.Source -ArgumentList $prefixedArguments -PassThru -WindowStyle Hidden
    try {
        $prefixedResponse = $null
        foreach ($attempt in 1..20) {
            try {
                $prefixedResponse = Invoke-WebRequest -UseBasicParsing `
                    -Uri "http://127.0.0.1:$prefixedPort/remote-php/public/health" `
                    -TimeoutSec 1
                break
            } catch {
                if ($attempt -eq 20) { throw }
                Start-Sleep -Milliseconds 150
            }
        }
        if ($prefixedResponse.StatusCode -ne 200) {
            throw "HTTP PHP con prefisso inatteso: $($prefixedResponse.StatusCode)."
        }
        $prefixedBody = $prefixedResponse.Content | ConvertFrom-Json
        if ($prefixedBody.service -ne 'remote-php' -or $prefixedBody.status -ne 'ok') {
            throw 'Routing PHP in sottocartella non valido.'
        }
    } finally {
        if ($prefixedProcess -and -not $prefixedProcess.HasExited) {
            Stop-Process -Id $prefixedProcess.Id -Force
        }
    }
}

Invoke-OrSkip 'Django isolated contracts' {
    $python = Get-Command python -ErrorAction Stop
    $version = & $python.Source -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    if ($LASTEXITCODE -ne 0 -or $version.Trim() -ne '3.12') { throw "Python 3.12 richiesto; rilevato $version." }
    Push-Location (Join-Path $projectRoot 'local-django')
    try {
        & $python.Source manage.py test health_service `
            --settings health_service.test_settings
        if ($LASTEXITCODE -ne 0) { throw 'Il test Django ha restituito un errore.' }
    } finally {
        Pop-Location
    }
}

if ($skipped.Count -gt 0) {
    Write-Warning ("Riepilogo parziale: " + ($skipped -join '; '))
    exit 0
}

Write-Output 'PASS: tutti i contratti isolati sono stati eseguiti.'
