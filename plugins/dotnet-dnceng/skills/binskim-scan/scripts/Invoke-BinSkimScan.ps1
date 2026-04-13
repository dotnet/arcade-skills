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

.PARAMETER PortalRulesFrom
    Path to a Guardian-merged Results.sarif from an official pipeline run. When specified,
    the summary output filters to only show findings for rules that appear in that file --
    matching what the central portal reports. Other findings are shown separately as
    "informational (not portal-reported)". This avoids confusion from rules that BinSkim
    evaluates but Guardian filters out based on SDL policy.

.EXAMPLE
    # After build.cmd -c Release -pack:
    .\Invoke-BinSkimScan.ps1

.EXAMPLE
    # Scan pkgassets directly (machinelearning-style):
    .\Invoke-BinSkimScan.ps1 -ScanDir artifacts\pkgassets

.EXAMPLE
    # Scan and filter to portal-reported rules:
    .\Invoke-BinSkimScan.ps1 -ScanDir artifacts\pkgassets -PortalRulesFrom C:\temp\sdl\Results.sarif

.EXAMPLE
    # Scan specific packages directory:
    .\Invoke-BinSkimScan.ps1 -PackagesDir artifacts\packages\Release\Shipping
#>
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$PackagesDir,
    [string]$OutputSarif,
    [string]$BinSkimPath = "C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe",
    [string]$ScanDir,
    [string]$PortalRulesFrom
)

$ErrorActionPreference = 'Stop'

# Validate BinSkim
if (-not (Test-Path $BinSkimPath)) {
    $installDocPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\references\binskim-install.md"))
    throw "BinSkim not found at $BinSkimPath. See $installDocPath."
}

if (-not $OutputSarif) {
    $OutputSarif = Join-Path $RepoRoot "binskim-results.sarif"
}
$scanExitCode = 0

