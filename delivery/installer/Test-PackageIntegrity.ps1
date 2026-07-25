[CmdletBinding()]
param(
    [string]$PackageRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$manifestName = 'PACKAGE-MANIFEST.json'
$checksumsName = 'SHA256SUMS.txt'
$expectedPackageName = 'drive-aura-51-offline'
$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Get-CanonicalDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Directory del pacchetto non trovata: $Path"
    }
    return [System.IO.Path]::GetFullPath(
        (Get-Item -Force -LiteralPath $Path).FullName
    ).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
}

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $prefix = $Root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith(
            $prefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Percorso fuori dal pacchetto: $fullPath"
    }
    return $fullPath.Substring($prefix.Length).Replace('\', '/')
}

function Assert-PortableRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if (
        [string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('\') -or
        $RelativePath.Contains(':') -or
        $RelativePath.Contains("`0") -or
        $RelativePath.Contains("`r") -or
        $RelativePath.Contains("`n") -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.EndsWith('/') -or
        $RelativePath.Contains('//')
    ) {
        throw "Percorso non portabile nel manifest: $RelativePath"
    }

    foreach ($segment in $RelativePath.Split('/')) {
        if ($segment -eq '' -or $segment -eq '.' -or $segment -eq '..') {
            throw "Segmento non valido nel manifest: $RelativePath"
        }
    }
}

function Assert-PathIsAllowed {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    Assert-PortableRelativePath -RelativePath $RelativePath
    $segments = $RelativePath.Split('/')
    $forbiddenDirectories = @(
        '.git',
        'target',
        'tmp',
        'logs',
        'runtime',
        '.venv',
        'cache',
        '.cache',
        '__pycache__',
        '.pytest_cache',
        '.mypy_cache',
        '.ruff_cache',
        '.idea',
        '.vscode',
        '.vs',
        '.settings',
        'node_modules'
    )

    foreach ($segment in $segments) {
        $lower = $segment.ToLowerInvariant()
        if ($forbiddenDirectories -contains $lower) {
            throw "Percorso vietato nel pacchetto: $RelativePath"
        }
        if (
            ($lower -eq '.env' -or $lower.StartsWith('.env.')) -and
            $lower -ne '.env.example'
        ) {
            throw "Configurazione locale vietata nel pacchetto: $RelativePath"
        }
        if (
            $lower.EndsWith('.log') -or
            $lower.EndsWith('.pyc') -or
            $lower.EndsWith('.pyo') -or
            $lower.EndsWith('.class') -or
            $lower.EndsWith('.tmp') -or
            $lower.EndsWith('.temp') -or
            $lower.EndsWith('.bak') -or
            $lower.EndsWith('.orig') -or
            $lower.EndsWith('.rej') -or
            $lower.EndsWith('.swp') -or
            $lower.EndsWith('.swo') -or
            $lower.EndsWith('~') -or
            $lower.EndsWith('.iml') -or
            $lower.EndsWith('.ipr') -or
            $lower.EndsWith('.iws') -or
            $lower.EndsWith('.code-workspace') -or
            $lower.EndsWith('.suo') -or
            $lower.EndsWith('.user') -or
            $lower -eq '.project' -or
            $lower -eq '.classpath' -or
            $lower -eq '.settings' -or
            $lower -eq '.ds_store' -or
            $lower -eq 'desktop.ini' -or
            $lower -eq 'thumbs.db'
        ) {
            throw "File vietato nel pacchetto: $RelativePath"
        }
    }
}

function Get-SafePackageEntries {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $rootItem = Get-Item -Force -LiteralPath $Root
    if (
        ($rootItem.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw 'La radice del pacchetto non puo essere un reparse point.'
    }

    $stack = New-Object System.Collections.Stack
    $stack.Push($rootItem)
    $entries = New-Object System.Collections.ArrayList
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        foreach ($item in Get-ChildItem -Force -LiteralPath $directory.FullName) {
            $relative = Get-NormalizedRelativePath `
                -Root $Root `
                -Path $item.FullName
            Assert-PathIsAllowed -RelativePath $relative
            if (
                ($item.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0
            ) {
                throw "Reparse point vietato nel pacchetto: $relative"
            }

            [void]$entries.Add([pscustomobject]@{
                RelativePath = $relative
                FullName = $item.FullName
                IsDirectory = [bool]$item.PSIsContainer
            })
            if ($item.PSIsContainer) {
                $stack.Push($item)
            }
        }
    }
    return @($entries.ToArray())
}

function New-CaseInsensitivePathMap {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [scriptblock]$PathSelector,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $map = @{}
    foreach ($item in $Items) {
        $path = [string](& $PathSelector $item)
        if ($map.ContainsKey($path)) {
            throw "Percorso duplicato senza distinzione maiuscole/minuscole ($Label): $path"
        }
        $map[$path] = $item
    }
    return $map
}

function Get-LowerSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).
        Hash.ToLowerInvariant()
}

