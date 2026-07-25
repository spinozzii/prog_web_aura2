[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StatePath,
    [Parameter(Mandatory = $true)][string]$RemoteApiUrl,
    [ValidateRange(1, 100)][int]$BatchSize = 50,
    [ValidateRange(0, 5)][int]$MaxRetries = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'DriveAura.Common.psm1') -Force

$state = Get-DriveAuraState -Path $StatePath
Assert-DriveAuraSecrets

$remoteUri = $null
if (-not [uri]::TryCreate($RemoteApiUrl, [UriKind]::Absolute, [ref]$remoteUri) -or
    ($remoteUri.Scheme -ne 'http' -and $remoteUri.Scheme -ne 'https')) {
    throw 'RemoteApiUrl deve essere un URL HTTP o HTTPS assoluto.'
}
Wait-DriveAuraHealth -BaseUrl $RemoteApiUrl -ExpectedService 'remote-php' -TimeoutSeconds 10

Assert-DriveAuraPortAvailable -Port ([int]$state.djangoPort) -Label 'Porta Django'
Assert-DriveAuraPortAvailable -Port ([int]$state.tomcatPort) -Label 'Porta Tomcat'
Assert-DriveAuraPortAvailable -Port ([int]$state.tomcatShutdownPort) -Label 'Porta arresto Tomcat'

$runtimeRoot = [string]$state.installRoot
$pidPath = Join-Path $runtimeRoot 'processes.json'
if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
    throw "Esiste gia un registro processi: eseguire Stop-DriveAura.ps1 -StatePath `"$StatePath`"."
}
$logRoot = Join-Path $runtimeRoot 'logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$tomcatWrapper = Join-Path $runtimeRoot 'run-tomcat.bat'
@(
    '@echo off',
    'call "%CATALINA_HOME%\bin\catalina.bat" run'
) | Set-Content -LiteralPath $tomcatWrapper -Encoding ASCII

$djangoEnvironment = @{
    POSTGRES_DB = [string]$state.postgresDatabase
    POSTGRES_USER = [string]$state.postgresUser
    POSTGRES_PASSWORD = $env:POSTGRES_PASSWORD
    POSTGRES_HOST = [string]$state.postgresHost
    POSTGRES_PORT = [string]$state.postgresPort
    LOCAL_API_SECRET = $env:LOCAL_API_SECRET
    DJANGO_SECRET_KEY = $env:DJANGO_SECRET_KEY
}
$tomcatEnvironment = @{
    JAVA_HOME = [string]$state.javaHome
    JRE_HOME = [string]$state.javaHome
    CATALINA_HOME = [string]$state.tomcatHome
    CATALINA_BASE = [string]$state.tomcatBase
    REMOTE_API_URL = $RemoteApiUrl.TrimEnd('/')
    LOCAL_API_URL = ("http://127.0.0.1:{0}" -f $state.djangoPort)
    REMOTE_API_SECRET = $env:REMOTE_API_SECRET
    LOCAL_API_SECRET = $env:LOCAL_API_SECRET
    BRIDGE_API_SECRET = $env:BRIDGE_API_SECRET
    BRIDGE_BATCH_SIZE = "$BatchSize"
    BRIDGE_CONNECT_TIMEOUT_MS = '3000'
    BRIDGE_READ_TIMEOUT_MS = '10000'
    BRIDGE_MAX_RETRIES = "$MaxRetries"
    BRIDGE_RETRY_DELAY_MS = '100'
}
$djangoProcess = $null
$tomcatProcess = $null
try {
    $djangoPrevious = Set-DriveAuraProcessEnvironment -Values $djangoEnvironment
    try {
        $djangoProcess = Start-Process `
            -FilePath ([string]$state.venvPython) `
            -ArgumentList @(
                'manage.py',
                'runserver',
                ("127.0.0.1:{0}" -f $state.djangoPort),
                '--noreload'
            ) `
            -WorkingDirectory ([string]$state.djangoRoot) `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logRoot 'django.out.log') `
            -RedirectStandardError (Join-Path $logRoot 'django.err.log') `
            -PassThru
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $djangoPrevious
    }

    $processState = [pscustomobject]@{
        djangoPid = $djangoProcess.Id
        tomcatLauncherPid = -1
        djangoMarker = [string]$state.installRoot
        tomcatMarker = [string]$state.installRoot
        startedAt = [DateTime]::UtcNow.ToString('o')
    }
    Save-DriveAuraState -State $processState -Path $pidPath

    $tomcatPrevious = Set-DriveAuraProcessEnvironment -Values $tomcatEnvironment
    try {
        $tomcatProcess = Start-Process `
            -FilePath $env:ComSpec `
            -ArgumentList @('/d', '/c', ('"{0}"' -f $tomcatWrapper)) `
            -WorkingDirectory ([string]$state.tomcatBase) `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $logRoot 'tomcat.out.log') `
            -RedirectStandardError (Join-Path $logRoot 'tomcat.err.log') `
            -PassThru
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $tomcatPrevious
    }
    $processState.tomcatLauncherPid = $tomcatProcess.Id
    Save-DriveAuraState -State $processState -Path $pidPath

    Wait-DriveAuraHealth -BaseUrl ("http://127.0.0.1:{0}" -f $state.djangoPort) `
        -ExpectedService 'local-django' -TimeoutSeconds 30
    Wait-DriveAuraHealth -BaseUrl ("http://127.0.0.1:{0}" -f $state.tomcatPort) `
        -ExpectedService 'bridge-servlet' -TimeoutSeconds 30
} catch {
    try {
        if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
            & (Join-Path $PSScriptRoot 'Stop-DriveAura.ps1') -StatePath $StatePath
        } elseif ($null -ne $djangoProcess) {
            $runningDjango = Get-Process -Id $djangoProcess.Id -ErrorAction SilentlyContinue
            if ($null -ne $runningDjango) {
                $commandLine = Get-DriveAuraProcessCommandLine -ProcessId $djangoProcess.Id
                if ([string]::IsNullOrWhiteSpace($commandLine) -or
                    $commandLine.IndexOf(
                        [string]$state.installRoot,
                        [StringComparison]::OrdinalIgnoreCase
                    ) -lt 0) {
                    throw "Rifiutato arresto PID $($djangoProcess.Id): Django non riconosciuto."
                }
                Stop-Process -Id $djangoProcess.Id -Force
            }
        }
    } catch {
        Write-Warning 'Pulizia automatica incompleta; controllare i PID nel registro processi.'
    }
    throw
}

Write-Host ("PASS: Django e servlet pronti; PID {0}/{1}." -f
    $djangoProcess.Id, $tomcatProcess.Id)