# Mode 1: Scan a directory directly
if ($ScanDir) {
    # Support both absolute and relative paths
    if ([System.IO.Path]::IsPathRooted($ScanDir)) {
        $target = $ScanDir
    } else {
        $target = Join-Path $RepoRoot $ScanDir
    }
    if (-not (Test-Path $target)) {
        throw "Scan directory not found: $target"
    }
    $allFiles = Get-ChildItem $target -Recurse -Include "*.dll","*.exe"
    $fileCount = ($allFiles | Measure-Object).Count
    $testFiles = @($allFiles | Where-Object { $_.FullName -match '[\\/](Tests?|Benchmarks?|TestUtilities)[\\/]' })
    Write-Host "Scanning $fileCount files in $target"
    if ($testFiles.Count -gt 0) {
        Write-Host "  Note: $($testFiles.Count) files are in test/benchmark directories and are likely not shipped."
    }
    & $BinSkimPath analyze "$target\**;-:file|$target\**\_.pdb" --recurse --output $OutputSarif --pretty-print --force 2>&1 | Where-Object { $_ -notmatch 'ERR997' }
    $scanExitCode = $LASTEXITCODE
    Write-Host "Results written to $OutputSarif"
}
# Mode 2: Auto-discover or extract .nupkg and scan
elseif (-not $PackagesDir) {
    # Search common locations
    # Common artifact locations (Windows-centric; adapt separators for other platforms)
    $candidates = @(
        (Join-Path $RepoRoot "artifacts\packages\Release\Shipping")
        (Join-Path $RepoRoot "artifacts\packages\Release\NonShipping")
        (Join-Path $RepoRoot "artifacts\pkgassets")
    )
    $foundDirect = $false
    foreach ($full in $candidates) {
        if (Test-Path $full) {
            $nupkgCount = (Get-ChildItem $full -Filter "*.nupkg" -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($nupkgCount -gt 0) {
                $PackagesDir = $full
                Write-Host "Found $nupkgCount .nupkg files in $full"
                break
            }
            # Check for direct DLLs (pkgassets style)
            $dllCount = (Get-ChildItem $full -Recurse -Filter "*.dll" -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($dllCount -gt 0) {
                Write-Host "Found $dllCount DLLs in $full (no .nupkg - scanning directly)"
                & $BinSkimPath analyze "$full\**;-:file|$full\**\_.pdb" --recurse --output $OutputSarif --pretty-print --force 2>&1 | Where-Object { $_ -notmatch 'ERR997' }
                $scanExitCode = $LASTEXITCODE
                Write-Host "Results written to $OutputSarif"
                $foundDirect = $true
                break
            }
        }
    }
    if (-not $PackagesDir -and -not $foundDirect) {
        throw "No .nupkg files found in common locations. Build with -pack first, or specify -PackagesDir or -ScanDir."
    }
}

# Mode 2 continued: Extract and scan .nupkg files if we found packages (not direct DLLs)
if ($PackagesDir) {
    $extractDir = Join-Path $RepoRoot "artifacts\extracted-for-binskim"
    if (Test-Path $extractDir) {
        Remove-Item $extractDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    $relevantExtensions = @('.dll', '.exe', '.pdb')
    $nupkgs = Get-ChildItem $PackagesDir -Filter "*.nupkg"
    Write-Host "Extracting $($nupkgs.Count) packages..."

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($nupkg in $nupkgs) {
        $pkgName = [System.IO.Path]::GetFileNameWithoutExtension($nupkg.Name)
        $pkgExtractDir = Join-Path $extractDir $pkgName
        New-Item -ItemType Directory -Path $pkgExtractDir -Force | Out-Null

        try {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($nupkg.FullName)
            $extracted = 0
            foreach ($entry in $zip.Entries) {
                $ext = [System.IO.Path]::GetExtension($entry.Name)
                if ($relevantExtensions -contains $ext) {
                    # Guard against path traversal (Zip Slip) — ensure entry stays under extract dir
                    $targetFile = Join-Path $pkgExtractDir $entry.FullName
                    $resolvedTarget = [System.IO.Path]::GetFullPath($targetFile)
                    $resolvedBase = [System.IO.Path]::GetFullPath($pkgExtractDir)
                    if (-not $resolvedTarget.StartsWith($resolvedBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                        Write-Warning "Skipping suspicious zip entry: $($entry.FullName)"
                        continue
                    }
                    $targetPath = Split-Path $resolvedTarget
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $resolvedTarget, $true)
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
    & $BinSkimPath analyze "$extractDir\**;-:file|$extractDir\**\_.pdb" --recurse --output $OutputSarif --pretty-print --force 2>&1 | Where-Object { $_ -notmatch 'ERR997' }
    $scanExitCode = $LASTEXITCODE
    Write-Host "`nResults written to $OutputSarif"
}

# Quick summary
if (Test-Path $OutputSarif) {
    $sarif = Get-Content $OutputSarif -Raw | ConvertFrom-Json
    $results = $sarif.runs[0].results
    if ($results) {
        # Discover portal-reported rules if a Results.sarif was provided
        $portalRules = $null
        if ($PortalRulesFrom -and (Test-Path $PortalRulesFrom)) {
            $portalSarif = Get-Content $PortalRulesFrom -Raw | ConvertFrom-Json
            $portalResults = $portalSarif.runs | ForEach-Object { $_.results } | Where-Object { $_ }
            if ($portalResults) {
                $portalRules = @($portalResults | ForEach-Object { $_.ruleId } | Sort-Object -Unique)
                Write-Host "`nPortal-reported rules (from Results.sarif): $($portalRules -join ', ')"
            } else {
                Write-Host "`nWarning: Results.sarif had no findings -- cannot determine portal rules. Showing all."
            }
        }

        $errors = @($results | Where-Object { $_.level -eq 'error' })
        $warnings = @($results | Where-Object { $_.level -eq 'warning' })

        if ($portalRules) {
            # Split findings into portal-reported vs informational
            $portalErrors = @($errors | Where-Object { $portalRules -contains $_.ruleId })
            $portalWarnings = @($warnings | Where-Object { $portalRules -contains $_.ruleId })
            $infoErrors = @($errors | Where-Object { $portalRules -notcontains $_.ruleId })
            $infoWarnings = @($warnings | Where-Object { $portalRules -notcontains $_.ruleId })

            Write-Host "`n=== Portal-Reported Findings (SDL-required for your org) ==="
            Write-Host "Errors: $($portalErrors.Count), Warnings: $($portalWarnings.Count)"
            if ($portalErrors.Count -gt 0) {
                Write-Host "`nPortal errors by rule:"
                $portalErrors | Group-Object ruleId | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
            }
            if ($portalErrors.Count -eq 0 -and $portalWarnings.Count -eq 0) {
                Write-Host "(None -- your fix cleared all portal-reported findings!)"
            }

            if ($infoErrors.Count -gt 0 -or $infoWarnings.Count -gt 0) {
                Write-Host "`n=== Informational Findings (not portal-reported) ==="
                Write-Host "Errors: $($infoErrors.Count), Warnings: $($infoWarnings.Count)"
                if ($infoErrors.Count -gt 0) {
                    Write-Host "`nInformational errors by rule:"
                    $infoErrors | Group-Object ruleId | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
                }
            }
        }
        else {
            # No portal filter -- show everything
            Write-Host "`n=== Summary ==="
            Write-Host "Errors: $($errors.Count), Warnings: $($warnings.Count)"
            if ($errors.Count -gt 0) {
                Write-Host "`nErrors by rule:"
                $errors | Group-Object ruleId | Sort-Object Count -Descending | Format-Table Count, Name -AutoSize
            }
            Write-Host "`nTip: Use -PortalRulesFrom <Results.sarif> to filter to portal-reported rules only."
        }
    }
    else {
        Write-Host "`nNo findings."
    }

    # Summarize ERR997 (PDB not found) from SARIF toolConfigurationNotifications
    $configNotifs = $null
    if ($sarif.runs -and $sarif.runs.Count -gt 0) {
        $firstRun = $sarif.runs[0]
        if ($firstRun.invocations -and $firstRun.invocations.Count -gt 0) {
            $configNotifs = $firstRun.invocations[0].toolConfigurationNotifications
        }
    }
    if ($configNotifs) {
        $pdbErrors = @($configNotifs | Where-Object { $_.descriptor.id -eq 'ERR997.ExceptionLoadingPdb' })
        if ($pdbErrors.Count -gt 0) {
            $uniqueBinaries = @($pdbErrors | ForEach-Object {
                $uri = $_.locations[0].physicalLocation.artifactLocation.uri
                [System.IO.Path]::GetFileName([Uri]::UnescapeDataString($uri))
            } | Sort-Object -Unique)
            Write-Host "`n=== Skipped Binaries (missing PDBs) ==="
            Write-Host "$($pdbErrors.Count) binaries could not be fully evaluated (E_PDB_NOT_FOUND)."
            Write-Host "Unique binaries: $($uniqueBinaries -join ', ')"
            Write-Host "If any of these ship, re-run with symbols present to ensure they are scanned."
        }
    }

    # Flag findings in test/benchmark paths
    if ($results) {
        $testFindings = @($results | Where-Object {
            $_.level -eq 'error' -and
            $_.locations[0].physicalLocation.artifactLocation.uri -match '[\\/](Tests?|Benchmarks?|TestUtilities)[\\/]'
        })
        if ($testFindings.Count -gt 0) {
            Write-Host "`nNote: $($testFindings.Count) error(s) are in test/benchmark paths and are likely not shipped."
        }
    }
}

$global:LASTEXITCODE = $scanExitCode