function Add-ExpectedDirectories {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DirectoryMap,

        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $segments = $FilePath.Split('/')
    for ($index = 1; $index -lt $segments.Length; $index++) {
        $directory = [string]::Join(
            '/',
            $segments[0..($index - 1)]
        )
        $DirectoryMap[$directory] = $true
    }
}

function Assert-RequiredFile {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ActualFiles,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if (-not $ActualFiles.ContainsKey($RelativePath)) {
        throw "File obbligatorio mancante: $RelativePath"
    }
}

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Parent $PSScriptRoot
}
$resolvedRoot = Get-CanonicalDirectory -Path $PackageRoot

$entries = @(Get-SafePackageEntries -Root $resolvedRoot)
$entryMap = New-CaseInsensitivePathMap `
    -Items $entries `
    -PathSelector { param($item) $item.RelativePath } `
    -Label 'filesystem'
$actualFiles = @($entries | Where-Object { -not $_.IsDirectory })
$actualDirectories = @($entries | Where-Object { $_.IsDirectory })
$actualFileMap = New-CaseInsensitivePathMap `
    -Items $actualFiles `
    -PathSelector { param($item) $item.RelativePath } `
    -Label 'file'
$actualDirectoryMap = New-CaseInsensitivePathMap `
    -Items $actualDirectories `
    -PathSelector { param($item) $item.RelativePath } `
    -Label 'directory'

Assert-RequiredFile -ActualFiles $actualFileMap -RelativePath $manifestName
Assert-RequiredFile -ActualFiles $actualFileMap -RelativePath $checksumsName

try {
    $manifestText = [System.IO.File]::ReadAllText(
        $actualFileMap[$manifestName].FullName,
        $utf8Strict
    )
    $manifest = $manifestText | ConvertFrom-Json
}
catch {
    throw "Manifest JSON non leggibile: $($_.Exception.Message)"
}
if (
    $null -eq $manifest -or
    [int]$manifest.formatVersion -ne 1 -or
    [string]$manifest.packageRoot -ne $expectedPackageName -or
    $null -eq $manifest.files
) {
    throw 'PACKAGE-MANIFEST.json non rispetta il formato versione 1.'
}

$manifestFiles = @($manifest.files)
if ($manifestFiles.Count -eq 0) {
    throw 'Il manifest non contiene file.'
}
$manifestMap = @{}
foreach ($record in $manifestFiles) {
    $relative = [string]$record.path
    Assert-PathIsAllowed -RelativePath $relative
    if ($relative -eq $manifestName -or $relative -eq $checksumsName) {
        throw "Il file di controllo non deve elencare se stesso: $relative"
    }
    if ($manifestMap.ContainsKey($relative)) {
        throw "Percorso duplicato nel manifest: $relative"
    }
    if (
        $record.sha256 -isnot [string] -or
        [string]$record.sha256 -notmatch '^[0-9a-f]{64}$' -or
        (
            $record.bytes -isnot [byte] -and
            $record.bytes -isnot [int16] -and
            $record.bytes -isnot [int32] -and
            $record.bytes -isnot [int64]
        ) -or
        [int64]$record.bytes -lt 0
    ) {
        throw "Metadati non validi nel manifest: $relative"
    }
    $manifestMap[$relative] = $record
}

foreach ($relative in $manifestMap.Keys) {
    if (-not $actualFileMap.ContainsKey($relative)) {
        throw "File dichiarato ma mancante: $relative"
    }
}
foreach ($relative in $actualFileMap.Keys) {
    if (
        $relative -ne $manifestName -and
        $relative -ne $checksumsName -and
        -not $manifestMap.ContainsKey($relative)
    ) {
        throw "File extra non dichiarato: $relative"
    }
}

foreach ($relative in $manifestMap.Keys) {
    $record = $manifestMap[$relative]
    $file = Get-Item -Force -LiteralPath $actualFileMap[$relative].FullName
    if ($file.Length -ne [int64]$record.bytes) {
        throw "Hash o dimensione non valida: $relative"
    }
    $actualHash = Get-LowerSha256 -Path $file.FullName
    if ($actualHash -ne [string]$record.sha256) {
        throw "Hash SHA-256 non valido: $relative"
    }
}

$expectedDirectories = @{}
foreach ($relative in $manifestMap.Keys) {
    Add-ExpectedDirectories `
        -DirectoryMap $expectedDirectories `
        -FilePath $relative
}
foreach ($relative in $actualDirectoryMap.Keys) {
    if (-not $expectedDirectories.ContainsKey($relative)) {
        throw "Directory extra non dichiarata: $relative"
    }
}
foreach ($relative in $expectedDirectories.Keys) {
    if (-not $actualDirectoryMap.ContainsKey($relative)) {
        throw "Directory attesa ma mancante: $relative"
    }
}

try {
    $checksumLines = [System.IO.File]::ReadAllLines(
        $actualFileMap[$checksumsName].FullName,
        $utf8Strict
    )
}
catch {
    throw "SHA256SUMS.txt non leggibile: $($_.Exception.Message)"
}
if ($checksumLines.Count -eq 0) {
    throw 'SHA256SUMS.txt e vuoto.'
}

$checksumMap = @{}
foreach ($line in $checksumLines) {
    $match = [regex]::Match($line, '^([0-9a-f]{64})  (.+)$')
    if (-not $match.Success) {
        throw "Riga non valida in SHA256SUMS.txt: $line"
    }
    $relative = $match.Groups[2].Value
    Assert-PathIsAllowed -RelativePath $relative
    if ($relative -eq $checksumsName) {
        throw 'SHA256SUMS.txt non puo contenere il proprio hash.'
    }
    if ($checksumMap.ContainsKey($relative)) {
        throw "Percorso duplicato in SHA256SUMS.txt: $relative"
    }
    $checksumMap[$relative] = $match.Groups[1].Value
}

$expectedChecksumPaths = @{}
foreach ($relative in $manifestMap.Keys) {
    $expectedChecksumPaths[$relative] = $true
}
$expectedChecksumPaths[$manifestName] = $true
foreach ($relative in $expectedChecksumPaths.Keys) {
    if (-not $checksumMap.ContainsKey($relative)) {
        throw "Checksum obbligatorio mancante: $relative"
    }
}
foreach ($relative in $checksumMap.Keys) {
    if (-not $expectedChecksumPaths.ContainsKey($relative)) {
        throw "Checksum extra non previsto: $relative"
    }
    if (-not $actualFileMap.ContainsKey($relative)) {
        throw "Checksum riferito a un file mancante: $relative"
    }
    $actualHash = Get-LowerSha256 `
        -Path $actualFileMap[$relative].FullName
    if ($actualHash -ne [string]$checksumMap[$relative]) {
        throw "Checksum aggregato non valido: $relative"
    }
}

