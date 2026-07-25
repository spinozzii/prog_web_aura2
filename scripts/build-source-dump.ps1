[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Project1Root,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$project2Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (
        Join-Path $project2Root 'database'
    ) 'drive-aura-51-source-v2.zip'
}
$sourceDatabase = Join-Path $Project1Root 'database'
$manifestPath = Join-Path $project2Root 'database\source-dump-manifest.json'
$restoreReadmePath = Join-Path $project2Root 'database\README_SOURCE_DUMP.md'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

$sourceFiles = @(
    [pscustomobject]@{
        Name = 'schema.sql'
        Path = Join-Path $sourceDatabase 'schema.sql'
        ExpectedBytes = [int64]$manifest.sourceFiles[0].bytes
        ExpectedHash = [string]$manifest.sourceFiles[0].sha256
    },
    [pscustomobject]@{
        Name = 'seed_massivo.sql'
        Path = Join-Path $sourceDatabase 'seed_massivo.sql'
        ExpectedBytes = [int64]$manifest.sourceFiles[1].bytes
        ExpectedHash = [string]$manifest.sourceFiles[1].sha256
    }
)

foreach ($source in $sourceFiles) {
    $item = Get-Item -LiteralPath $source.Path
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source.Path).
        Hash.ToLowerInvariant()
    if ($item.Length -ne $source.ExpectedBytes -or
        $hash -ne $source.ExpectedHash) {
        throw "Sorgente inattesa: $($source.Name)."
    }
}

$sourceDocumentationPath = Join-Path (
    $sourceDatabase
) ([string]$manifest.sourceDocumentation.name)
$sourceDocumentation = Get-Item -LiteralPath $sourceDocumentationPath
$sourceDocumentationHash = (
    Get-FileHash -Algorithm SHA256 -LiteralPath $sourceDocumentationPath
).Hash.ToLowerInvariant()
if ($sourceDocumentation.Length -ne
        [int64]$manifest.sourceDocumentation.bytes -or
    $sourceDocumentationHash -ne
        [string]$manifest.sourceDocumentation.sha256) {
    throw 'Documentazione sorgente inattesa.'
}

$expectedCounts = @{}
foreach ($property in $manifest.rowCounts.PSObject.Properties) {
    $expectedCounts[$property.Name] = [int64]$property.Value
}

$actualCounts = @{}
$currentTable = $null
$seedPath = $sourceFiles[1].Path
$utf8 = [System.Text.UTF8Encoding]::new($false)
foreach ($line in [System.IO.File]::ReadLines($seedPath, $utf8)) {
    $insert = [regex]::Match(
        $line,
        '^INSERT\s+INTO\s+`?([a-z_]+)`?',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if ($insert.Success) {
        $currentTable = $insert.Groups[1].Value
        if (-not $actualCounts.ContainsKey($currentTable)) {
            $actualCounts[$currentTable] = [int64]0
        }
        continue
    }
    if ($null -ne $currentTable -and $line.StartsWith('(')) {
        $actualCounts[$currentTable]++
    }
    if ($null -ne $currentTable -and $line -match ';\s*$') {
        $currentTable = $null
    }
}

foreach ($entity in $expectedCounts.Keys) {
    if (-not $actualCounts.ContainsKey($entity) -or
        $actualCounts[$entity] -ne $expectedCounts[$entity]) {
        throw "Conteggio inatteso per $entity."
    }
}
$actualTotal = ($actualCounts.Values | Measure-Object -Sum).Sum
if ($actualCounts.Count -ne $expectedCounts.Count -or
    $actualTotal -ne [int64]$manifest.totalRowCount) {
    throw 'Insieme di entità o totale righe inatteso.'
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Add-Type -AssemblyName System.IO.Compression
$archiveStream = [System.IO.File]::Open(
    $resolvedOutput,
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
        $entries = @(
            [pscustomobject]@{
                Name = 'schema.sql'
                Path = $sourceFiles[0].Path
            },
            [pscustomobject]@{
                Name = 'seed_massivo.sql'
                Path = $sourceFiles[1].Path
            },
            [pscustomobject]@{
                Name = 'source-dump-manifest.json'
                Path = $manifestPath
            },
            [pscustomobject]@{
                Name = 'README_RESTORE.md'
                Path = $restoreReadmePath
            }
        )
        $fixedTimestamp = [System.DateTimeOffset]::new(
            2026, 7, 25, 0, 0, 0, [System.TimeSpan]::Zero
        )
        foreach ($item in $entries) {
            $entry = $archive.CreateEntry(
                $item.Name,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $entry.LastWriteTime = $fixedTimestamp
            $input = [System.IO.File]::OpenRead($item.Path)
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

$zipHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedOutput).
    Hash.ToLowerInvariant()
$checksumPath = "$resolvedOutput.sha256"
$checksumLine = "$zipHash *$([System.IO.Path]::GetFileName($resolvedOutput))`n"
[System.IO.File]::WriteAllText($checksumPath, $checksumLine, $utf8)

$verifyStream = [System.IO.File]::OpenRead($resolvedOutput)
try {
    $verifyArchive = [System.IO.Compression.ZipArchive]::new(
        $verifyStream,
        [System.IO.Compression.ZipArchiveMode]::Read,
        $false
    )
    try {
        foreach ($source in $sourceFiles) {
            $entry = $verifyArchive.GetEntry($source.Name)
            if ($null -eq $entry) {
                throw "Voce mancante nel pacchetto: $($source.Name)."
            }
            $entryStream = $entry.Open()
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try {
                $entryHash = [System.BitConverter]::ToString(
                    $sha.ComputeHash($entryStream)
                ).Replace('-', '').ToLowerInvariant()
            }
            finally {
                $sha.Dispose()
                $entryStream.Dispose()
            }
            if ($entryHash -ne $source.ExpectedHash) {
                throw "Checksum interno non valido: $($source.Name)."
            }
        }
    }
    finally {
        $verifyArchive.Dispose()
    }
}
finally {
    $verifyStream.Dispose()
}

Write-Host "Pacchetto: $resolvedOutput"
Write-Host "SHA-256: $zipHash"
Write-Host "Righe validate: $actualTotal"
