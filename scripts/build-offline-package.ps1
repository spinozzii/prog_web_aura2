[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$packageName = 'drive-aura-51-offline'
$archiveName = "$packageName.zip"
$projectRoot = [System.IO.Path]::GetFullPath(
    (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)
$repositoryTmp = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'tmp')
)
$workRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $repositoryTmp 'drive-aura-package')
)
$stagingContainer = Join-Path $workRoot 's'
$extractionContainer = Join-Path $workRoot 'x'
$packageRoot = Join-Path $stagingContainer $packageName
$distRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $projectRoot 'dist')
)
$archivePath = Join-Path $distRoot $archiveName
$archiveSidecarPath = "$archivePath.sha256"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$copiedPaths = @{}

function Assert-PathWithin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot,

        [switch]$AllowRoot
    )

    $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $allowedFull = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    if (
        $AllowRoot -and
        $candidateFull.Equals(
            $allowedFull,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        return
    }
    $prefix = $allowedFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidateFull.StartsWith(
            $prefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Percorso fuori dal perimetro consentito: $candidateFull"
    }
}

function Assert-SafeWorkRoot {
    $expected = [System.IO.Path]::GetFullPath(
        (Join-Path $repositoryTmp 'drive-aura-package')
    )
    if (-not $workRoot.Equals(
            $expected,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw 'La directory temporanea non coincide con il percorso fisso previsto.'
    }
    Assert-PathWithin -Candidate $workRoot -AllowedRoot $repositoryTmp
    if (Test-Path -LiteralPath $repositoryTmp) {
        $tmpItem = Get-Item -Force -LiteralPath $repositoryTmp
        if (
            ($tmpItem.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw 'La directory tmp del repository e un reparse point.'
        }
    }
    if (Test-Path -LiteralPath $workRoot) {
        $workItem = Get-Item -Force -LiteralPath $workRoot
        if (
            ($workItem.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw 'La directory temporanea di packaging e un reparse point.'
        }
    }
}

function Remove-SafeWorkRoot {
    Assert-SafeWorkRoot
    if (Test-Path -LiteralPath $workRoot) {
        Remove-Item -Recurse -Force -LiteralPath $workRoot
    }
}

function Get-ProjectPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [switch]$Directory
    )

    if (
        [string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('..')
    ) {
        throw "Percorso sorgente non valido: $RelativePath"
    }
    $path = [System.IO.Path]::GetFullPath(
        (Join-Path $projectRoot $RelativePath)
    )
    Assert-PathWithin -Candidate $path -AllowedRoot $projectRoot
    if ($Directory) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Directory sorgente obbligatoria mancante: $RelativePath"
        }
    }
    elseif (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "File sorgente obbligatorio mancante: $RelativePath"
    }
    return $path
}

function Get-StagingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    if (
        [string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains('..')
    ) {
        throw "Destinazione di staging non valida: $RelativePath"
    }
    $path = [System.IO.Path]::GetFullPath(
        (Join-Path $packageRoot $RelativePath)
    )
    Assert-PathWithin -Candidate $path -AllowedRoot $packageRoot
    return $path
}

function Get-RelativeFromRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $pathFull.StartsWith(
            $prefix,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
        throw "Percorso non discendente dalla radice prevista: $pathFull"
    }
    return $pathFull.Substring($prefix.Length).Replace('\', '/')
}

function Test-IsExcludedDirectoryName {
    param([string]$Name)

    return @(
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
    ) -contains $Name.ToLowerInvariant()
}

function Test-IsExcludedFileName {
    param([string]$Name)

    $lower = $Name.ToLowerInvariant()
    if (
        ($lower -eq '.env' -or $lower.StartsWith('.env.')) -and
        $lower -ne '.env.example'
    ) {
        return $true
    }
    return (
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
    )
}

