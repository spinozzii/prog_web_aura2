[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$StatePath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'DriveAura.Common.psm1') -Force

$state = Get-DriveAuraState -Path $StatePath
$pidPath = Join-Path ([string]$state.installRoot) 'processes.json'
if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
    Write-Host 'PASS: nessun processo registrato da arrestare.'
    return
}
$processState = Get-DriveAuraState -Path $pidPath

$tomcatEnvironment = @{
    JAVA_HOME = [string]$state.javaHome
    JRE_HOME = [string]$state.javaHome
    CATALINA_HOME = [string]$state.tomcatHome
    CATALINA_BASE = [string]$state.tomcatBase
}
$tomcatLauncherId = [int]$processState.tomcatLauncherPid
if ($tomcatLauncherId -gt 0) {
    $previous = Set-DriveAuraProcessEnvironment -Values $tomcatEnvironment
    try {
        $stopResult = Invoke-DriveAuraExternal `
            -FilePath (Join-Path ([string]$state.tomcatHome) 'bin\catalina.bat') `
            -Arguments @('stop') -AllowFailure
        if ($stopResult.ExitCode -ne 0) {
            Write-Warning 'Arresto Tomcat non confermato dal comando catalina.'
        }
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $previous
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds(12)
while ([DateTime]::UtcNow -lt $deadline) {
    $tomcatLauncher = Get-Process -Id ([int]$processState.tomcatLauncherPid) `
        -ErrorAction SilentlyContinue
    $tomcatChildren = @(
        Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
                ([string]$_.CommandLine).IndexOf(
                    [string]$state.tomcatBase,
                    [StringComparison]::OrdinalIgnoreCase
                ) -ge 0
            }
    )
    if ($null -eq $tomcatLauncher -and $tomcatChildren.Count -eq 0) {
        break
    }
    Start-Sleep -Milliseconds 250
}

foreach ($entry in @(
        [pscustomobject]@{
            Id = [int]$processState.djangoPid
            Marker = [string]$processState.djangoMarker
            Label = 'Django'
        },
        [pscustomobject]@{
            Id = [int]$processState.tomcatLauncherPid
            Marker = [string]$processState.tomcatMarker
            Label = 'Tomcat'
        }
    )) {
    if ($entry.Id -le 0) {
        continue
    }
    $process = Get-Process -Id $entry.Id -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        continue
    }
    $commandLine = Get-DriveAuraProcessCommandLine -ProcessId $entry.Id
    if ([string]::IsNullOrWhiteSpace($commandLine) -or
        $commandLine.IndexOf($entry.Marker, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw ("Rifiutato arresto PID {0}: command line non riconducibile a {1}." -f
            $entry.Id, $entry.Label)
    }
    Stop-Process -Id $entry.Id -Force
}

$remainingTomcat = @(
    Get-CimInstance -ClassName Win32_Process -ErrorAction Stop |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.CommandLine) -and
            ([string]$_.CommandLine).IndexOf(
                [string]$state.tomcatBase,
                [StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        }
)
foreach ($process in $remainingTomcat) {
    $commandLine = [string]$process.CommandLine
    if ($commandLine.IndexOf(
            [string]$state.tomcatBase,
            [StringComparison]::OrdinalIgnoreCase
        ) -lt 0) {
        throw "Rifiutato arresto PID $($process.ProcessId): command line Tomcat non riconosciuta."
    }
    Stop-Process -Id ([int]$process.ProcessId) -Force
}

Start-Sleep -Milliseconds 500
Assert-DriveAuraPortAvailable -Port ([int]$state.djangoPort) -Label 'Porta Django'
Assert-DriveAuraPortAvailable -Port ([int]$state.tomcatPort) -Label 'Porta Tomcat'
Assert-DriveAuraPortAvailable -Port ([int]$state.tomcatShutdownPort) -Label 'Porta arresto Tomcat'

Remove-Item -LiteralPath $pidPath -Force
Write-Host 'PASS: processi Drive Aura arrestati.'
