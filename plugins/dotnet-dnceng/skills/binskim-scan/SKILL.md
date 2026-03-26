---
name: binskim-scan
description: >
  Run BinSkim binary security analysis locally, matching the official 1ES SDL pipeline configuration.
  Use when asked to scan binaries for security issues, check BinSkim compliance, verify a fix for a
  BinSkim rule violation (BA2008, BA2024, etc.), or investigate SDL scan results. Also use when asked
  "run binskim", "binary security scan", "SDL scan", "check binskim", "BA2008", "security compliance",
  or "binskim failures". DO NOT USE FOR: source code analysis (use CodeQL), credential scanning
  (use CredScan), or general build/test failures (use ci-analysis).
---

# BinSkim Binary Security Analysis

Run BinSkim locally against a dotnet repository to approximate the results of the official 1ES SDL pipeline. This skill handles: installing BinSkim, building the repo to produce shippable artifacts, discovering what the pipeline actually scans, running BinSkim with matching file targeting, and comparing results with central findings.

> ⚠️ **Local scans are an approximation.** The official pipeline runs BinSkim via Guardian, which may apply different default policies, rule configurations, and organization-level settings. Local scans also don't apply baseline suppressions (`PipelineAutobaseliningConfig.yml`), so you'll see all findings including ones the official pipeline suppresses as known/accepted. For exact-match results, see "Approach 2: Recommend Official Pipeline Run" below.

## Two Approaches

### Approach 1: Local BinSkim Scan (fast, lower fidelity)

Run BinSkim directly on locally-built artifacts. Fast iteration, no pipeline permissions needed, can target specific subtrees. Useful for investigating findings, iterating on fixes, and checking coverage gaps.

**Limitations vs official**: Results will be a **superset** of official findings (no baseline suppression) and may differ in rule severity/enablement because the official pipeline runs BinSkim via Guardian with potentially different defaults and policies. Treat local results as directional, not authoritative.

### Approach 2: Recommend Official Pipeline Run (exact results)

If the user needs exact pass/fail confirmation, **recommend they manually queue the official CI pipeline** against their branch. Do NOT trigger this automatically — just explain how.

> 💡 **SDL does NOT run on PR validation builds.** It only runs on official/CI pipelines (typically gated by `Build.Reason != PullRequest`). The user must manual-queue the official pipeline to get SDL results before merging.

**Per-repo pipeline names** (see [references/repo-profiles.md](references/repo-profiles.md) for details):
- **machinelearning**: Queue `dotnet-machinelearning-official`. SDL config is in `build/vsts-ci.yml`.
- **sdk**: Queue the internal CI pipeline (`.vsts-ci.yml`, not `.vsts-pr.yml`).
- **runtime**: Queue `runtime-official.yml` (SDL via 1ES autobaselining).
- **roslyn**: Queue `azure-pipelines-official.yml`.

Tell the user: *"For exact results matching the official baseline, you can manually queue the official CI pipeline against your branch. This runs the real Guardian+BinSkim with production config and baseline suppressions. It's slower but authoritative."*

## When to Use This Skill

- Verifying a fix for a BinSkim rule violation before pushing
- Investigating BinSkim findings reported from official SDL runs
- Scanning a repo or subtree for binary security issues
- Checking whether a repo's BinSkim config covers everything it ships
- Questions like "why does BA2008 fire on X.dll?", "run binskim on this repo"

**Not for**: source code security (CodeQL), credential scanning (CredScan), or runtime security testing.

## Prerequisites (for local scanning)

- **BinSkim**: Installed at `C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe`. If missing, see [references/binskim-install.md](references/binskim-install.md).
- **Build toolchain**: .NET SDK (managed builds), Visual Studio with MSVC + CMake (native builds). See [references/build-prereqs.md](references/build-prereqs.md).
- **Repo cloned locally**: Typically under `C:\git\<repo-name>`.

## Local Scan Workflow

### Step 1: Discover Pipeline BinSkim Configuration

Before running anything, read the repo's pipeline YAML to understand what the official scan targets.

1. **Find the pipeline YAML** — look for `vsts-ci.yml`, `.vsts-ci.yml`, `azure-pipelines.yml`, `azure-pipelines-official.yml`, or `.ado.yml` at the repo root or under `eng/pipelines/`. Note: some repos have separate PR (`.vsts-pr.yml`) and CI (`.vsts-ci.yml`) pipelines — SDL is typically only in the CI/official one.
2. **Find the `sdl.binskim` section** — this tells you the official config:
   ```yaml
   sdl:
     binskim:
       enabled: true
       scanOutputDirectoryOnly: true    # Only scans published artifacts, not full build output
       # analyzeTargetGlob: ...         # Some repos specify explicit globs
   ```
