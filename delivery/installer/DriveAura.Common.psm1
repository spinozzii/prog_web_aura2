Set-StrictMode -Version 2.0

function Write-DriveAuraStep {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host ("[Drive Aura] {0}" -f $Message)
}

function Resolve-DriveAuraExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Label non trovato. Indicare il percorso esplicito."
    }
    if (Test-Path -LiteralPath $Value -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Value).Path
    }
    $command = Get-Command $Value -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        throw "$Label non trovato: $Value"
    }
    return $command.Source
}

function Invoke-DriveAuraExternal {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 represents native stderr as ErrorRecord objects.
        # Capture them as ordinary command output and decide solely from the exit code.
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($null -eq $exitCode) {
        $exitCode = 0
    }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw ("Comando non riuscito ({0}): {1}" -f $exitCode, ($output -join [Environment]::NewLine))
    }
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output = ($output -join [Environment]::NewLine)
    }
}

function Get-DriveAuraPythonRuntime {
    param([string]$PythonPath)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PythonPath)) {
        $candidates += [pscustomobject]@{ Value = $PythonPath; Prefix = @() }
    } elseif (-not [string]::IsNullOrWhiteSpace($env:DRIVE_AURA_PYTHON)) {
        $candidates += [pscustomobject]@{ Value = $env:DRIVE_AURA_PYTHON; Prefix = @() }
    } else {
        $candidates += [pscustomobject]@{ Value = 'py'; Prefix = @('-3.12') }
        $candidates += [pscustomobject]@{ Value = 'python'; Prefix = @() }
    }

    $errors = @()
    foreach ($candidate in $candidates) {
        try {
            $executable = Resolve-DriveAuraExecutable -Value $candidate.Value -Label 'Python 3.12'
            $prefix = @($candidate.Prefix)
            if ([IO.Path]::GetFileNameWithoutExtension($executable) -ieq 'py' -and $prefix.Count -eq 0) {
                $prefix = @('-3.12')
            }
            $probe = Invoke-DriveAuraExternal -FilePath $executable -Arguments (
                $prefix + @(
                    '-c',
                    'import struct,sys; print(chr(46).join(map(str,sys.version_info[:3]))+chr(124)+str(struct.calcsize(chr(80))*8))'
                )
            )
            $match = [regex]::Match($probe.Output, '(?m)^(3\.\d+\.\d+)\|(32|64)\s*$')
            if (-not $match.Success) {
                throw 'versione non interpretabile'
            }
            $version = [version]$match.Groups[1].Value
            if ($version.Major -ne 3 -or $version.Minor -ne 12) {
                throw ("versione {0} incompatibile; e richiesto Python 3.12 x64" -f $version)
            }
            if ($match.Groups[2].Value -ne '64') {
                throw 'architettura a 32 bit incompatibile; e richiesto Python 3.12 x64'
            }
            $modules = Invoke-DriveAuraExternal -FilePath $executable -Arguments (
                $prefix + @('-c', 'import ensurepip,venv')
            ) -AllowFailure
            if ($modules.ExitCode -ne 0) {
                throw 'il runtime non include venv/ensurepip; installare la distribuzione completa di Python 3.12'
            }
            return [pscustomobject]@{
                Path = $executable
                PrefixArguments = @($prefix)
                Version = $version.ToString()
                Architecture = 'x64'
            }
        } catch {
            $errors += $_.Exception.Message
        }
    }
    throw ("Python 3.12 x64 compatibile non trovato. {0}" -f ($errors -join ' | '))
}

