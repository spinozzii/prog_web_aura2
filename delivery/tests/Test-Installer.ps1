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

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("drive-aura-t09-tests-{0}" -f [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
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
