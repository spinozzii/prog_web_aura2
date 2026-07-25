[CmdletBinding()]
param(
    [string]$PythonPath,
    [string]$JavaHome,
    [string]$TomcatHome,
    [string]$PostgresBin,
    [string]$InstallRoot,
    [string]$PostgresHost = '127.0.0.1',
    [int]$PostgresPort = 5432,
    [string]$PostgresUser = 'postgres',
    [string]$PostgresDatabase = 'drive_aura_51',
    [string]$VerificationDatabase,
    [int]$DjangoPort = 8000,
    [int]$TomcatPort = 8080,
    [int]$TomcatShutdownPort = 8005,
    [int]$SyntheticRemotePort = 8081,
    [switch]$SkipVerification
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'DriveAura.Common.psm1') -Force

$timer = [Diagnostics.Stopwatch]::StartNew()
$packageRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
if ([string]::IsNullOrWhiteSpace($InstallRoot)) {
    $InstallRoot = Join-Path (Split-Path -Parent $packageRoot) 'drive-aura-51-runtime'
}
$installFullPath = [IO.Path]::GetFullPath($InstallRoot)
$packagePathPrefix = $packageRoot.TrimEnd('\') + '\'
$installPathPrefix = $installFullPath.TrimEnd('\') + '\'
if (
    $installFullPath.TrimEnd('\').Equals(
        $packageRoot.TrimEnd('\'),
        [StringComparison]::OrdinalIgnoreCase
    ) -or
    $installFullPath.StartsWith($packagePathPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    $packageRoot.StartsWith($installPathPrefix, [StringComparison]::OrdinalIgnoreCase)
) {
    throw 'InstallRoot deve essere una directory dedicata, esterna e non antenata del pacchetto.'
}
$installMarkerPath = Join-Path $installFullPath '.drive-aura-install.json'
if (Test-Path -LiteralPath $installFullPath -PathType Container) {
    $existingEntries = @(Get-ChildItem -LiteralPath $installFullPath -Force)
    if ($existingEntries.Count -gt 0) {
        if (-not (Test-Path -LiteralPath $installMarkerPath -PathType Leaf)) {
            throw 'InstallRoot non e vuota e non e riconoscibile come installazione Drive Aura.'
        }
        $existingMarker = Get-DriveAuraState -Path $installMarkerPath
        if ($existingMarker.apiVersion -ne '1.0' -or
            -not ([string]$existingMarker.packageRoot).Equals(
                $packageRoot,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw 'InstallRoot appartiene a un pacchetto diverso o ha un marcatore non valido.'
        }
        if (Test-Path -LiteralPath (Join-Path $installFullPath 'processes.json') -PathType Leaf) {
            throw 'Installazione in uso: eseguire Stop-DriveAura.ps1 prima di riconfigurare.'
        }
    }
}

Write-DriveAuraStep 'Verifica integrita del pacchetto.'
& (Join-Path $PSScriptRoot 'Test-PackageIntegrity.ps1') -PackageRoot $packageRoot

Assert-DriveAuraIdentifier -Value $PostgresUser -Label 'Utente PostgreSQL'
Assert-DriveAuraIdentifier -Value $PostgresDatabase -Label 'Database PostgreSQL'
if (-not $SkipVerification) {
    if ([string]::IsNullOrWhiteSpace($VerificationDatabase)) {
        $verificationStemLength = [Math]::Min($PostgresDatabase.Length, 56)
        $VerificationDatabase = $PostgresDatabase.Substring(0, $verificationStemLength) + '_verify'
    }
    Assert-DriveAuraIdentifier -Value $VerificationDatabase -Label 'Database PostgreSQL di verifica'
    if ($VerificationDatabase.Equals($PostgresDatabase, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Il database di verifica deve essere distinto dal database operativo.'
    }
}
Assert-DriveAuraSecrets
$ports = @($DjangoPort, $TomcatPort, $TomcatShutdownPort, $SyntheticRemotePort)
if (@($ports | Select-Object -Unique).Count -ne $ports.Count) {
    throw 'Le porte Django, Tomcat, arresto Tomcat e sorgente sintetica devono essere distinte.'
}

Write-DriveAuraStep 'Rilevamento Python, Java, Tomcat e PostgreSQL.'
$python = Get-DriveAuraPythonRuntime -PythonPath $PythonPath
$java = Get-DriveAuraJavaRuntime -JavaHome $JavaHome
$tomcat = Get-DriveAuraTomcatRuntime -TomcatHome $TomcatHome -JavaRuntime $java
$postgres = Get-DriveAuraPostgresRuntime -PostgresBin $PostgresBin
$wheelhouse = Test-DriveAuraWheelhouse -Wheelhouse (Join-Path $packageRoot 'wheelhouse')

Write-DriveAuraStep ("Runtime: Python {0}, Java {1}, Tomcat {2}, PostgreSQL {3}." -f
    $python.Version, $java.Version, $tomcat.Version, $postgres.Version)
Test-DriveAuraPostgresReady -PostgresRuntime $postgres -HostName $PostgresHost `
    -Port $PostgresPort -User $PostgresUser -Database 'postgres'

New-Item -ItemType Directory -Force -Path $installFullPath | Out-Null
Save-DriveAuraState -State ([pscustomobject]@{
        apiVersion = '1.0'
        packageRoot = $packageRoot
        createdBy = 'Drive Aura 51 offline configurator'
    }) -Path $installMarkerPath
$appRoot = Join-Path $installFullPath 'app'
New-Item -ItemType Directory -Force -Path $appRoot | Out-Null

Write-DriveAuraStep 'Preparazione dei sorgenti locali.'
$djangoSource = Join-Path $packageRoot 'source\local-django'
$sharedSource = Join-Path $packageRoot 'source\shared'
if (-not (Test-Path -LiteralPath (Join-Path $djangoSource 'manage.py') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $sharedSource 'entity-schema.json') -PathType Leaf)) {
    throw 'Sorgenti Django o schema condiviso mancanti dal pacchetto.'
}
Copy-Item -LiteralPath $djangoSource -Destination $appRoot -Recurse -Force
Copy-Item -LiteralPath $sharedSource -Destination $appRoot -Recurse -Force
$djangoRoot = Join-Path $appRoot 'local-django'

$venvRoot = Join-Path $installFullPath '.venv'
$venvPython = Join-Path $venvRoot 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    Write-DriveAuraStep "Creazione dell'ambiente virtuale Python locale."
    Invoke-DriveAuraExternal -FilePath $python.Path -Arguments (
        @($python.PrefixArguments) + @('-m', 'venv', $venvRoot)
    ) | Out-Null
}
if (-not (Test-Path -LiteralPath $venvPython -PathType Leaf)) {
    throw "Creazione dell'ambiente virtuale non riuscita."
}

Write-DriveAuraStep ("Installazione di {0} wheel esclusivamente offline." -f $wheelhouse.Count)
$oldPipNoIndex = $env:PIP_NO_INDEX
$oldPipDisable = $env:PIP_DISABLE_PIP_VERSION_CHECK
$oldPipConfigFile = $env:PIP_CONFIG_FILE
$oldPipFindLinks = $env:PIP_FIND_LINKS
$oldPipIndexUrl = $env:PIP_INDEX_URL
$oldPipExtraIndexUrl = $env:PIP_EXTRA_INDEX_URL
try {
    $env:PIP_NO_INDEX = '1'
    $env:PIP_DISABLE_PIP_VERSION_CHECK = '1'
    $env:PIP_CONFIG_FILE = 'NUL'
    $env:PIP_FIND_LINKS = $null
    $env:PIP_INDEX_URL = $null
    $env:PIP_EXTRA_INDEX_URL = $null
    Invoke-DriveAuraExternal -FilePath $venvPython -Arguments @(
        '-m', 'pip', 'install',
        '--no-index',
        '--disable-pip-version-check',
        '--require-hashes',
        '--find-links', $wheelhouse.Root,
        '--requirement', $wheelhouse.Requirements
    ) | Out-Null
} finally {
    $env:PIP_NO_INDEX = $oldPipNoIndex
    $env:PIP_DISABLE_PIP_VERSION_CHECK = $oldPipDisable
    $env:PIP_CONFIG_FILE = $oldPipConfigFile
    $env:PIP_FIND_LINKS = $oldPipFindLinks
    $env:PIP_INDEX_URL = $oldPipIndexUrl
    $env:PIP_EXTRA_INDEX_URL = $oldPipExtraIndexUrl
}

function Initialize-DriveAuraDatabase {
    param([Parameter(Mandatory = $true)][string]$Database)

    Write-DriveAuraStep ("Preparazione del database PostgreSQL {0}." -f $Database)
    if (-not (Test-DriveAuraDatabaseExists -PostgresRuntime $postgres -HostName $PostgresHost `
            -Port $PostgresPort -User $PostgresUser -Database $Database)) {
        New-DriveAuraDatabase -PostgresRuntime $postgres -HostName $PostgresHost `
            -Port $PostgresPort -User $PostgresUser -Database $Database
    }
    Test-DriveAuraPostgresReady -PostgresRuntime $postgres -HostName $PostgresHost `
        -Port $PostgresPort -User $PostgresUser -Database $Database

    $djangoEnvironment = @{
        POSTGRES_DB = $Database
        POSTGRES_USER = $PostgresUser
        POSTGRES_PASSWORD = $env:POSTGRES_PASSWORD
        POSTGRES_HOST = $PostgresHost
        POSTGRES_PORT = "$PostgresPort"
        LOCAL_API_SECRET = $env:LOCAL_API_SECRET
        DJANGO_SECRET_KEY = $env:DJANGO_SECRET_KEY
    }
    $previousDjangoEnvironment = Set-DriveAuraProcessEnvironment -Values $djangoEnvironment
    try {
        Push-Location $djangoRoot
        try {
            Write-DriveAuraStep ("Applicazione delle migrazioni Django a {0}." -f $Database)
            Invoke-DriveAuraExternal -FilePath $venvPython -Arguments @(
                'manage.py', 'migrate', '--noinput'
            ) | Out-Null
            Invoke-DriveAuraExternal -FilePath $venvPython -Arguments @(
                'manage.py', 'migrate', '--check'
            ) | Out-Null
        } finally {
            Pop-Location
        }
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $previousDjangoEnvironment
    }
}

Initialize-DriveAuraDatabase -Database $PostgresDatabase
if (-not $SkipVerification) {
    Initialize-DriveAuraDatabase -Database $VerificationDatabase
}

Write-DriveAuraStep 'Creazione del CATALINA_BASE isolato.'
$catalinaBase = Join-Path $installFullPath 'tomcat-base'
foreach ($directory in @('conf', 'logs', 'temp', 'webapps', 'work')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $catalinaBase $directory) | Out-Null
}
Copy-Item -Path (Join-Path $tomcat.Home 'conf\*') `
    -Destination (Join-Path $catalinaBase 'conf') -Recurse -Force
$serverXmlPath = Join-Path $catalinaBase 'conf\server.xml'
[xml]$serverXml = Get-Content -Raw -Encoding UTF8 -LiteralPath $serverXmlPath
$serverNode = $serverXml.SelectSingleNode('/Server')
if ($null -eq $serverNode) {
    throw 'Configurazione Tomcat non riconosciuta: elemento Server mancante.'
}
$serverNode.SetAttribute('port', "$TomcatShutdownPort")
$serverNode.SetAttribute('shutdown', ([guid]::NewGuid().ToString('N')))
$httpConnector = $null
foreach ($connector in @($serverXml.SelectNodes('/Server/Service/Connector'))) {
    $protocol = $connector.GetAttribute('protocol')
    if ([string]::IsNullOrWhiteSpace($protocol) -or $protocol -match 'HTTP') {
        $httpConnector = $connector
        break
    }
}
if ($null -eq $httpConnector) {
    throw 'Configurazione Tomcat non riconosciuta: connettore HTTP mancante.'
}
$httpConnector.SetAttribute('port', "$TomcatPort")
$httpConnector.SetAttribute('address', '127.0.0.1')
$serverXml.Save($serverXmlPath)

$warName = if ($tomcat.Major -eq 9) {
    'bridge-tomcat9.war'
} else {
    'bridge-tomcat11.war'
}
$warSource = Join-Path $packageRoot ("artifacts\{0}" -f $warName)
if (-not (Test-Path -LiteralPath $warSource -PathType Leaf)) {
    throw "WAR precompilato mancante: $warName"
}
Copy-Item -LiteralPath $warSource -Destination (Join-Path $catalinaBase 'webapps\ROOT.war') -Force

$statePath = Join-Path $installFullPath 'install-state.json'
$state = [pscustomobject]@{
    apiVersion = '1.0'
    packageRoot = $packageRoot
    installRoot = $installFullPath
    venvPython = $venvPython
    djangoRoot = $djangoRoot
    javaHome = $java.Home
    javaVersion = $java.Version
    tomcatHome = $tomcat.Home
    tomcatBase = $catalinaBase
    tomcatVersion = $tomcat.Version
    tomcatMajor = $tomcat.Major
    postgresBin = $postgres.Bin
    postgresVersion = $postgres.Version
    postgresHost = $PostgresHost
    postgresPort = $PostgresPort
    postgresUser = $PostgresUser
    postgresDatabase = $PostgresDatabase
    djangoPort = $DjangoPort
    tomcatPort = $TomcatPort
    tomcatShutdownPort = $TomcatShutdownPort
    syntheticRemotePort = $SyntheticRemotePort
    selectedWar = $warName
}
Save-DriveAuraState -State $state -Path $statePath

$secretsExample = @'
# Copiare soltanto nella propria sessione PowerShell. Non salvare valori reali nel pacchetto.
$env:POSTGRES_PASSWORD = '<password-postgresql>'
$env:DJANGO_SECRET_KEY = '<stringa-casuale-almeno-32-caratteri>'
$env:LOCAL_API_SECRET = '<segreto-locale-almeno-12-caratteri>'
$env:REMOTE_API_SECRET = '<segreto-remoto-almeno-12-caratteri>'
$env:BRIDGE_API_SECRET = '<segreto-bridge-almeno-12-caratteri>'
'@
$secretsExample | Set-Content -LiteralPath (Join-Path $installFullPath 'set-secrets.example.ps1') `
    -Encoding UTF8

if (-not $SkipVerification) {
    Write-DriveAuraStep 'Avvio della verifica sintetica completa.'
    $verificationStatePath = Join-Path $installFullPath 'verification-state.json'
    $verificationState = $state.PSObject.Copy()
    $verificationState.postgresDatabase = $VerificationDatabase
    Save-DriveAuraState -State $verificationState -Path $verificationStatePath
    & (Join-Path $PSScriptRoot 'Verify-DriveAura.ps1') -StatePath $verificationStatePath
}

$timer.Stop()
Write-Host ("PASS: configurazione completata in {0:N3} secondi." -f $timer.Elapsed.TotalSeconds)
Write-Host ("Stato locale: {0}" -f $statePath)
if (-not $SkipVerification) {
    Write-Host ("Database operativo pronto e non popolato dalla prova: {0}" -f $PostgresDatabase)
    Write-Host ("Stato della verifica sintetica: {0}" -f $verificationStatePath)
}