function Get-DriveAuraJavaRuntime {
    param([string]$JavaHome)

    if (-not [string]::IsNullOrWhiteSpace($JavaHome)) {
        $javaPath = Join-Path $JavaHome 'bin\java.exe'
    } elseif (-not [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
        $javaPath = Join-Path $env:JAVA_HOME 'bin\java.exe'
    } else {
        $javaPath = 'java'
    }
    $java = Resolve-DriveAuraExecutable -Value $javaPath -Label 'Java'
    $probe = Invoke-DriveAuraExternal -FilePath $java -Arguments @(
        '-XshowSettings:properties',
        '-version'
    )
    $versionMatch = [regex]::Match($probe.Output, '(?m)^\s*java\.version\s*=\s*([^\s]+)\s*$')
    $homeMatch = [regex]::Match($probe.Output, '(?m)^\s*java\.home\s*=\s*(.+?)\s*$')
    if (-not $versionMatch.Success -or -not $homeMatch.Success) {
        throw 'Versione o directory Java non riconosciuta.'
    }
    $versionText = $versionMatch.Groups[1].Value
    if ($versionText -match '^1\.(\d+)') {
        $major = [int]$Matches[1]
    } elseif ($versionText -match '^(\d+)') {
        $major = [int]$Matches[1]
    } else {
        throw "Versione Java non riconosciuta: $versionText"
    }
    if ($major -lt 8) {
        throw "Java $versionText incompatibile; e richiesto Java 8 o successivo."
    }
    $home = $homeMatch.Groups[1].Value.Trim()
    if (-not (Test-Path -LiteralPath $home -PathType Container)) {
        throw "Directory Java non valida: $home"
    }
    return [pscustomobject]@{
        Path = $java
        Home = (Resolve-Path -LiteralPath $home).Path
        Version = $versionText
        Major = $major
    }
}

function Assert-DriveAuraJavaTomcatCompatibility {
    param(
        [Parameter(Mandatory = $true)][int]$JavaMajor,
        [Parameter(Mandatory = $true)][int]$TomcatMajor
    )

    if ($TomcatMajor -eq 9 -and $JavaMajor -lt 8) {
        throw 'Tomcat 9 richiede Java 8 o successivo.'
    }
    if ($TomcatMajor -eq 11 -and $JavaMajor -lt 17) {
        throw 'Tomcat 11 richiede Java 17 o successivo.'
    }
    if ($TomcatMajor -ne 9 -and $TomcatMajor -ne 11) {
        throw "Tomcat $TomcatMajor non supportato: usare Tomcat 9 oppure Tomcat 11."
    }
}

function Get-DriveAuraTomcatRuntime {
    param(
        [string]$TomcatHome,
        [Parameter(Mandatory = $true)][psobject]$JavaRuntime
    )

    if ([string]::IsNullOrWhiteSpace($TomcatHome)) {
        $TomcatHome = $env:CATALINA_HOME
    }
    if ([string]::IsNullOrWhiteSpace($TomcatHome) -or
        -not (Test-Path -LiteralPath $TomcatHome -PathType Container)) {
        throw 'Tomcat non trovato. Indicare -TomcatHome oppure CATALINA_HOME.'
    }
    $home = (Resolve-Path -LiteralPath $TomcatHome).Path
    foreach ($relative in @('bin\catalina.bat', 'bin\version.bat', 'lib\catalina.jar', 'conf\server.xml')) {
        if (-not (Test-Path -LiteralPath (Join-Path $home $relative) -PathType Leaf)) {
            throw "Tomcat non riconosciuto: manca $relative."
        }
    }

    $oldJavaHome = $env:JAVA_HOME
    $oldJreHome = $env:JRE_HOME
    $oldCatalinaHome = $env:CATALINA_HOME
    try {
        $env:JAVA_HOME = $JavaRuntime.Home
        $env:JRE_HOME = $JavaRuntime.Home
        $env:CATALINA_HOME = $home
        $probe = Invoke-DriveAuraExternal -FilePath (Join-Path $home 'bin\version.bat')
    } finally {
        $env:JAVA_HOME = $oldJavaHome
        $env:JRE_HOME = $oldJreHome
        $env:CATALINA_HOME = $oldCatalinaHome
    }
    $match = [regex]::Match($probe.Output, 'Server version:\s*Apache Tomcat/(\d+)\.([0-9.]+)')
    if (-not $match.Success) {
        throw 'Versione Tomcat non riconosciuta dal comando bin\version.bat.'
    }
    $major = [int]$match.Groups[1].Value
    Assert-DriveAuraJavaTomcatCompatibility -JavaMajor $JavaRuntime.Major -TomcatMajor $major
    return [pscustomobject]@{
        Home = $home
        Version = ("{0}.{1}" -f $match.Groups[1].Value, $match.Groups[2].Value)
        Major = $major
    }
}

function Assert-DriveAuraPostgresVersionCompatibility {
    param([Parameter(Mandatory = $true)][int]$Major)
    if ($Major -lt 14 -or $Major -gt 18) {
        throw "PostgreSQL $Major incompatibile; sono ammesse le versioni da 14 a 18."
    }
}

function Get-DriveAuraPostgresRuntime {
    param([string]$PostgresBin)

    if ([string]::IsNullOrWhiteSpace($PostgresBin)) {
        $PostgresBin = $env:POSTGRES_BIN
    }
    if ([string]::IsNullOrWhiteSpace($PostgresBin)) {
        $psql = Get-Command 'psql.exe' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $psql) {
            $PostgresBin = Split-Path -Parent $psql.Source
        }
    }
    if ([string]::IsNullOrWhiteSpace($PostgresBin) -or
        -not (Test-Path -LiteralPath $PostgresBin -PathType Container)) {
        throw 'PostgreSQL non trovato. Indicare -PostgresBin oppure POSTGRES_BIN.'
    }
    $bin = (Resolve-Path -LiteralPath $PostgresBin).Path
    foreach ($name in @('psql.exe', 'pg_isready.exe', 'createdb.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $bin $name) -PathType Leaf)) {
            throw "PostgreSQL non riconosciuto: manca $name."
        }
    }
    $probe = Invoke-DriveAuraExternal -FilePath (Join-Path $bin 'psql.exe') -Arguments @('--version')
    $match = [regex]::Match($probe.Output, 'PostgreSQL\)\s+(\d+)(?:\.([0-9]+))?')
    if (-not $match.Success) {
        throw 'Versione PostgreSQL non riconosciuta.'
    }
    $major = [int]$match.Groups[1].Value
    Assert-DriveAuraPostgresVersionCompatibility -Major $major
    return [pscustomobject]@{
        Bin = $bin
        Version = if ($match.Groups[2].Success) {
            "$major.$($match.Groups[2].Value)"
        } else {
            "$major"
        }
        Major = $major
    }
}