3. **Check for `BinskimAdditionalRunConfigParams`** — custom flags/exclusions passed to BinSkim.
4. **Check for `1espt/PipelineAutobaseliningConfig.yml`** — some repos only have autobaselining (no explicit config).
5. **Identify what artifacts are published** — look for `PublishPipelineArtifact` steps. The scan targets these.

> 💡 **Report what you find.** Tell the user: "The official pipeline scans X with config Y. I'll reproduce that locally." If the config looks like it misses shipped binaries, flag it: "Warning: pipeline has `scanOutputDirectoryOnly: true` but also ships installers/archives that aren't in the scan target."

See [references/repo-profiles.md](references/repo-profiles.md) for known configurations per repo.

### Step 2: Build the Repo to Produce Scan Targets

The key insight: **BinSkim scans built/packaged binaries, not source code.** You must build (and often pack) the repo to produce what the pipeline scans.

**Standard arcade repos (most dotnet repos):**
```powershell
# Managed + pack (produces .nupkg files)
build.cmd -c Release -pack

# If the repo has native code AND you need pkgassets:
build.cmd -c Release -projects src\Native\Native.proj /p:CopyPackageAssets=true
```

**What to build depends on what the pipeline scans:**

| Pipeline config | What to build locally | Scan target |
|---|---|---|
| `scanOutputDirectoryOnly: true` + publishes `pkgassets` | Build + pack, copy pkgassets | `artifacts\pkgassets\**` |
| `scanOutputDirectoryOnly: true` + publishes NuGet packages | `build.cmd -pack` then extract .nupkg | Extracted .nupkg contents (dll/exe/pdb only) |
| Explicit `analyzeTargetGlob` on `artifacts\bin\` | `build.cmd -c Release` | Use the glob from YAML |
| Autobaselining only | `build.cmd -c Release` | `artifacts\bin\**` (best guess) |

**Extracting .nupkg for scanning** (mirrors what `eng/common/sdl/extract-artifact-packages.ps1` does — only extracts `.dll`, `.exe`, `.pdb`, not the full package):
```powershell
$nupkgDir = "artifacts\packages\Release\Shipping"  # Shipping only — NonShipping is internal tooling
$extractDir = "artifacts\extracted-for-scan"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Get-ChildItem "$nupkgDir\*.nupkg" | ForEach-Object {
    $dest = Join-Path $extractDir $_.BaseName
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $zip = [System.IO.Compression.ZipFile]::OpenRead($_.FullName)
    $zip.Entries | Where-Object { $_.Name -match '\.(dll|exe|pdb)$' } | ForEach-Object {
        $target = Join-Path $dest $_.FullName
        New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($_, $target, $true)
    }
    $zip.Dispose()
}
```

> ⚠️ **Only extract Shipping packages** unless you have reason to believe NonShipping packages are also scanned. The official pipeline typically scans only what's published to customers.

> ⚠️ **Native builds may require extra setup** — MSVC toolchain, Spectre-mitigated libraries, CMake, specific SDKs. If the native build fails, you can still scan managed outputs and NuGet-packaged native blobs from the NuGet cache. See [references/build-prereqs.md](references/build-prereqs.md).

### Step 3: Run BinSkim

```powershell
$binskim = "C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe"
$target = "<scan-target-from-step-1>"
$output = "binskim-results.sarif"

& $binskim analyze $target --recurse --output $output --pretty-print --force
```

**Target patterns** (match what `configure-sdl-tool.ps1` generates):
- Official arcade default: `"$TargetDirectory\**;-:file|$TargetDirectory\**\_.pdb"` — scans all PE binaries (DLL+EXE), excludes `_.pdb` files
- For pkgassets: `"artifacts\pkgassets\**"` (no extension filter needed — BinSkim auto-filters to PE binaries)
- For extracted packages: `"artifacts\extracted-for-scan\**;-:file|artifacts\extracted-for-scan\**\_.pdb"`
- Explicit glob from pipeline: use the `analyzeTargetGlob` value directly

> ⚠️ **Don't filter to `*.dll` only** — the official pipeline scans `**` (all files) and lets BinSkim decide what's a PE binary. This catches `.exe` files too. If you use `*.dll`, you'll miss executables.

**For subtree scanning** (user wants to scan only part of a repo):
```powershell
& $binskim analyze "src\SomeLibrary\artifacts\bin\**\*.dll" --recurse --output $output --pretty-print --force
```

### Step 4: Analyze Results

Parse the SARIF output and summarize:

```powershell
# Quick summary from SARIF
$sarif = Get-Content $output | ConvertFrom-Json
$results = $sarif.runs[0].results
$errors = $results | Where-Object { $_.level -eq 'error' }
$warnings = $results | Where-Object { $_.level -eq 'warning' }