function Get-SafeSourceFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot
    )

    $rootItem = Get-Item -Force -LiteralPath $SourceRoot
    if (
        ($rootItem.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw "Reparse point sorgente vietato: $SourceRoot"
    }

    $stack = New-Object System.Collections.Stack
    $stack.Push($rootItem)
    $files = New-Object System.Collections.ArrayList
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        foreach ($item in Get-ChildItem -Force -LiteralPath $directory.FullName) {
            if (
                ($item.Attributes -band
                    [System.IO.FileAttributes]::ReparsePoint) -ne 0
            ) {
                throw "Reparse point sorgente vietato: $($item.FullName)"
            }
            if ($item.PSIsContainer) {
                if (-not (Test-IsExcludedDirectoryName -Name $item.Name)) {
                    $stack.Push($item)
                }
                continue
            }
            if (-not (Test-IsExcludedFileName -Name $item.Name)) {
                [void]$files.Add($item)
            }
        }
    }
    return @($files.ToArray())
}

function Copy-StagedFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRelative
    )

    $sourceItem = Get-Item -Force -LiteralPath $SourcePath
    if (
        $sourceItem.PSIsContainer -or
        ($sourceItem.Attributes -band
            [System.IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw "File sorgente non regolare: $SourcePath"
    }
    if (Test-IsExcludedFileName -Name $sourceItem.Name) {
        throw "File sorgente vietato: $SourcePath"
    }

    $portableDestination = $DestinationRelative.Replace('\', '/')
    if ($copiedPaths.ContainsKey($portableDestination)) {
        throw "Destinazione duplicata nello staging: $portableDestination"
    }
    $destination = Get-StagingPath -RelativePath $DestinationRelative
    $destinationDirectory = Split-Path -Parent $destination
    New-Item -ItemType Directory -Force -Path $destinationDirectory |
        Out-Null
    Copy-Item -LiteralPath $sourceItem.FullName -Destination $destination
    $copiedPaths[$portableDestination] = $true
}

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRelative,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRelative
    )

    $source = Get-ProjectPath -RelativePath $SourceRelative
    Copy-StagedFile `
        -SourcePath $source `
        -DestinationRelative $DestinationRelative
}

function Copy-AllowedTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRelative,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRelative,

        [scriptblock]$FilePredicate = { param($file) $true }
    )

    $sourceRoot = Get-ProjectPath `
        -RelativePath $SourceRelative `
        -Directory
    $selected = @()
    foreach ($file in Get-SafeSourceFiles -SourceRoot $sourceRoot) {
        if (& $FilePredicate $file) {
            $selected += $file
        }
    }
    if ($selected.Count -eq 0) {
        throw "La directory allowlist non contiene file: $SourceRelative"
    }
    foreach ($file in $selected) {
        $relative = Get-RelativeFromRoot `
            -Root $sourceRoot `
            -Path $file.FullName
        Copy-StagedFile `
            -SourcePath $file.FullName `
            -DestinationRelative (
                $DestinationRelative.TrimEnd('/', '\') +
                '/' +
                $relative
            )
    }
}