function Assert-DriveAuraIdentifier {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_]{0,62}$') {
        throw "$Label non valido. Usare soltanto lettere, numeri e underscore."
    }
}

function Assert-DriveAuraSecrets {
    param([string[]]$Names = @(
        'POSTGRES_PASSWORD',
        'DJANGO_SECRET_KEY',
        'LOCAL_API_SECRET',
        'REMOTE_API_SECRET',
        'BRIDGE_API_SECRET'
    ))

    foreach ($name in $Names) {
        $value = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Segreto mancante: impostare `$env:$name nella sessione corrente."
        }
        if ($value.Length -lt 12) {
            throw "Segreto $name troppo corto: usare almeno 12 caratteri."
        }
    }
}

function Assert-DriveAuraPortAvailable {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [string]$Label = 'Porta'
    )
    if ($Port -lt 1024 -or $Port -gt 65535) {
        throw "$Label non valida: $Port."
    }
    $listener = $null
    try {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
        $listener.Start()
    } catch {
        throw "$Label $Port occupata. Scegliere una porta libera senza terminare processi estranei."
    } finally {
        if ($null -ne $listener) {
            $listener.Stop()
        }
    }
}

function Wait-DriveAuraHealth {
    param(
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$ExpectedService,
        [int]$TimeoutSeconds = 30
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $lastError = $null
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $response = Invoke-RestMethod -Method Get -Uri ($BaseUrl.TrimEnd('/') + '/health') -TimeoutSec 3
            if ($response.apiVersion -eq '1.0' -and
                $response.service -eq $ExpectedService -and
                $response.status -eq 'ok') {
                return
            }
            $lastError = 'contratto inatteso'
        } catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Milliseconds 250
    }
    throw "Readiness $ExpectedService non raggiunta entro $TimeoutSeconds secondi: $lastError"
}

function Test-DriveAuraWheelhouse {
    param([Parameter(Mandatory = $true)][string]$Wheelhouse)

    $root = (Resolve-Path -LiteralPath $Wheelhouse -ErrorAction Stop).Path
    $checksumPath = Join-Path $root 'SHA256SUMS.txt'
    $requirementsPath = Join-Path $root 'requirements-offline.txt'
    if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $requirementsPath -PathType Leaf)) {
        throw 'Wheelhouse incompleta: mancano SHA256SUMS.txt o requirements-offline.txt.'
    }
    $expected = @{}
    foreach ($line in Get-Content -LiteralPath $checksumPath -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -notmatch '^([0-9a-f]{64})  ([A-Za-z0-9_.+-]+\.whl)$') {
            throw "Riga checksum wheel non valida: $line"
        }
        $key = $Matches[2].ToLowerInvariant()
        if ($expected.ContainsKey($key)) {
            throw "Wheel duplicata nel manifest: $($Matches[2])"
        }
        $expected[$key] = $Matches[1]
    }
    $actual = @(Get-ChildItem -LiteralPath $root -File -Filter '*.whl')
    if ($actual.Count -eq 0 -or $actual.Count -ne $expected.Count) {
        throw 'Numero di wheel diverso dal manifest.'
    }
    foreach ($file in $actual) {
        $key = $file.Name.ToLowerInvariant()
        if (-not $expected.ContainsKey($key)) {
            throw "Wheel non dichiarata: $($file.Name)"
        }
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        if ($hash -ne $expected[$key]) {
            throw "Checksum wheel non valido: $($file.Name)"
        }
    }
    $requiredNames = @('django-', 'psycopg-', 'psycopg_binary-', 'asgiref-', 'sqlparse-', 'tzdata-')
    foreach ($prefix in $requiredNames) {
        if (-not @($actual | Where-Object { $_.Name.ToLowerInvariant().StartsWith($prefix) })) {
            throw "Wheel obbligatoria mancante: $prefix"
        }
    }
    return [pscustomobject]@{
        Root = $root
        Requirements = $requirementsPath
        Count = $actual.Count
    }
}

function Invoke-DriveAuraPostgresExternal {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_PASSWORD)) {
        throw 'Segreto mancante: impostare $env:POSTGRES_PASSWORD.'
    }
    $previousPassword = $env:PGPASSWORD
    try {
        $env:PGPASSWORD = $env:POSTGRES_PASSWORD
        return Invoke-DriveAuraExternal -FilePath $FilePath -Arguments $Arguments `
            -AllowFailure:$AllowFailure
    } finally {
        $env:PGPASSWORD = $previousPassword
    }
}

