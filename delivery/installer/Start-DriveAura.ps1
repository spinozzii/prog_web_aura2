[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StatePath,
    [Parameter(Mandatory = $true)][string]$RemoteApiUrl,
    [ValidateRange(1, 100)][int]$BatchSize = 50,
    [ValidateRange(0, 5)][int]$MaxRetries = 2,
    [ValidateRange(5, 120)][int]$ReadinessTimeoutSeconds = 45
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'DriveAura.Common.psm1') -Force

Repair-DriveAuraPathEnvironment | Out-Null
$state = Get-DriveAuraState -Path $StatePath
Assert-DriveAuraSecrets

Assert-DriveAuraRemoteUrl -Value $RemoteApiUrl | Out-Null
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
$djangoWrapper = Join-Path $runtimeRoot 'run-django.bat'
$djangoOut = Join-Path $logRoot 'django.out.log'
$djangoErr = Join-Path $logRoot 'django.err.log'
$tomcatOut = Join-Path $logRoot 'tomcat.out.log'
$tomcatErr = Join-Path $logRoot 'tomcat.err.log'
@(
    '@echo off',
    ('cd /d "{0}"' -f [string]$state.djangoRoot),
    ('"{0}" manage.py runserver 127.0.0.1:{1} --noreload 1>>"{2}" 2>>"{3}" <NUL' -f
        [string]$state.venvPython, [int]$state.djangoPort, $djangoOut, $djangoErr)
) | Set-Content -LiteralPath $djangoWrapper -Encoding ASCII
@(
    '@echo off',
    ('call "%CATALINA_HOME%\bin\catalina.bat" run 1>>"' +
        $tomcatOut + '" 2>>"' + $tomcatErr + '" <NUL')
) | Set-Content -LiteralPath $tomcatWrapper -Encoding ASCII

$djangoEnvironment = @{
    POSTGRES_DB = [string]$state.postgresDatabase
    POSTGRES_USER = [string]$state.postgresUser
    POSTGRES_PASSWORD = $env:POSTGRES_PASSWORD
    POSTGRES_HOST = [string]$state.postgresHost
    POSTGRES_PORT = [string]$state.postgresPort
    LOCAL_API_SECRET = $env:LOCAL_API_SECRET
    DJANGO_SECRET_KEY = $env:DJANGO_SECRET_KEY
    DJANGO_SETTINGS_MODULE = 'health_service.settings'
    DJANGO_TEST_SQLITE = $null
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
$djangoIdentity = $null
$tomcatIdentity = $null
try {
    $djangoPrevious = Set-DriveAuraProcessEnvironment -Values $djangoEnvironment
    try {
        $djangoIdentity = Start-DriveAuraManagedProcess `
            -WrapperPath $djangoWrapper `
            -WorkingDirectory ([string]$state.djangoRoot)
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $djangoPrevious
    }

    $processState = [pscustomobject]@{
        apiVersion = '1.0'
        djangoProcess = $djangoIdentity
        tomcatProcess = $null
        startedAt = [DateTime]::UtcNow.ToString('o')
    }
    Save-DriveAuraState -State $processState -Path $pidPath

    $tomcatPrevious = Set-DriveAuraProcessEnvironment -Values $tomcatEnvironment
    try {
        $tomcatIdentity = Start-DriveAuraManagedProcess `
            -WrapperPath $tomcatWrapper `
            -WorkingDirectory ([string]$state.tomcatBase)
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $tomcatPrevious
    }
    $processState.tomcatProcess = $tomcatIdentity
    Save-DriveAuraState -State $processState -Path $pidPath

    Wait-DriveAuraHealth -BaseUrl ("http://127.0.0.1:{0}" -f $state.djangoPort) `
        -ExpectedService 'local-django' -TimeoutSeconds $ReadinessTimeoutSeconds `
        -ProcessIdentity $djangoIdentity -ProcessLabel 'Django'
    Wait-DriveAuraHealth -BaseUrl ("http://127.0.0.1:{0}" -f $state.tomcatPort) `
        -ExpectedService 'bridge-servlet' -TimeoutSeconds $ReadinessTimeoutSeconds `
        -ProcessIdentity $tomcatIdentity -ProcessLabel 'Tomcat'
} catch {
    $primaryError = $_
    try {
        if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
            & (Join-Path $PSScriptRoot 'Stop-DriveAura.ps1') -StatePath $StatePath
        } elseif ($null -ne $tomcatIdentity) {
            Stop-DriveAuraOwnedProcessTree -Identity $tomcatIdentity -Label 'Tomcat'
            if ($null -ne $djangoIdentity) {
                Stop-DriveAuraOwnedProcessTree -Identity $djangoIdentity -Label 'Django'
            }
        } elseif ($null -ne $djangoIdentity) {
            Stop-DriveAuraOwnedProcessTree -Identity $djangoIdentity -Label 'Django'
        }
    } catch {
        throw ("Avvio non riuscito: {0} | Pulizia automatica: {1}" -f
            $primaryError.Exception.Message, $_.Exception.Message)
    }
    throw $primaryError
}

Write-Host ("PASS: Django e servlet pronti; PID {0}/{1}." -f
    $djangoIdentity.pid, $tomcatIdentity.pid)