function Copy-FlatAllowlist {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRelative,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRelative,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions
    )

    $sourceRoot = Get-ProjectPath `
        -RelativePath $SourceRelative `
        -Directory
    $files = @()
    foreach ($item in Get-ChildItem -Force -LiteralPath $sourceRoot) {
        if (
            ($item.Attributes -band
                [System.IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw "Reparse point sorgente vietato: $($item.FullName)"
        }
        if ($item.PSIsContainer) {
            if (-not (Test-IsExcludedDirectoryName -Name $item.Name)) {
                throw "Sottocartella non ammessa in $SourceRelative`: $($item.Name)"
            }
            continue
        }
        if (Test-IsExcludedFileName -Name $item.Name) {
            continue
        }
        if ($AllowedExtensions -notcontains $item.Extension.ToLowerInvariant()) {
            throw "Estensione non ammessa in $SourceRelative`: $($item.Name)"
        }
        $files += $item
    }
    if ($files.Count -eq 0) {
        throw "La directory allowlist e vuota: $SourceRelative"
    }
    foreach ($file in $files) {
        Copy-StagedFile `
            -SourcePath $file.FullName `
            -DestinationRelative (
                $DestinationRelative.TrimEnd('/', '\') +
                '/' +
                $file.Name
            )
    }
}

function Get-StagedFiles {
    $files = @()
    foreach ($item in Get-SafeSourceFiles -SourceRoot $packageRoot) {
        $files += [pscustomobject]@{
            RelativePath = Get-RelativeFromRoot `
                -Root $packageRoot `
                -Path $item.FullName
            FullName = $item.FullName
            Length = [int64]$item.Length
        }
    }
    return @($files | Sort-Object -Property RelativePath)
}

function Get-LowerSha256 {
    param([string]$Path)

    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).
        Hash.ToLowerInvariant()
}

Assert-SafeWorkRoot
if (-not (Test-Path -LiteralPath $distRoot -PathType Container)) {
    throw 'La cartella dist del repository non esiste.'
}
Assert-PathWithin `
    -Candidate $distRoot `
    -AllowedRoot $projectRoot

Remove-SafeWorkRoot
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

try {
    # Delivery runtime: only the explicit release roots, never delivery/tests.
    Copy-RequiredFile 'delivery\README.md' 'README.md'
    Copy-RequiredFile 'delivery\ALTERVISTA.md' 'ALTERVISTA.md'
    Copy-AllowedTree 'delivery\config' 'config'
    Copy-AllowedTree 'delivery\installer' 'installer'
    Copy-FlatAllowlist `
        'delivery\wheelhouse' `
        'wheelhouse' `
        @('.whl', '.txt', '.json')
    Copy-FlatAllowlist `
        'delivery\artifacts' `
        'artifacts' `
        @('.war', '.txt', '.json', '.md')
    Copy-FlatAllowlist 'output\pdf' 'pdf' @('.pdf')

    Copy-RequiredFile `
        'database\drive-aura-51-source-v2.zip' `
        'database\drive-aura-51-source-v2.zip'
    Copy-RequiredFile `
        'database\drive-aura-51-source-v2.zip.sha256' `
        'database\drive-aura-51-source-v2.zip.sha256'

    # Remote PHP source.
    Copy-RequiredFile 'remote-php\README.md' 'source\remote-php\README.md'
    Copy-AllowedTree 'remote-php\public' 'source\remote-php\public'
    Copy-AllowedTree 'remote-php\src' 'source\remote-php\src'
    Copy-AllowedTree 'remote-php\tests' 'source\remote-php\tests'

    # Java source: parent/module POMs, README and src only; target is never read.
    Copy-RequiredFile `
        'bridge-servlet\README.md' `
        'source\bridge-servlet\README.md'
    Copy-RequiredFile `
        'bridge-servlet\pom.xml' `
        'source\bridge-servlet\pom.xml'
    foreach ($module in @('core', 'tomcat9', 'tomcat11')) {
        Copy-RequiredFile `
            "bridge-servlet\$module\pom.xml" `
            "source\bridge-servlet\$module\pom.xml"
        Copy-AllowedTree `
            "bridge-servlet\$module\src" `
            "source\bridge-servlet\$module\src"
    }

    # Django source and migrations, excluding every generated cache.
    Copy-RequiredFile 'local-django\manage.py' 'source\local-django\manage.py'
    Copy-RequiredFile `
        'local-django\requirements.txt' `
        'source\local-django\requirements.txt'
    Copy-RequiredFile `
        'local-django\README.md' `
        'source\local-django\README.md'
    Copy-AllowedTree `
        'local-django\health_service' `
        'source\local-django\health_service' `
        { param($file) $file.Extension.ToLowerInvariant() -eq '.py' }

    Copy-RequiredFile `
        'shared\entity-schema.json' `
        'source\shared\entity-schema.json'
    Copy-AllowedTree `
        'tests\fixtures' `
        'source\tests\fixtures' `
        { param($file) $file.Extension.ToLowerInvariant() -eq '.json' }
    Copy-RequiredFile `
        'tests\health-contract.json' `
        'source\tests\health-contract.json'
    Copy-RequiredFile `
        'tests\run-health-contracts.ps1' `
        'source\tests\run-health-contracts.ps1'

    # Only the two supported end-to-end verification commands are delivered.
    Copy-RequiredFile `
        'scripts\verify-full-migration.ps1' `
        'tools\verify-full-migration.ps1'
    Copy-RequiredFile `
        'scripts\verify-mass-migration.ps1' `
        'tools\verify-mass-migration.ps1'

    $payloadFiles = @(Get-StagedFiles)
    $manifestRecords = @()
    foreach ($file in $payloadFiles) {
        $manifestRecords += [ordered]@{
            path = $file.RelativePath
            bytes = $file.Length
            sha256 = Get-LowerSha256 -Path $file.FullName
        }
    }
    $manifestObject = [ordered]@{
        formatVersion = 1
        packageRoot = $packageName
        files = $manifestRecords
    }
    $manifestJson = (
        $manifestObject |
            ConvertTo-Json -Depth 6
    ).Replace("`r`n", "`n") + "`n"
    $manifestPath = Join-Path $packageRoot 'PACKAGE-MANIFEST.json'
    [System.IO.File]::WriteAllText(
        $manifestPath,
        $manifestJson,
        $utf8NoBom
    )

    $checksumItems = @($payloadFiles) + @([pscustomobject]@{
        RelativePath = 'PACKAGE-MANIFEST.json'
        FullName = $manifestPath
    })
    $checksumItems = @(
        $checksumItems |
            Sort-Object -Property RelativePath
    )
    $checksumLines = @()
    foreach ($item in $checksumItems) {
        $checksumLines += (
            (Get-LowerSha256 -Path $item.FullName) +
            '  ' +
            $item.RelativePath
        )
    }
    [System.IO.File]::WriteAllText(
        (Join-Path $packageRoot 'SHA256SUMS.txt'),
        ([string]::Join("`n", $checksumLines) + "`n"),
        $utf8NoBom
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archiveStream = [System.IO.File]::Open(
        $archivePath,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $archive = [System.IO.Compression.ZipArchive]::new(
            $archiveStream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        try {
            $fixedTimestamp = [System.DateTimeOffset]::new(
                2026,
                7,
                25,
                0,
                0,
                0,
                [System.TimeSpan]::Zero
            )
            foreach ($file in Get-StagedFiles) {
                $entryName = (
                    $packageName +
                    '/' +
                    $file.RelativePath
                )
                $entry = $archive.CreateEntry(
                    $entryName,
                    [System.IO.Compression.CompressionLevel]::Optimal
                )
                $entry.LastWriteTime = $fixedTimestamp
                $input = [System.IO.File]::OpenRead($file.FullName)
                $output = $entry.Open()
                try {
                    $input.CopyTo($output)
                }
                finally {
                    $output.Dispose()
                    $input.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
    }
    finally {
        $archiveStream.Dispose()
    }

    $archiveHash = Get-LowerSha256 -Path $archivePath
    [System.IO.File]::WriteAllText(
        $archiveSidecarPath,
        "$archiveHash *$archiveName`n",
        $utf8NoBom
    )

    New-Item `
        -ItemType Directory `
        -Force `
        -Path $extractionContainer |
        Out-Null
    [System.IO.Compression.ZipFile]::ExtractToDirectory(
        $archivePath,
        $extractionContainer
    )
    $extractedRoot = Join-Path $extractionContainer $packageName
    $integrityScript = Join-Path (
        Join-Path $extractedRoot 'installer'
    ) 'Test-PackageIntegrity.ps1'
    if (-not (Test-Path -LiteralPath $integrityScript -PathType Leaf)) {
        throw 'Il verificatore di integrita manca dall''archivio estratto.'
    }
    & $integrityScript -PackageRoot $extractedRoot

    $sidecarLine = [System.IO.File]::ReadAllText(
        $archiveSidecarPath,
        $utf8NoBom
    ).Trim()
    if (
        $sidecarLine -ne
            "$archiveHash *$archiveName"
    ) {
        throw 'Il sidecar dell''archivio candidato non coincide.'
    }

    Write-Host "Pacchetto candidato: $archivePath"
    Write-Host "SHA-256: $archiveHash"
    Write-Host "File payload: $($payloadFiles.Count)"
}
finally {
    Remove-SafeWorkRoot
}