function Test-DriveAuraPostgresReady {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [string]$Database = 'postgres'
    )

    Assert-DriveAuraIdentifier -Value $User -Label 'Utente PostgreSQL'
    Assert-DriveAuraIdentifier -Value $Database -Label 'Database PostgreSQL'
    if ([string]::IsNullOrWhiteSpace($env:POSTGRES_PASSWORD)) {
        throw 'Segreto mancante: impostare $env:POSTGRES_PASSWORD.'
    }
    $ready = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'pg_isready.exe') `
        -Arguments @('--host', $HostName, '--port', "$Port", '--username', $User, '--dbname', $Database) `
        -AllowFailure
    if ($ready.ExitCode -ne 0) {
        throw "PostgreSQL non raggiungibile su ${HostName}:$Port. Verificare servizio, porta e firewall."
    }
    $query = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', $Database,
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', 'SELECT 1'
        ) -AllowFailure
    if ($query.ExitCode -ne 0 -or $query.Output.Trim() -ne '1') {
        throw 'Autenticazione PostgreSQL fallita. Verificare utente, password e pg_hba.conf.'
    }
    $serverVersion = Invoke-DriveAuraPostgresExternal `
        -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', $Database,
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', 'SHOW server_version_num'
        ) -AllowFailure
    $serverVersionNumber = 0
    if ($serverVersion.ExitCode -ne 0 -or
        -not [int]::TryParse($serverVersion.Output.Trim(), [ref]$serverVersionNumber)) {
        throw 'Versione del server PostgreSQL non interpretabile.'
    }
    $serverMajor = [int][Math]::Floor($serverVersionNumber / 10000)
    Assert-DriveAuraPostgresVersionCompatibility -Major $serverMajor
}

function Test-DriveAuraDatabaseExists {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Database
    )

    Assert-DriveAuraIdentifier -Value $Database -Label 'Database PostgreSQL'
    $sql = "SELECT 1 FROM pg_database WHERE datname = '$Database'"
    $result = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', 'postgres',
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', $sql
        )
    return $result.Output.Trim() -eq '1'
}

function New-DriveAuraDatabase {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Database
    )

    Assert-DriveAuraIdentifier -Value $Database -Label 'Database PostgreSQL'
    Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'createdb.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--no-password',
            '--encoding', 'UTF8',
            '--template', 'template0',
            $Database
        ) | Out-Null
}

function Get-DriveAuraDomainRowCount {
    param(
        [Parameter(Mandatory = $true)][psobject]$PostgresRuntime,
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$Database
    )

    $sql = @'
SELECT
  (SELECT COUNT(*) FROM cittadino) +
  (SELECT COUNT(*) FROM patologia) +
  (SELECT COUNT(*) FROM patologia_cronica) +
  (SELECT COUNT(*) FROM patologia_mortale) +
  (SELECT COUNT(*) FROM ospedale) +
  (SELECT COUNT(*) FROM ricovero) +
  (SELECT COUNT(*) FROM patologia_ricovero) +
  (SELECT COUNT(*) FROM progressivo_ricovero);
'@
    $result = Invoke-DriveAuraPostgresExternal -FilePath (Join-Path $PostgresRuntime.Bin 'psql.exe') `
        -Arguments @(
            '--host', $HostName,
            '--port', "$Port",
            '--username', $User,
            '--dbname', $Database,
            '--no-password',
            '--tuples-only',
            '--no-align',
            '--command', $sql
        )
    $value = 0L
    if (-not [long]::TryParse($result.Output.Trim(), [ref]$value)) {
        throw 'Conteggio delle tabelle PostgreSQL non interpretabile.'
    }
    return $value
}