Assert-RequiredFile -ActualFiles $actualFileMap -RelativePath 'README.md'
Assert-RequiredFile -ActualFiles $actualFileMap -RelativePath 'ALTERVISTA.md'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'installer/Test-PackageIntegrity.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'installer/Configure-DriveAura.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'installer/Start-DriveAura.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'installer/Stop-DriveAura.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'installer/Verify-DriveAura.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'installer/DriveAura.Common.psm1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'installer/mock_remote.py'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'config/parameters.example.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'config/secrets.example.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'config/altervista-setenv.example.htaccess'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'database/drive-aura-51-source-v2.zip'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'database/drive-aura-51-source-v2.zip.sha256'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/remote-php/public/index.php'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/remote-php/README.md'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/bridge-servlet/pom.xml'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/bridge-servlet/README.md'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/local-django/manage.py'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/local-django/requirements.txt'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/local-django/README.md'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/shared/entity-schema.json'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/tests/health-contract.json'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'source/tests/run-health-contracts.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'tools/verify-full-migration.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'tools/verify-mass-migration.ps1'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'wheelhouse/requirements-offline.txt'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'wheelhouse/SHA256SUMS.txt'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'artifacts/SHA256SUMS.txt'
Assert-RequiredFile `
    -ActualFiles $actualFileMap `
    -RelativePath 'pdf/manuale-drive-aura-51.pdf'

