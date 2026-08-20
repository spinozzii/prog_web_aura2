[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Wheelhouse,
    [Parameter(Mandatory = $true)][string]$PostgresBin,
    [string]$ExtractedPackageRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
Import-Module (Join-Path $repositoryRoot 'delivery\installer\DriveAura.Common.psm1') -Force
. (Join-Path $repositoryRoot 'delivery\installer\DriveAura.PathSafety.ps1')

$passed = 0
$failed = 0
function Invoke-ExpectedFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$MessagePattern
    )
    try {
        & $Action
        Write-Host "FAIL: $Name non ha rifiutato il caso avverso."
        $script:failed++
    } catch {
        if ($_.Exception.Message -notmatch $MessagePattern) {
            Write-Host ("FAIL: {0}; messaggio inatteso: {1}" -f $Name, $_.Exception.Message)
            $script:failed++
        } else {
            Write-Host "PASS: $Name"
            $script:passed++
        }
    }
}

function Wait-InstallerProbeProcess {
    param(
        [Parameter(Mandatory = $true)][Diagnostics.Process]$Process,
        [Parameter(Mandatory = $true)][string]$ExpectedExecutablePath,
        [Parameter(Mandatory = $true)][string]$Label,
        [ValidateRange(100, 5000)][int]$TimeoutMilliseconds = 2000
    )

    $identity = $null
    try {
        $identity = New-DriveAuraProcessIdentity `
            -Process $Process `
            -CommandMarker $Label `
            -ExpectedExecutablePath $ExpectedExecutablePath
        if ($Process.WaitForExit($TimeoutMilliseconds)) {
            return [int]$Process.ExitCode
        }

        if (Test-DriveAuraProcessIdentity -Identity $identity -Label $Label) {
            Stop-DriveAuraOwnedProcessTree `
                -Identity $identity -Label $Label -TimeoutSeconds 2
        }
        if (-not $Process.WaitForExit(1500)) {
            throw "Timeout $Label; il processo non si e chiuso dopo il cleanup mirato."
        }
        throw "Timeout $Label dopo $TimeoutMilliseconds millisecondi; processo arrestato."
    } finally {
        $Process.Dispose()
    }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("drive-aura-t09-tests-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $pathEnvironment = [Environment]::GetEnvironmentVariables('Process')
    $pathAliases = @(
        $pathEnvironment.Keys |
            Where-Object {
                [string]::Equals(
                    [string]$_,
                    'Path',
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    $pathValue = if ($pathAliases.Count -gt 0) {
        [string]$pathEnvironment[$pathAliases[0]]
    } else {
        ''
    }
    [Environment]::SetEnvironmentVariable('Path', $pathValue, 'Process')
    [Environment]::SetEnvironmentVariable('PATH', $pathValue, 'Process')
    Repair-DriveAuraPathEnvironment | Out-Null
    $normalizedAliases = @(
        [Environment]::GetEnvironmentVariables('Process').Keys |
            Where-Object {
                [string]::Equals(
                    [string]$_,
                    'Path',
                    [StringComparison]::OrdinalIgnoreCase
                )
            }
    )
    if ($normalizedAliases.Count -ne 1) {
        throw 'La normalizzazione Path/PATH non ha prodotto una chiave univoca.'
    }
    $processProbe = Start-Process -FilePath $env:ComSpec `
        -ArgumentList @('/d', '/c', 'exit 0') -WindowStyle Hidden -PassThru
    $processProbeExit = Wait-InstallerProbeProcess `
        -Process $processProbe `
        -ExpectedExecutablePath $env:ComSpec `
        -Label 'prova normale Start-Process' `
        -TimeoutMilliseconds 2000
    if ($processProbeExit -ne 0) {
        throw 'Il processo di prova non si e concluso correttamente.'
    }
    Write-Host 'PASS: ambiente Path/PATH normalizzato per Start-Process.'
    $passed++

    $timeoutProbe = Start-Process `
        -FilePath (Join-Path $env:SystemRoot 'System32\ping.exe') `
        -ArgumentList @('127.0.0.1', '-n', '30') `
        -WindowStyle Hidden -PassThru
    $timeoutProbePid = $timeoutProbe.Id
    $timeoutProbeTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        Wait-InstallerProbeProcess `
            -Process $timeoutProbe `
            -ExpectedExecutablePath (Join-Path $env:SystemRoot 'System32\ping.exe') `
            -Label 'prova timeout Start-Process' `
            -TimeoutMilliseconds 300 | Out-Null
        throw 'La prova timeout Start-Process non ha prodotto errore.'
    } catch {
        if ($_.Exception.Message -notmatch 'Timeout prova timeout Start-Process') {
            throw
        }
    } finally {
        $timeoutProbeTimer.Stop()
    }
    if ($timeoutProbeTimer.Elapsed.TotalSeconds -gt 5 -or
        $null -ne (Get-Process -Id $timeoutProbePid -ErrorAction SilentlyContinue)) {
        throw 'Il cleanup della prova timeout Start-Process non e terminato correttamente.'
    }
    Write-Host 'PASS: WaitForExit limitato, identita verificata e Dispose eseguito.'
    $passed++

    $commonModule = Get-Module | Where-Object {
        $_.Path -eq (Join-Path $repositoryRoot 'delivery\installer\DriveAura.Common.psm1')
    }
    if ($null -eq $commonModule) {
        throw 'Modulo comune installer non disponibile per la regressione cleanup.'
    }
    $identityRaceTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        $identityRaceCalls = & $commonModule {
            $script:driveAuraIdentityRaceCalls = 0
            $script:driveAuraIdentityRaceProcess = [pscustomobject]@{ Path = '' }
            function script:Get-Process {
                param([int]$Id, [object]$ErrorAction)

                $script:driveAuraIdentityRaceCalls++
                if ($script:driveAuraIdentityRaceCalls -le 2) {
                    return $script:driveAuraIdentityRaceProcess
                }
                return $null
            }
            try {
                Stop-DriveAuraOwnedProcessTree -Identity ([pscustomobject]@{
                        pid = 4242
                        executablePath = $env:ComSpec
                        startedUtcTicks = '1'
                        commandMarker = 'race cleanup Django simulata'
                    }) -Label 'Django simulato' -TimeoutSeconds 1
                return $script:driveAuraIdentityRaceCalls
            } finally {
                Remove-Item Function:\Get-Process -Force -ErrorAction SilentlyContinue
                Remove-Variable driveAuraIdentityRaceCalls,driveAuraIdentityRaceProcess `
                    -Scope Script -ErrorAction SilentlyContinue
            }
        }
    } finally {
        $identityRaceTimer.Stop()
    }
    if ($identityRaceCalls -lt 3 -or $identityRaceTimer.Elapsed.TotalSeconds -gt 3) {
        throw 'La race di uscita durante la verifica identita non e stata gestita entro il timeout.'
    }
    Write-Host 'PASS: processo gia terminato durante la verifica identita ignorato in sicurezza.'
    $passed++

    $shortProbe = 'C:\DriveAura51\drive-aura-51-offline'
    $null = Assert-DriveAuraPathBudget `
        -RootPath $shortProbe -RequiredRelativeLength 104 `
        -Label 'il percorso corto simulato'
    Invoke-ExpectedFailure -Name 'Percorso Windows troppo lungo' `
        -MessagePattern 'C:\\DriveAura51' -Action {
        $longProbe = 'C:\' + ('directory-lunga-' * 11)
        Assert-DriveAuraPathBudget `
            -RootPath $longProbe -RequiredRelativeLength 104 `
            -Label 'il percorso lungo simulato' | Out-Null
    }
    Write-Host 'PASS: percorso Windows corto accettato.'
    $passed++

    $parseErrors = New-Object System.Collections.Generic.List[object]
    $unsafeWaits = New-Object System.Collections.Generic.List[string]
    $powerShellFiles = @(
        foreach ($scanRoot in @(
                'delivery\installer',
                'delivery\tests',
                'scripts',
                'tests'
            )) {
            Get-ChildItem -Recurse -File `
                -LiteralPath (Join-Path $repositoryRoot $scanRoot) |
                Where-Object {
                    $_.Extension -ieq '.ps1' -or $_.Extension -ieq '.psm1'
                }
        }
    )
    foreach ($scriptFile in $powerShellFiles) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $scriptFile.FullName,
            [ref]$tokens,
            [ref]$errors
        )
        foreach ($parseError in @($errors)) {
            $parseErrors.Add($parseError)
        }
        foreach ($call in @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    [string]$node.Member.Value -eq 'WaitForExit' -and
                    $node.Arguments.Count -eq 0
                }, $true))) {
            $unsafeWaits.Add("$($scriptFile.FullName):$($call.Extent.StartLineNumber)")
        }
    }
    if ($parseErrors.Count -gt 0 -or $unsafeWaits.Count -gt 0) {
        throw ('Audit PowerShell non valido; parse={0}; WaitForExit senza timeout={1}: {2}' -f
            $parseErrors.Count, $unsafeWaits.Count, ($unsafeWaits -join ', '))
    }
    Write-Host 'PASS: audit AST senza WaitForExit privo di timeout.'
    $passed++

    $externalTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        Invoke-DriveAuraExternal `
            -FilePath (Join-Path $env:SystemRoot 'System32\ping.exe') `
            -Arguments @('127.0.0.1', '-n', '30') `
            -TimeoutSeconds 1 | Out-Null
        throw 'Il processo esterno bloccato non ha prodotto timeout.'
    } catch {
        if ($_.Exception.Message -notmatch 'Timeout') {
            throw
        }
    } finally {
        $externalTimer.Stop()
    }
    if ($externalTimer.Elapsed.TotalSeconds -gt 8) {
        throw "Timeout processo esterno troppo lento: $($externalTimer.Elapsed.TotalSeconds) secondi."
    }
    Write-Host 'PASS: processo esterno arrestato entro il timeout finito.'
    $passed++

    $metacharRoot = Join-Path $tempRoot 'external-&-probe'
    New-Item -ItemType Directory -Path $metacharRoot | Out-Null
    $metacharBatch = Join-Path $metacharRoot 'probe.cmd'
    @('@echo off', 'echo METACHAR_OK') |
        Set-Content -LiteralPath $metacharBatch -Encoding ASCII
    $metacharResult = Invoke-DriveAuraExternal -FilePath $metacharBatch `
        -TimeoutSeconds 5
    if ($metacharResult.ExitCode -ne 0 -or
        $metacharResult.Output -notmatch 'METACHAR_OK') {
        throw 'Il comando batch in un percorso con metacaratteri non e stato eseguito.'
    }
    Write-Host 'PASS: comando batch in percorso con metacaratteri gestito.'
    $passed++

    $percentRoot = Join-Path $tempRoot 'external-%TEMP%-probe'
    New-Item -ItemType Directory -Path $percentRoot | Out-Null
    $percentBatch = Join-Path $percentRoot 'probe.cmd'
    @('@echo off', 'echo PERCENT_PATH') |
        Set-Content -LiteralPath $percentBatch -Encoding ASCII
    Invoke-ExpectedFailure -Name 'Percorso batch con percentuale ambiguo' `
        -MessagePattern 'carattere %' -Action {
        Invoke-DriveAuraExternal -FilePath $percentBatch -TimeoutSeconds 5 |
            Out-Null
    }

    $orphanRoot = Join-Path $tempRoot 'external child with spaces'
    New-Item -ItemType Directory -Path $orphanRoot | Out-Null
    $orphanPidPath = Join-Path $orphanRoot 'child.pid'
    $orphanChildPath = Join-Path $orphanRoot 'orphan-child.ps1'
    $orphanParentPath = Join-Path $orphanRoot 'spawn-orphan.ps1'
    @'
param([Parameter(Mandatory = $true)][string]$PidPath)
[IO.File]::WriteAllText($PidPath, [string]$PID)
Start-Sleep -Seconds 30
'@ | Set-Content -LiteralPath $orphanChildPath -Encoding UTF8
    @'
param(
    [Parameter(Mandatory = $true)][string]$ChildPath,
    [Parameter(Mandatory = $true)][string]$PidPath
)
$powershellPath = (Get-Process -Id $PID).Path
$argumentLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}" "{1}"' -f `
    $ChildPath.Replace('"', '""'), $PidPath.Replace('"', '""')
$child = Start-Process -FilePath $powershellPath -ArgumentList $argumentLine `
    -WindowStyle Hidden -PassThru
$deadline = [DateTime]::UtcNow.AddSeconds(5)
while (-not (Test-Path -LiteralPath $PidPath) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 50
}
if (-not (Test-Path -LiteralPath $PidPath)) {
    throw "Il figlio PID $($child.Id) non ha scritto il file di controllo."
}
'@ | Set-Content -LiteralPath $orphanParentPath -Encoding UTF8
    $powershellExecutable = (Get-Process -Id $PID).Path
    $orphanTimer = [Diagnostics.Stopwatch]::StartNew()
    Invoke-DriveAuraExternal -FilePath $powershellExecutable -Arguments @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $orphanParentPath,
        $orphanChildPath,
        $orphanPidPath
    ) -TimeoutSeconds 8 | Out-Null
    $orphanTimer.Stop()
    if (-not (Test-Path -LiteralPath $orphanPidPath -PathType Leaf)) {
        throw 'Il test del figlio esterno non ha prodotto il PID.'
    }
    $orphanPid = [int](Get-Content -Raw -LiteralPath $orphanPidPath)
    Start-Sleep -Milliseconds 250
    if ($null -ne (Get-Process -Id $orphanPid -ErrorAction SilentlyContinue)) {
        throw "Il figlio esterno PID $orphanPid e rimasto attivo."
    }
    if ($orphanTimer.Elapsed.TotalSeconds -gt 10) {
        throw "Chiusura albero esterno troppo lenta: $($orphanTimer.Elapsed.TotalSeconds) secondi."
    }
    Write-Host 'PASS: figli esterni e handle chiusi quando termina il processo radice.'
    $passed++

    $identityRoot = Join-Path $tempRoot 'identity round trip'
    New-Item -ItemType Directory -Path $identityRoot | Out-Null
    $identityWrapper = Join-Path $identityRoot 'long-running.bat'
    @(
        '@echo off',
        '"%SystemRoot%\System32\ping.exe" 127.0.0.1 -n 30 >NUL'
    ) | Set-Content -LiteralPath $identityWrapper -Encoding ASCII
    $identity = Start-DriveAuraManagedProcess `
        -WrapperPath $identityWrapper -WorkingDirectory $identityRoot
    $identityStatePath = Join-Path $identityRoot 'identity.json'
    try {
        Save-DriveAuraState -State ([pscustomobject]@{
                apiVersion = '1.0'
                process = $identity
            }) -Path $identityStatePath
        $roundTripIdentity = (Get-DriveAuraState -Path $identityStatePath).process
        if ($roundTripIdentity.startedUtcTicks -isnot [string]) {
            throw 'L istante del processo non e stato serializzato come testo esatto.'
        }
        if (-not (Test-DriveAuraProcessIdentity `
                -Identity $roundTripIdentity -Label 'round-trip JSON')) {
            throw 'Il processo round-trip non e piu attivo.'
        }
    } finally {
        Stop-DriveAuraOwnedProcessTree -Identity $identity `
            -Label 'round-trip JSON' -TimeoutSeconds 3
    }
    Write-Host 'PASS: identita PID preservata esattamente nel round-trip JSON.'
    $passed++

    $managedRoot = Join-Path $tempRoot 'managed process with spaces'
    New-Item -ItemType Directory -Path $managedRoot | Out-Null
    $failedLog = Join-Path $managedRoot 'failed-start.log'
    $failedWrapper = Join-Path $managedRoot 'failed-start.bat'
    @(
        '@echo off',
        ('echo avvio intenzionalmente fallito 1>>"{0}" 2>&1' -f $failedLog),
        'exit /b 23'
    ) | Set-Content -LiteralPath $failedWrapper -Encoding ASCII
    $probeListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $probeListener.Start()
    $failedPort = ([Net.IPEndPoint]$probeListener.LocalEndpoint).Port
    $probeListener.Stop()
    $failedIdentity = Start-DriveAuraManagedProcess `
        -WrapperPath $failedWrapper -WorkingDirectory $managedRoot
    $failedTimer = [Diagnostics.Stopwatch]::StartNew()
    try {
        Wait-DriveAuraHealth -BaseUrl ("http://127.0.0.1:{0}" -f $failedPort) `
            -ExpectedService 'bridge-servlet' -TimeoutSeconds 3 `
            -ProcessIdentity $failedIdentity -ProcessLabel 'Tomcat simulato'
        throw 'La readiness ha accettato un avvio fallito.'
    } catch {
        if ($_.Exception.Message -notmatch 'terminato prima della readiness') {
            throw
        }
    } finally {
        Stop-DriveAuraOwnedProcessTree -Identity $failedIdentity `
            -Label 'Tomcat simulato' -TimeoutSeconds 2
        $failedTimer.Stop()
    }
    if ($failedTimer.Elapsed.TotalSeconds -gt 5) {
        throw "Regressione avvio fallito oltre timeout: $($failedTimer.Elapsed.TotalSeconds) secondi."
    }
    Assert-DriveAuraPortAvailable -Port $failedPort -Label 'Porta avvio fallito'
    $exclusive = [IO.File]::Open(
        $failedLog,
        [IO.FileMode]::Open,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    $exclusive.Dispose()
    $renamedLog = $failedLog + '.renamed'
    Move-Item -LiteralPath $failedLog -Destination $renamedLog
    Move-Item -LiteralPath $renamedLog -Destination $failedLog
    Write-Host 'PASS: avvio fallito, cleanup e rilascio handle entro il timeout.'
    $passed++

    Assert-DriveAuraRemoteUrl -Value 'http://127.0.0.1:18081/api' | Out-Null
    Assert-DriveAuraRemoteUrl -Value 'http://localhost:18081/api' | Out-Null
    Assert-DriveAuraRemoteUrl -Value 'https://account.altervista.org/api' | Out-Null
    Invoke-ExpectedFailure -Name 'HTTP remoto non cifrato' -MessagePattern 'HTTPS' -Action {
        Assert-DriveAuraRemoteUrl -Value 'http://remote.example/api' | Out-Null
    }
    Write-Host 'PASS: HTTP loopback e HTTPS remoto ammessi.'
    $passed++

    Invoke-ExpectedFailure -Name 'Python mancante' -MessagePattern 'Python 3\.12' -Action {
        Get-DriveAuraPythonRuntime -PythonPath (Join-Path $tempRoot 'missing-python.exe') | Out-Null
    }

    $fakePython = Join-Path $tempRoot 'python313.cmd'
    @('@echo off', 'echo 3.13.9^|64', 'exit /b 0') |
        Set-Content -LiteralPath $fakePython -Encoding ASCII
    Invoke-ExpectedFailure -Name 'Python incompatibile' -MessagePattern 'incompatibile' -Action {
        Get-DriveAuraPythonRuntime -PythonPath $fakePython | Out-Null
    }

    Invoke-ExpectedFailure -Name 'Java mancante' -MessagePattern 'Java non trovato' -Action {
        Get-DriveAuraJavaRuntime -JavaHome (Join-Path $tempRoot 'missing-java') | Out-Null
    }

    Invoke-ExpectedFailure -Name 'Java incompatibile' -MessagePattern 'Java 8' -Action {
        Assert-DriveAuraJavaTomcatCompatibility -JavaMajor 7 -TomcatMajor 9
    }

    Invoke-ExpectedFailure -Name 'Java incompatibile con Tomcat 11' `
        -MessagePattern 'Java 17' -Action {
        Assert-DriveAuraJavaTomcatCompatibility -JavaMajor 8 -TomcatMajor 11
    }

    $fakeJavaRuntime = [pscustomobject]@{ Home = $tempRoot; Major = 17 }
    Invoke-ExpectedFailure -Name 'Tomcat mancante' -MessagePattern 'Tomcat non trovato' -Action {
        Get-DriveAuraTomcatRuntime -TomcatHome (Join-Path $tempRoot 'missing-tomcat') `
            -JavaRuntime $fakeJavaRuntime | Out-Null
    }

    $fakeTomcat = Join-Path $tempRoot 'tomcat10'
    foreach ($directory in @('bin', 'lib', 'conf')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $fakeTomcat $directory) | Out-Null
    }
    '@echo off' | Set-Content -LiteralPath (Join-Path $fakeTomcat 'bin\catalina.bat') -Encoding ASCII
    @('@echo off', 'echo Server version: Apache Tomcat/10.1.0') |
        Set-Content -LiteralPath (Join-Path $fakeTomcat 'bin\version.bat') -Encoding ASCII
    '' | Set-Content -LiteralPath (Join-Path $fakeTomcat 'lib\catalina.jar') -Encoding ASCII
    '<Server />' | Set-Content -LiteralPath (Join-Path $fakeTomcat 'conf\server.xml') -Encoding ASCII
    Invoke-ExpectedFailure -Name 'Tomcat non riconosciuto' -MessagePattern 'Tomcat 10 non supportato' -Action {
        Get-DriveAuraTomcatRuntime -TomcatHome $fakeTomcat -JavaRuntime $fakeJavaRuntime | Out-Null
    }

    Invoke-ExpectedFailure -Name 'PostgreSQL mancante' -MessagePattern 'PostgreSQL non riconosciuto' -Action {
        Get-DriveAuraPostgresRuntime -PostgresBin $tempRoot | Out-Null
    }

    Invoke-ExpectedFailure -Name 'PostgreSQL incompatibile' -MessagePattern 'incompatibile' -Action {
        Assert-DriveAuraPostgresVersionCompatibility -Major 13
    }

    $postgresRuntime = Get-DriveAuraPostgresRuntime -PostgresBin $PostgresBin
    $savedPassword = $env:POSTGRES_PASSWORD
    $env:POSTGRES_PASSWORD = 'offline-test-password'
    try {
        Invoke-ExpectedFailure -Name 'PostgreSQL non raggiungibile' `
            -MessagePattern 'non raggiungibile' -Action {
            Test-DriveAuraPostgresReady -PostgresRuntime $postgresRuntime `
                -HostName '127.0.0.1' -Port 65432 -User 'postgres' -Database 'postgres'
        }
    } finally {
        $env:POSTGRES_PASSWORD = $savedPassword
    }

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        $occupiedPort = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
        Invoke-ExpectedFailure -Name 'Porta occupata' -MessagePattern 'occupata' -Action {
            Assert-DriveAuraPortAvailable -Port $occupiedPort -Label 'Porta test'
        }
    } finally {
        $listener.Stop()
    }

    $savedBridgeSecret = $env:BRIDGE_API_SECRET
    try {
        $env:BRIDGE_API_SECRET = $null
        Invoke-ExpectedFailure -Name 'Segreto mancante' -MessagePattern 'BRIDGE_API_SECRET' -Action {
            Assert-DriveAuraSecrets -Names @('BRIDGE_API_SECRET')
        }
    } finally {
        $env:BRIDGE_API_SECRET = $savedBridgeSecret
    }

    $foreignInstallRoot = Join-Path $tempRoot 'foreign-install-root'
    New-Item -ItemType Directory -Path $foreignInstallRoot | Out-Null
    'file estraneo' | Set-Content -LiteralPath (Join-Path $foreignInstallRoot 'unrelated.txt') `
        -Encoding ASCII
    Invoke-ExpectedFailure -Name 'InstallRoot estranea non vuota' `
        -MessagePattern 'non e vuota' -Action {
        & (Join-Path $repositoryRoot 'delivery\installer\Configure-DriveAura.ps1') `
            -InstallRoot $foreignInstallRoot
    }

    $wheelCopy = Join-Path $tempRoot 'wheelhouse'
    Copy-Item -LiteralPath $Wheelhouse -Destination $wheelCopy -Recurse
    $firstWheel = Get-ChildItem -LiteralPath $wheelCopy -File -Filter '*.whl' |
        Sort-Object Name | Select-Object -First 1
    if ($null -eq $firstWheel) {
        throw 'Wheelhouse di test vuota.'
    }
    [IO.File]::AppendAllText($firstWheel.FullName, 'alterato')
    Invoke-ExpectedFailure -Name 'Wheel o checksum alterato' -MessagePattern 'Checksum wheel' -Action {
        Test-DriveAuraWheelhouse -Wheelhouse $wheelCopy | Out-Null
    }

    $configureText = Get-Content -Raw -Encoding UTF8 `
        -LiteralPath (Join-Path $repositoryRoot 'delivery\installer\Configure-DriveAura.ps1')
    if ($configureText -notmatch '--no-index' -or
        $configureText -notmatch '--require-hashes' -or
        $configureText -notmatch 'PIP_CONFIG_FILE' -or
        $configureText -notmatch 'PIP_FIND_LINKS' -or
        $configureText -match 'Invoke-WebRequest|Start-BitsTransfer|curl\.exe') {
        throw 'Il configuratore non garantisce installazione senza rete.'
    }
    Write-Host 'PASS: assenza di rete (nessun downloader e pip --no-index/--require-hashes).'
    $passed++
    if ($configureText -notmatch 'org\.apache\.coyote\.http11\.Http11Nio2Protocol') {
        throw 'Il configuratore non forza il connector NIO2 compatibile con il contesto Windows.'
    }
    Write-Host 'PASS: connector Tomcat NIO2 configurato per Tomcat 9 e 11.'
    $passed++

    $startText = Get-Content -Raw -Encoding UTF8 `
        -LiteralPath (Join-Path $repositoryRoot 'delivery\installer\Start-DriveAura.ps1')
    $settingsText = Get-Content -Raw -Encoding UTF8 `
        -LiteralPath (Join-Path $repositoryRoot 'local-django\health_service\settings.py')
    if ($startText -notmatch "DJANGO_SETTINGS_MODULE\s*=\s*'health_service\.settings'" -or
        $startText -notmatch 'DJANGO_TEST_SQLITE\s*=\s*\$null' -or
        $settingsText -match 'DJANGO_TEST_SQLITE|sqlite3') {
        throw 'Il servizio operativo puo ereditare impostazioni SQLite di test.'
    }
    Write-Host 'PASS: impostazioni operative Django vincolate a PostgreSQL.'
    $passed++

    if (-not [string]::IsNullOrWhiteSpace($ExtractedPackageRoot)) {
        $tamperedPackage = Join-Path $tempRoot 'tampered-package'
        Copy-Item -LiteralPath $ExtractedPackageRoot -Destination $tamperedPackage -Recurse
        [IO.File]::AppendAllText((Join-Path $tamperedPackage 'README.md'), 'alterato')
        Invoke-ExpectedFailure -Name 'Archivio estratto alterato' -MessagePattern 'hash|checksum|integrita' -Action {
            & (Join-Path $tamperedPackage 'installer\Test-PackageIntegrity.ps1') `
                -PackageRoot $tamperedPackage
        }
    }
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('drive-aura-t09-tests-')) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
    }
}

if ($failed -ne 0) {
    throw "$failed casi avversi non superati; $passed superati."
}
Write-Host "PASS: $passed casi avversi superati."