function Save-DriveAuraState {
    param(
        [Parameter(Mandatory = $true)][psobject]$State,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-DriveAuraState {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configurazione installata non trovata: $Path"
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
}

function Set-DriveAuraProcessEnvironment {
    param([Parameter(Mandatory = $true)][hashtable]$Values)
    $previous = @{}
    foreach ($name in $Values.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        [Environment]::SetEnvironmentVariable($name, [string]$Values[$name], 'Process')
    }
    return $previous
}

function Restore-DriveAuraProcessEnvironment {
    param([Parameter(Mandatory = $true)][hashtable]$Previous)
    foreach ($name in $Previous.Keys) {
        [Environment]::SetEnvironmentVariable($name, $Previous[$name], 'Process')
    }
}

function Get-DriveAuraProcessCommandLine {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    try {
        $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" `
            -ErrorAction Stop
        return [string]$process.CommandLine
    } catch {
        return ''
    }
}

Export-ModuleMember -Function @(
    'Write-DriveAuraStep',
    'Resolve-DriveAuraExecutable',
    'Invoke-DriveAuraExternal',
    'Get-DriveAuraPythonRuntime',
    'Get-DriveAuraJavaRuntime',
    'Assert-DriveAuraJavaTomcatCompatibility',
    'Get-DriveAuraTomcatRuntime',
    'Get-DriveAuraPostgresRuntime',
    'Assert-DriveAuraPostgresVersionCompatibility',
    'Assert-DriveAuraIdentifier',
    'Assert-DriveAuraSecrets',
    'Assert-DriveAuraPortAvailable',
    'Wait-DriveAuraHealth',
    'Test-DriveAuraWheelhouse',
    'Test-DriveAuraPostgresReady',
    'Test-DriveAuraDatabaseExists',
    'New-DriveAuraDatabase',
    'Get-DriveAuraDomainRowCount',
    'Save-DriveAuraState',
    'Get-DriveAuraState',
    'Set-DriveAuraProcessEnvironment',
    'Restore-DriveAuraProcessEnvironment',
    'Get-DriveAuraProcessCommandLine'
)