$warFiles = @($actualFiles | Where-Object {
    $_.RelativePath -match '^artifacts/[^/]+\.war$'
})
if (
    $warFiles.Count -ne 2 -or
    @($warFiles | Where-Object {
        $_.RelativePath -match '(?i)tomcat9[^/]*\.war$'
    }).Count -ne 1 -or
    @($warFiles | Where-Object {
        $_.RelativePath -match '(?i)tomcat11[^/]*\.war$'
    }).Count -ne 1
) {
    throw 'Servono esattamente i WAR Tomcat 9 e Tomcat 11.'
}

$warChecksumLines = [System.IO.File]::ReadAllLines(
    $actualFileMap['artifacts/SHA256SUMS.txt'].FullName,
    $utf8Strict
)
$warChecksumMap = @{}
foreach ($line in $warChecksumLines) {
    $match = [regex]::Match(
        $line,
        '^([0-9a-f]{64})  ([^/\\]+\.war)$'
    )
    if (-not $match.Success) {
        throw "Riga non valida nel checksum WAR: $line"
    }
    $warName = $match.Groups[2].Value
    if ($warChecksumMap.ContainsKey($warName)) {
        throw "WAR duplicato nel checksum dedicato: $warName"
    }
    $warChecksumMap[$warName] = $match.Groups[1].Value
}
foreach ($war in $warFiles) {
    $warName = [System.IO.Path]::GetFileName($war.RelativePath)
    if (-not $warChecksumMap.ContainsKey($warName)) {
        throw "Checksum WAR mancante: $warName"
    }
    if (
        (Get-LowerSha256 -Path $war.FullName) -ne
        [string]$warChecksumMap[$warName]
    ) {
        throw "Checksum WAR non valido: $warName"
    }
}
if ($warChecksumMap.Count -ne $warFiles.Count) {
    throw 'Il checksum WAR contiene riferimenti extra.'
}

$wheels = @($actualFiles | Where-Object {
    $_.RelativePath -match '^wheelhouse/[^/]+\.whl$'
})
if ($wheels.Count -eq 0) {
    throw 'La wheelhouse non contiene pacchetti .whl.'
}

