<#
.SYNOPSIS
    Run BinSkim on a repo's packaged artifacts, mirroring the official 1ES SDL pipeline.

.DESCRIPTION
    Extracts .nupkg files (like eng/common/sdl/extract-artifact-packages.ps1), then
    runs BinSkim on the extracted contents. Use after building the repo with -pack.

.PARAMETER RepoRoot
    Path to the repo root. Defaults to current directory.

.PARAMETER PackagesDir
    Path to directory containing .nupkg files. If not specified, searches common locations:
    artifacts\packages\Release\Shipping, artifacts\packages\Release\NonShipping, artifacts\pkgassets.

.PARAMETER OutputSarif
    Path for the SARIF output file. Defaults to binskim-results.sarif in the repo root.

.PARAMETER BinSkimPath
    Path to BinSkim.exe. Defaults to C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe.

.PARAMETER ScanDir
    Scan a directory directly instead of extracting .nupkg files. Useful for pkgassets/ or
    artifacts\bin\ scanning.

.EXAMPLE
    # After build.cmd -c Release -pack:
    .\Invoke-BinSkimScan.ps1

.EXAMPLE
    # Scan pkgassets directly (machinelearning-style):
    .\Invoke-BinSkimScan.ps1 -ScanDir artifacts\pkgassets

.EXAMPLE
    # Scan specific packages directory:
    .\Invoke-BinSkimScan.ps1 -PackagesDir artifacts\packages\Release\Shipping
#>
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$PackagesDir,
    [string]$OutputSarif,
    [string]$BinSkimPath = "C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe",
    [string]$ScanDir
)

$ErrorActionPreference = 'Stop'

# Validate BinSkim
if (-not (Test-Path $BinSkimPath)) {
    Write-Error "BinSkim not found at $BinSkimPath. See references/binskim-install.md."
    exit 1
}

if (-not $OutputSarif) {
    $OutputSarif = Join-Path $RepoRoot "binskim-results.sarif"
}

# Mode 1: Scan a directory directly
if ($ScanDir) {
    $target = Join-Path $RepoRoot $ScanDir
    if (-not (Test-Path $target)) {
        Write-Error "Scan directory not found: $target"
        exit 1
    }
    $fileCount = (Get-ChildItem $target -Recurse -Include "*.dll","*.exe" | Measure-Object).Count
    Write-Host "Scanning $fileCount DLL/EXE files in $target"
    & $BinSkimPath analyze "$target\**" --recurse --output $OutputSarif --pretty-print --force
    Write-Host "Results written to $OutputSarif"
    exit $LASTEXITCODE
}

# Mode 2: Extract .nupkg and scan
if (-not $PackagesDir) {
    # Search common locations
    $candidates = @(
        "artifacts\packages\Release\Shipping"
        "artifacts\packages\Release\NonShipping"
        "artifacts\pkgassets"
    )
    foreach ($c in $candidates) {
        $full = Join-Path $RepoRoot $c
        if (Test-Path $full) {
            $nupkgCount = (Get-ChildItem $full -Filter "*.nupkg" -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($nupkgCount -gt 0) {
                $PackagesDir = $full
                Write-Host "Found $nupkgCount .nupkg files in $c"
                break
            }
            # Check for direct DLLs (pkgassets style)
            $dllCount = (Get-ChildItem $full -Recurse -Filter "*.dll" -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($dllCount -gt 0) {
                Write-Host "Found $dllCount DLLs in $c (no .nupkg — scanning directly)"
                & $BinSkimPath analyze "$full\**" --recurse --output $OutputSarif --pretty-print --force
                Write-Host "Results written to $OutputSarif"
                exit $LASTEXITCODE
            }
        }
    }
    if (-not $PackagesDir) {
        Write-Error "No .nupkg files found in common locations. Build with -pack first, or specify -PackagesDir or -ScanDir."
        exit 1
    }
}

# Extract .nupkg files (mirrors eng/common/sdl/extract-artifact-packages.ps1)
$extractDir = Join-Path $RepoRoot "artifacts\extracted-for-binskim"
if (Test-Path $extractDir) {
    Remove-Item $extractDir -Recurse -Force
}
New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

$relevantExtensions = @('.dll', '.exe', '.pdb')
$nupkgs = Get-ChildItem $PackagesDir -Filter "*.nupkg"
Write-Host "Extracting $($nupkgs.Count) packages..."

foreach ($nupkg in $nupkgs) {
    $pkgName = [System.IO.Path]::GetFileNameWithoutExtension($nupkg.Name)
    $pkgExtractDir = Join-Path $extractDir $pkgName
    New-Item -ItemType Directory -Path $pkgExtractDir -Force | Out-Null

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($nupkg.FullName)
        $extracted = 0
        foreach ($entry in $zip.Entries) {
            $ext = [System.IO.Path]::GetExtension($entry.Name)
            if ($relevantExtensions -contains $ext) {
                $targetPath = Join-Path $pkgExtractDir (Split-Path $entry.FullName)
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                $targetFile = Join-Path $pkgExtractDir $entry.FullName
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetFile, $true)
                $extracted++
            }
        }
        if ($extracted -gt 0) {
            Write-Host "  $pkgName : $extracted files"
        }
    }
    finally {
        if ($zip) { $zip.Dispose() }
    }
}

# Count total scan targets
$totalFiles = (Get-ChildItem $extractDir -Recurse -Include "*.dll","*.exe" | Measure-Object).Count
Write-Host "`nScanning $totalFiles DLL/EXE files from extracted packages..."

# Run BinSkim (exclude _.pdb like the official pipeline does)
& $BinSkimPath analyze "$extractDir\**;-:file|$extractDir\**\_.pdb" --recurse --output $OutputSarif --pretty-print --force

Write-Host "`nResults written to $OutputSarif"

# Quick summary
if (Test-Path $OutputSarif) {
    $sarif = Get-Content $OutputSarif -Raw | ConvertFrom-Json
    $results = $sarif.runs[0].results
    if ($results) {
        $errors = @($results | Where-Object { $_.level -eq 'error' })
        $warnings = @($results | Where-Object { $_.level -eq 'warning' })
        Write-Host "`n=== Summary ==="
        Write-Host "Errors: $($errors.Count), Warnings: $($warnings.Count)"
        if ($errors.Count -gt 0) {
            Write-Host "`nErrors by rule:"
            $errors | Group-Object ruleId | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
        }
    }
    else {
        Write-Host "`nNo findings."
    }
}

exit $LASTEXITCODE