Write-Host "Errors: $($errors.Count), Warnings: $($warnings.Count)"
$errors | Group-Object ruleId | Sort-Object Count -Descending | Format-Table Count, Name
```

**Present results as:**
1. Summary table: rule ID, count, severity
2. Per-binary breakdown for errors (which DLLs fail which rules)
3. For each finding: is this a first-party binary (built in this repo) or third-party (from NuGet)?
4. Comparison with central findings if the user provided them

### Step 5: Compare with Central Pipeline Results (if applicable)

If the user provides central/official BinSkim results:
1. Map each central finding to your local results
2. Flag any **gaps** — findings in central that you don't see locally (likely packaging differences)
3. Flag any **extras** — findings you see locally but not centrally (likely scanning too broadly — test dependencies, transitive NuGet packages)
4. The central pipeline scans only *shipped* artifacts; local builds include test/sample outputs

## Coverage Gap Detection

After scanning, check whether the scan covers everything the repo ships:

1. **List all published artifacts** from the pipeline YAML
2. **Compare with scan targets** — are installers, CLI archives, VSIXes, or native blobs excluded?
3. **Report gaps**: "This repo ships X.zip containing native binaries, but `scanOutputDirectoryOnly: true` only scans the NuGet output. The CLI binaries in X.zip are not covered by BinSkim."

## Non-Arcade Repos

Some repos (e.g., microsoft/perfview) don't use arcade infrastructure. For these:
1. There's no `eng/common/sdl/` — BinSkim config is in the 1ES template or pipeline YAML directly
2. Build output may be in `src\bin\` instead of `artifacts\`
3. Build entry point may be `msbuild` directly instead of `build.cmd`
4. Look for `.ado.yml` or `.pipelines/` directories for pipeline config

The general approach still works: find the pipeline YAML, identify what's published, build it, scan it. You just can't assume arcade conventions.

## Cross-Platform Limitations

This skill targets **Windows scanning only**. The official pipeline may also build and scan Linux/macOS binaries (ELF, Mach-O). If central findings include non-Windows binaries, those cannot be reproduced locally on Windows. Flag this to the user.

## Anti-Patterns

> ❌ **Don't scan the entire `artifacts\bin\` if the pipeline uses `scanOutputDirectoryOnly`.** You'll get hundreds of findings from test dependencies and NuGet-restored third-party DLLs that aren't part of what the repo ships.

> ❌ **Don't report NuGet transitive dependency findings as repo issues.** If `libSkiaSharp.dll` fails BA2008, that's a SkiaSharp issue, not this repo's issue — unless this repo ships it.

> ❌ **Don't skip the pack step.** Many repos' shippable binaries only materialize during packing (native blobs get copied into pkgassets, NuGets get assembled). Building without packing scans the wrong thing.

> ❌ **Don't assume the native build is required.** If native code fails to build locally, you can often still scan the pre-built native blobs from NuGet packages in the local cache (`$env:USERPROFILE\.nuget\packages\`).

## Common BinSkim Rules

| Rule | Description | Typical fix |
|---|---|---|
| BA2008 | EnableControlFlowGuard — CFG not enabled | Rebuild with `/guard:cf` (MSVC) or equivalent |
| BA2024 | EnableSpectreMitigations — Spectre v1 not mitigated | Rebuild with `/Qspectre` and Spectre-mitigated libs |
| BA2006 | BuildWithSecureTools — outdated compiler | Update compiler/toolchain |
| BA2007 | EnableCriticalCompilerWarnings — warnings disabled | Fix `/W` flags |
| BA2011 | EnableStackProtection — `/GS-` used | Remove `/GS-` flag |
| BA2012 | DoNotModifyStackProtectionCookie — custom cookie | Remove custom `__security_cookie` |

## References

- **Installing BinSkim**: [references/binskim-install.md](references/binskim-install.md)
- **Build prerequisites**: [references/build-prereqs.md](references/build-prereqs.md)
- **Per-repo profiles**: [references/repo-profiles.md](references/repo-profiles.md)
- **Arcade SDL infrastructure**: [references/arcade-sdl.md](references/arcade-sdl.md)
