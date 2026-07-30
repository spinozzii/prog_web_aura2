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
$cleanupErrors = New-Object System.Collections.Generic.List[string]

$tomcatEnvironment = @{
    JAVA_HOME = [string]$state.javaHome
    JRE_HOME = [string]$state.javaHome
    CATALINA_HOME = [string]$state.tomcatHome
    CATALINA_BASE = [string]$state.tomcatBase
}
$tomcatIdentity = $processState.tomcatProcess
$djangoIdentity = $processState.djangoProcess
if ($null -ne $tomcatIdentity -and
    (Test-DriveAuraProcessIdentity -Identity $tomcatIdentity -Label 'Tomcat')) {
    $previous = Set-DriveAuraProcessEnvironment -Values $tomcatEnvironment
    try {
        $stopResult = Invoke-DriveAuraExternal `
            -FilePath (Join-Path ([string]$state.tomcatHome) 'bin\catalina.bat') `
            -Arguments @('stop') -AllowFailure -TimeoutSeconds 8
        if ($stopResult.ExitCode -ne 0) {
            Write-Warning 'Arresto Tomcat non confermato dal comando catalina.'
        }
    } catch {
        $cleanupErrors.Add(("arresto Tomcat: {0}" -f $_.Exception.Message))
    } finally {
        Restore-DriveAuraProcessEnvironment -Previous $previous
    }
}

$deadline = [DateTime]::UtcNow.AddSeconds(12)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($null -eq $tomcatIdentity -or
        -not (Test-DriveAuraProcessIdentity -Identity $tomcatIdentity -Label 'Tomcat')) {
        break
    }
    Start-Sleep -Milliseconds 250
}

foreach ($entry in @(
        [pscustomobject]@{ Identity = $tomcatIdentity; Label = 'Tomcat' },
        [pscustomobject]@{ Identity = $djangoIdentity; Label = 'Django' }
    )) {
    if ($null -eq $entry.Identity) {
        continue
    }
    try {
        Stop-DriveAuraOwnedProcessTree -Identity $entry.Identity `
            -Label $entry.Label -TimeoutSeconds 5
    } catch {
        $cleanupErrors.Add(("{0}: {1}" -f $entry.Label, $_.Exception.Message))
    }
}

Start-Sleep -Milliseconds 500
foreach ($port in @(
        [pscustomobject]@{ Value = [int]$state.djangoPort; Label = 'Porta Django' },
        [pscustomobject]@{ Value = [int]$state.tomcatPort; Label = 'Porta Tomcat' },
        [pscustomobject]@{
            Value = [int]$state.tomcatShutdownPort
            Label = 'Porta arresto Tomcat'
        }
    )) {
    try {
        Assert-DriveAuraPortAvailable -Port $port.Value -Label $port.Label
    } catch {
        $cleanupErrors.Add($_.Exception.Message)
    }
}

if ($cleanupErrors.Count -gt 0) {
    throw ("Pulizia Drive Aura incompleta: {0}" -f ($cleanupErrors -join ' | '))
}
Remove-Item -LiteralPath $pidPath -Force -ErrorAction Stop
Write-Host 'PASS: processi Drive Aura arrestati.'
