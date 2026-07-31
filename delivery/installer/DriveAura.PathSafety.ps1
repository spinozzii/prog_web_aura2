Set-StrictMode -Version 2.0

function Assert-DriveAuraPathBudget {
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][ValidateRange(1, 247)][int]$RequiredRelativeLength,
        [Parameter(Mandatory = $true)][string]$Label,
        [ValidateRange(128, 248)][int]$MaximumAbsoluteLength = 248
    )

    $fullRoot = [IO.Path]::GetFullPath($RootPath).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $maximumExpected = $fullRoot.Length + $RequiredRelativeLength
    if ($maximumExpected -gt $MaximumAbsoluteLength) {
        throw (
            "Percorso Windows troppo lungo per ${Label}: sono previsti fino a " +
            "$maximumExpected caratteri, limite prudenziale $MaximumAbsoluteLength. " +
            'Riestrarre il pacchetto in C:\DriveAura51 e rilanciare il comando. ' +
            'Lo script non sposta o cancella automaticamente alcun file.'
        )
    }
    return $fullRoot
}