$wheelChecksumLines = [System.IO.File]::ReadAllLines(
    $actualFileMap['wheelhouse/SHA256SUMS.txt'].FullName,
    $utf8Strict
)
$wheelChecksumMap = @{}
foreach ($line in $wheelChecksumLines) {
    $match = [regex]::Match(
        $line,
        '^([0-9a-f]{64})  ([^/\\]+\.whl)$'
    )
    if (-not $match.Success) {
        throw "Riga non valida nel checksum wheelhouse: $line"
    }
    $wheelName = $match.Groups[2].Value
    if ($wheelChecksumMap.ContainsKey($wheelName)) {
        throw "Wheel duplicata nel checksum wheelhouse: $wheelName"
    }
    $wheelChecksumMap[$wheelName] = $match.Groups[1].Value
}
foreach ($wheel in $wheels) {
    $wheelName = [System.IO.Path]::GetFileName($wheel.RelativePath)
    if (-not $wheelChecksumMap.ContainsKey($wheelName)) {
        throw "Checksum wheel mancante: $wheelName"
    }
    if (
        (Get-LowerSha256 -Path $wheel.FullName) -ne
        [string]$wheelChecksumMap[$wheelName]
    ) {
        throw "Checksum wheel non valido: $wheelName"
    }
}
if ($wheelChecksumMap.Count -ne $wheels.Count) {
    throw 'Il checksum wheelhouse contiene riferimenti extra.'
}

$pdfFiles = @($actualFiles | Where-Object {
    $_.RelativePath -match '^pdf/[^/]+\.pdf$'
})
if ($pdfFiles.Count -ne 2) {
    throw 'La cartella pdf deve contenere esattamente due PDF.'
}

$configFiles = @($actualFiles | Where-Object {
    $_.RelativePath.StartsWith(
        'config/',
        [System.StringComparison]::OrdinalIgnoreCase
    )
})
if ($configFiles.Count -eq 0) {
    throw 'Mancano le configurazioni di esempio.'
}
$remoteSourceFiles = @($actualFiles | Where-Object {
    $_.RelativePath -match '^source/remote-php/(public|src|tests)/'
})
$bridgeSourceFiles = @($actualFiles | Where-Object {
    $_.RelativePath -match '^source/bridge-servlet/(core|tomcat9|tomcat11)/src/'
})
$djangoSourceFiles = @($actualFiles | Where-Object {
    $_.RelativePath -match '^source/local-django/health_service/.+\.py$'
})
$djangoMigrations = @($actualFiles | Where-Object {
    $_.RelativePath -match '^source/local-django/health_service/migrations/.+\.py$'
})
$fixtureFiles = @($actualFiles | Where-Object {
    $_.RelativePath -match '^source/tests/fixtures/.+\.json$'
})
if (
    $remoteSourceFiles.Count -eq 0 -or
    $bridgeSourceFiles.Count -eq 0 -or
    $djangoSourceFiles.Count -eq 0 -or
    $djangoMigrations.Count -eq 0 -or
    $fixtureFiles.Count -eq 0
) {
    throw 'Uno o piu alberi sorgente obbligatori sono incompleti.'
}

$dumpRelative = 'database/drive-aura-51-source-v2.zip'
$dumpSidecarRelative = "$dumpRelative.sha256"
$sidecarLines = [System.IO.File]::ReadAllLines(
    $actualFileMap[$dumpSidecarRelative].FullName,
    $utf8Strict
)
if ($sidecarLines.Count -ne 1) {
    throw 'Il sidecar del dump deve contenere una sola riga.'
}
$dumpMatch = [regex]::Match(
    $sidecarLines[0],
    '^([0-9a-f]{64}) \*drive-aura-51-source-v2\.zip$'
)
if (-not $dumpMatch.Success) {
    throw 'Formato del sidecar del dump non valido.'
}
$dumpHash = Get-LowerSha256 -Path $actualFileMap[$dumpRelative].FullName
if ($dumpHash -ne $dumpMatch.Groups[1].Value) {
    throw 'Il checksum dedicato del dump non coincide.'
}

Write-Host "Integrita pacchetto valida: $resolvedRoot"
Write-Host "File payload: $($manifestMap.Count)"
Write-Host "WAR: $($warFiles.Count); wheel: $($wheels.Count); PDF: $($pdfFiles.Count)"
