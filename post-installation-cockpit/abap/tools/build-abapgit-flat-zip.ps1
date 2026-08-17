param(
    [string]$OutputPath = "dist\s4-post-installation-abapgit-rfc-flat-full-root.zip"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $OutputPath))
$distRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot "dist"))

if (-not $resolvedOutput.StartsWith($distRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output path must stay inside $distRoot"
}

$sourceFiles = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot "src") -Recurse -File |
    Where-Object { $_.Name -ne "package.devc.xml" }
$duplicateNames = $sourceFiles | Group-Object Name | Where-Object Count -gt 1
if ($duplicateNames) {
    $names = $duplicateNames.Name -join ", "
    throw "Cannot create flat archive because filenames collide: $names"
}

$missingMetadata = $sourceFiles |
    Where-Object { $_.Name.EndsWith(".abap", [System.StringComparison]::OrdinalIgnoreCase) } |
    Where-Object {
        $objectBaseName = $_.BaseName
        if ($objectBaseName -match '\.clas\.testclasses$') {
            $objectBaseName = $objectBaseName -replace '\.testclasses$', ''
        }
        elseif ($objectBaseName -match '\.fugr\.[^.]+$') {
            $objectBaseName = $objectBaseName -replace '(\.fugr)\.[^.]+$', '$1'
        }
        $expectedMetadata = Join-Path $_.DirectoryName ($objectBaseName + ".xml")
        -not (Test-Path -LiteralPath $expectedMetadata)
    }
if ($missingMetadata) {
    $names = $missingMetadata.Name -join ", "
    throw "ABAP source files without matching abapGit metadata: $names"
}

New-Item -ItemType Directory -Path (Split-Path -Parent $resolvedOutput) -Force | Out-Null
if ([System.IO.File]::Exists($resolvedOutput)) {
    [System.IO.File]::Delete($resolvedOutput)
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Add-LfTextEntry {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [string]$SourcePath,
        [string]$EntryName
    )

    $content = Get-Content -LiteralPath $SourcePath -Raw
    $content = $content -replace "`r`n?", "`n"
    $entry = $Archive.CreateEntry(
        $EntryName,
        [System.IO.Compression.CompressionLevel]::Optimal
    )
    $writer = [System.IO.StreamWriter]::new(
        $entry.Open(),
        [System.Text.UTF8Encoding]::new($false)
    )
    try {
        $writer.Write($content)
    }
    finally {
        $writer.Dispose()
    }
}
$archive = [System.IO.Compression.ZipFile]::Open(
    $resolvedOutput,
    [System.IO.Compression.ZipArchiveMode]::Create
)

try {
    $metadata = Get-Content -LiteralPath (Join-Path $repositoryRoot ".abapgit.xml") -Raw
    $metadata = $metadata -replace '<FOLDER_LOGIC>[^<]+</FOLDER_LOGIC>', '<FOLDER_LOGIC>FULL</FOLDER_LOGIC>'
    $metadata = $metadata -replace '<STARTING_FOLDER>/src/?</STARTING_FOLDER>', '<STARTING_FOLDER>/src/</STARTING_FOLDER>'
    if ($metadata -notmatch '<FOLDER_LOGIC>FULL</FOLDER_LOGIC>') {
        throw "The archive metadata must use FULL folder logic."
    }
    if ($metadata -notmatch '<STARTING_FOLDER>/src/</STARTING_FOLDER>') {
        throw "The archive metadata must use /src/ as its starting folder."
    }

    $metadataEntry = $archive.CreateEntry(
        ".abapgit.xml",
        [System.IO.Compression.CompressionLevel]::Optimal
    )
    $metadataWriter = [System.IO.StreamWriter]::new(
        $metadataEntry.Open(),
        [System.Text.UTF8Encoding]::new($false)
    )
    try {
        $metadataWriter.Write($metadata)
    }
    finally {
        $metadataWriter.Dispose()
    }

    $rootPackageMetadata = Join-Path $repositoryRoot "src\package.devc.xml"
    if (-not (Test-Path -LiteralPath $rootPackageMetadata)) {
        throw "Root package metadata is missing: $rootPackageMetadata"
    }
    Add-LfTextEntry -Archive $archive `
        -SourcePath $rootPackageMetadata `
        -EntryName "src/package.devc.xml"

    foreach ($file in $sourceFiles) {
        Add-LfTextEntry -Archive $archive `
            -SourcePath $file.FullName `
            -EntryName "src/$($file.Name)"
    }
}
finally {
    $archive.Dispose()
}

$verificationArchive = [System.IO.Compression.ZipFile]::Open(
    $resolvedOutput,
    [System.IO.Compression.ZipArchiveMode]::Read
)
try {
    $entryNames = @($verificationArchive.Entries | ForEach-Object FullName)
    if ($entryNames.Count -ne ($entryNames | Select-Object -Unique).Count) {
        throw "The generated archive contains duplicate entry names."
    }
    if ($entryNames -notcontains ".abapgit.xml" -or
        $entryNames -notcontains "src/package.devc.xml") {
        throw "The generated archive is missing mandatory abapGit metadata."
    }
    if ($entryNames | Where-Object { $_ -notmatch '^(\.abapgit\.xml|src/[^/]+)$' }) {
        throw "The generated archive is not flat under src/."
    }
}
finally {
    $verificationArchive.Dispose()
}

Write-Output $resolvedOutput
