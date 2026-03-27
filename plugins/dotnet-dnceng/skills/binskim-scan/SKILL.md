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

> ⚠️ **Local scans are an approximation.** The official pipeline runs BinSkim via Guardian, which may apply different default policies, rule configurations, and organization-level settings. Local scans don't apply Guardian's filtering/baselining, so you may see more findings than the central portal reports. This can actually be useful — see "Understanding Guardian Filtering" below. For exact-match results, see "Approach 2: Recommend Official Pipeline Run" below.

## Two Approaches

### Approach 1: Local BinSkim Scan (fast, lower fidelity)

Run BinSkim directly on locally-built artifacts. Fast iteration, no pipeline permissions needed, can target specific subtrees. Useful for investigating findings, iterating on fixes, and checking coverage gaps.

**Limitations vs official**: Results will be a **superset** of official findings (no baseline suppression) and may differ in rule severity/enablement because the official pipeline runs BinSkim via Guardian with potentially different defaults and policies. Treat local results as directional, not authoritative.

### Approach 2: Recommend Official Pipeline Run (exact results)

If the user needs exact pass/fail confirmation, **recommend they manually queue the official CI pipeline** against their branch. Do NOT trigger this automatically — just explain how.

> 💡 **SDL does NOT run on PR validation builds.** It only runs on official/CI pipelines (typically gated by `Build.Reason != PullRequest`). The user must manual-queue the official pipeline to get SDL results before merging.

**Per-repo pipeline names and AzDO links** (see [references/repo-profiles.md](references/repo-profiles.md) for details):
- **machinelearning**: [`dotnet-machinelearning-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1110) (dnceng/internal, definition 1110)
- **runtime**: [`dotnet-runtime-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=679) (dnceng/internal, definition 679)
- **roslyn**: [`dotnet-roslyn-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=327) (dnceng/internal, definition 327)
- **aspire**: [`dotnet-aspire`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1309) (dnceng/internal, definition 1309)
- **diagnostics**: [`dotnet-diagnostics`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=528) (dnceng/internal, definition 528)
- **dotnet/dotnet (VMR)**: [`dotnet-unified-build`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1330) (dnceng/internal, definition 1330)
- **sdk**: Look up in AzDO (may be in a different org)
- **aspnetcore**: Look up in AzDO (may be in a different org)
- **perfview**: Official pipeline in devdiv/DevDiv org (not dnceng)

Tell the user: *"For exact results matching the official baseline, you can manually queue the official CI pipeline against your branch. This runs the real Guardian+BinSkim with production config and baseline suppressions. It's slower but authoritative."*

## When to Use This Skill

- Verifying a fix for a BinSkim rule violation before pushing
- Investigating BinSkim findings reported from official SDL runs
- Scanning a repo or subtree for binary security issues
- Checking whether a repo's BinSkim config covers everything it ships
- Questions like "why does BA2008 fire on X.dll?", "run binskim on this repo"

**Not for**: source code security (CodeQL), credential scanning (CredScan), or runtime security testing.

## Prerequisites (for local scanning)

- **BinSkim**: See [references/binskim-install.md](references/binskim-install.md) for installation.
  - Windows: `C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe`
  - Linux: `~/binskim-tool/extracted/tools/net9.0/linux-x64/BinSkim`
- **Build toolchain**: .NET SDK (managed builds). For native code: MSVC + CMake on Windows, gcc/clang + CMake on Linux. See [references/build-prereqs.md](references/build-prereqs.md).
- **Repo cloned locally**: Typically under `C:\git\<repo-name>` (Windows) or `~/git/<repo-name>` (Linux).

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
# Windows
build.cmd -c Release -pack

# Linux
./build.sh -c Release -pack
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
>
> **NuGet cache limitation**: Scanning NuGet-cached DLLs only covers third-party native blobs consumed via NuGet packages. It misses: (1) first-party native code compiled from source, (2) managed assemblies the repo builds, and (3) pack-only artifacts. For repos like machinelearning where all current BA2008 findings are on NuGet-sourced Intel DLLs, this is sufficient. For repos that compile native code from source, a full build is needed for complete coverage.

### Step 3: Run BinSkim

**Preferred: Use the helper script** which handles scanning, summary, and portal filtering:

```powershell
$script = "c:\git\arcade-skills\plugins\dotnet-dnceng\skills\binskim-scan\scripts\Invoke-BinSkimScan.ps1"

# Scan a directory directly (e.g., pkgassets):
& $script -RepoRoot C:\git\machinelearning -ScanDir artifacts\pkgassets

# Scan and filter to portal-reported rules:
& $script -RepoRoot C:\git\machinelearning -ScanDir artifacts\pkgassets -PortalRulesFrom C:\temp\Results.sarif

# Auto-discover scan targets (searches common artifact locations):
& $script -RepoRoot C:\git\machinelearning
```

> 💡 `-ScanDir` accepts both relative paths (joined with `-RepoRoot`) and absolute paths.

**Manual BinSkim invocation** (if not using the helper script):

```powershell
$binskim = "C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe"
$target = "<scan-target-from-step-1>"
$output = "binskim-results.sarif"

# Note: newer BinSkim versions (4.x+) use --log syntax, not --pretty-print/--force
& $binskim analyze $target --recurse --output $output --log "PrettyPrint;ForceOverwrite"
# Older versions may use: --pretty-print --force
```

**Target patterns** (match what `configure-sdl-tool.ps1` generates):
- Official arcade default: `"$TargetDirectory\**;-:file|$TargetDirectory\**\_.pdb"` — scans all PE binaries (DLL+EXE), excludes `_.pdb` files
- For pkgassets: `"artifacts\pkgassets\**"` (no extension filter needed — BinSkim auto-filters to PE binaries)
- For extracted packages: `"artifacts\extracted-for-scan\**;-:file|artifacts\extracted-for-scan\**\_.pdb"`
- Explicit glob from pipeline: use the `analyzeTargetGlob` value directly

> ⚠️ **Don't filter to `*.dll` only** — the official pipeline scans `**` (all files) and lets BinSkim decide what's a PE binary. This catches `.exe` files too. If you use `*.dll`, you'll miss executables.

**For subtree scanning** (user wants to scan only part of a repo):
```powershell
& $binskim analyze "src\SomeLibrary\artifacts\bin\**\*.dll" --recurse --output $output --log "PrettyPrint;ForceOverwrite"
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

> 💡 **Local scans are a superset, not a subset.** Local BinSkim sees ALL findings because there's no Guardian filtering. If the user's central portal shows fewer findings than your local scan, that's expected — Guardian filters findings before they reach the portal. To understand what's being filtered, download the raw `binskim.sarif` from the SDL build artifacts (see "Understanding Guardian Filtering" below).

### Step 6: Download and Compare Raw vs Merged SARIF (for investigation)

When investigating discrepancies between local results and the central portal, download the SDL artifacts from the official build:

```powershell
# Download SDL artifact from official build
# Use AzDO tools or the ado-dnceng-pipelines_download_artifact tool
# Artifact names follow the pattern: drop_build_<OS>_<arch>_sdl_analysis
# For the VMR (dotnet/dotnet): drop_VMR_Vertical_Build_<OS>_<arch>_sdl_analysis
# Some repos have multiple SDL legs — check all Windows legs for complete coverage

# Key files inside the artifact:
# - binskim/001/binskim.sarif    ← Raw BinSkim output (everything it found)
# - Results.sarif                 ← Guardian-merged output (what the portal sees)
# - break/001/options.json        ← Break policy (which tools can fail the build)
# - .gdnbaselines                 ← Auto-generated baseline suppressions
```

> ⚠️ **Large SARIF files**: For repos with many binaries (especially the VMR), the raw `binskim.sarif` and `Results.sarif` can be **50-80MB+**. Use PowerShell's `Get-Content -Raw | ConvertFrom-Json` to parse them — don't try to read them into your context directly. Stream through results with `ForEach-Object` and `Group-Object` for analysis.

This is the authoritative way to understand the gap between "what BinSkim found" and "what the portal reports."

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

## Cross-Platform

BinSkim ships for Windows, Linux (x64, arm64), and macOS (x64). Use the platform-appropriate binary:
- Windows: `tools/net9.0/win-x64/BinSkim.exe`
- Linux: `tools/net9.0/linux-x64/BinSkim` (make executable: `chmod +x`)
- macOS: `tools/net9.0/osx-x64/BinSkim`

Use `build.sh` instead of `build.cmd` on Linux/macOS. Artifact paths use forward slashes.

If the official pipeline builds and scans on a different OS than the one you're on, you may not be able to reproduce those specific findings locally (e.g., ELF binaries on Windows).

## Before/After Comparison (Optional)

To prove a fix resolved specific findings, scan before and after the change:

1. **Baseline scan** on `main` (or the branch before your fix):
   ```
   git stash  # or checkout main
   # build + scan → binskim-before.sarif
   ```
2. **Fix scan** on your branch:
   ```
   git stash pop  # or checkout fix-branch
   # build + scan → binskim-after.sarif
   ```
3. **Diff the results**:
   ```powershell
   $before = (Get-Content binskim-before.sarif | ConvertFrom-Json).runs[0].results | Where-Object { $_.level -eq 'error' }
   $after  = (Get-Content binskim-after.sarif  | ConvertFrom-Json).runs[0].results | Where-Object { $_.level -eq 'error' }
   Write-Host "Before: $($before.Count) errors, After: $($after.Count) errors"
   # Compare by ruleId + target binary for specific delta
   ```

> ⚠️ This requires two full builds, so it's slow. Only suggest this when the user specifically wants proof that a fix works. For most cases, a single scan of the fix branch is sufficient.

## Fix Strategies by Finding Type

Not all BinSkim findings can be fixed the same way. The fix strategy depends on whether the flagged binary is **built from source** in the repo or **consumed as a pre-built dependency**.

### Classify the finding first

Before recommending a fix, determine where the binary comes from:

1. **Search the repo for the binary name** — is there a `.vcxproj`, `.csproj`, or `CMakeLists.txt` that produces it?
2. **Check NuGet packages** — is the binary copied from a `PackageReference` or `$(PkgXxx)` path?
3. **Check for `<Content Include="...">` items** — is it a pre-built file just being copied to output?

### Fix strategies

| Binary origin | Example | Fix approach |
|---|---|---|
| **C++ source in repo** (`.vcxproj`) | EtwClrProfiler.dll in perfview | Add compiler/linker flags to the project file (e.g., `/guard:cf` for BA2008, `/Qspectre` for BA2024) |
| **Pre-built native from NuGet** | winterop.dll (WiX), Intel MKL/TBB DLLs | **Cannot fix in this repo.** Update to newer package version, file issue upstream, or suppress/baseline |
| **Third-party test framework** | xunit.*.dll | Fix scan scope — these shouldn't be in shipped artifacts. Exclude via BinSkim glob or fix packaging |
| **Pre-built test fixtures** | mockclr_*.dll, mockdac.dll | Fix scan scope — exclude `**/TestBinaries/**` from scan target, or suppress/baseline |
| **Managed C# assembly** | Most `.dll` from `.csproj` | BA2008 is **not applicable** (BinSkim skips IL-only). BA2004/BA2027 may apply — use csc options |

### Common misconception: `<ControlFlowGuard>` in C# projects

Setting `<ControlFlowGuard>Guard</ControlFlowGuard>` in a `.csproj` or `Directory.Build.targets` does **nothing** for C# projects. The C# compiler (`csc`) does not support `/guard:cf`. This property only works in `.vcxproj` (MSVC C++ projects). BA2008 only fires on native PE binaries anyway — managed assemblies are skipped.

### VMR (dotnet/dotnet) fix ownership

In the VMR, findings map to source sub-repos. Fixes should be made in the **source repo** (e.g., `dotnet/arcade`, `dotnet/runtime`), not the VMR itself. To identify the owning sub-repo, look at the artifact path in the SARIF — e.g., `src/arcade/artifacts/...` → fix goes to `dotnet/arcade`.

## Anti-Patterns

> ❌ **Don't scan the entire `artifacts\bin\` if the pipeline uses `scanOutputDirectoryOnly`.** You'll get hundreds of findings from test dependencies and NuGet-restored third-party DLLs that aren't part of what the repo ships.

> ❌ **Don't report NuGet transitive dependency findings as repo issues.** If `libSkiaSharp.dll` fails BA2008, that's a SkiaSharp issue, not this repo's issue — unless this repo ships it.

> ❌ **Don't skip the pack step.** Many repos' shippable binaries only materialize during packing (native blobs get copied into pkgassets, NuGets get assembled). Building without packing scans the wrong thing.

> ❌ **Don't assume the native build is required.** If native code fails to build locally (e.g., missing Spectre-mitigated MSVC libs), you can still scan pre-built native DLLs from the NuGet cache. Many BinSkim rules (including BA2008) don't need PDBs, so NuGet-cached binaries work fine. PDB-dependent rules like BA2028 will report ERR997.ExceptionLoadingPdb instead of actual findings.

> ❌ **Don't trust the central portal as the complete picture.** Download the raw `binskim.sarif` from the SDL build artifacts and compare it with the Guardian-merged `Results.sarif`. The portal shows only findings for rules with SDL policy requirement mappings — other Error-level findings may be legitimately filtered based on your org's SDL requirements.

> ❌ **Don't assume "not in the portal" means "not a problem."** Guardian filtering removes findings for rules without SDL policy mappings for your org. These may still be good security practice even if not SDL-required. Review the raw SARIF to understand the full picture.

> ❌ **Don't confuse break policy with reporting.** The break policy (`IncludeTools`) controls whether BinSkim can fail the build. It does NOT control what gets reported to the portal. Findings can be reported without breaking the build, and findings can be filtered from reporting even if they would break the build.

> ❌ **Don't be alarmed by extra local findings.** Local BinSkim scans evaluate ALL rules. The portal only reports a subset (those with SDL policy mappings). Use `-PortalRulesFrom` to filter local results to match what the portal cares about.

## BinSkim Rules by Platform and SDL Compliance

Not all Error-level rules are reported to the central portal — Guardian filters based on internal SDL policy requirement mappings. Rules at **Warning** severity are recommended best practices. Use the `-PortalRulesFrom` parameter to discover which rules your pipeline actually reports.

> ⚠️ **"Required" ≠ "the build will break."** Whether the build actually breaks on BinSkim errors depends on whether the repo's Guardian `break` policy includes BinSkim in its `IncludeTools` list. Many repos do not — BinSkim runs and reports but doesn't gate the build. Error-level findings are still SDL requirements regardless of whether the build breaks on them.

### Windows PE Rules (BA2xxx)

These apply to `.dll` and `.exe` files built with MSVC or the managed compiler.

| Rule | Name | Severity | Typical fix |
|---|---|---|---|
| BA2001 | LoadImageAboveFourGigabyteAddress | Error | Remove custom `/BASE`; use default base address |
| BA2002 | DoNotIncorporateVulnerableDependencies | Error | Update vulnerable static-linked dependency |
| BA2003 | EnableStackProtection | Error | (Related to BA2011) |
| BA2004 | EnableSecureSourceCodeHashing | Error | Use `/ZH:SHA_256` (MSVC 17.0+) or `-checksumalgorithm:SHA256` (csc) |
| BA2005 | DoNotShipVulnerableBinaries | Error | Update obsolete library to patched version |
| BA2006 | BuildWithSecureTools | Error | Update compiler/toolchain to minimum required version |
| BA2007 | EnableCriticalCompilerWarnings | Error | Compile at `/W3` or higher; don't disable required warnings |
| BA2008 | EnableControlFlowGuard | Error | Rebuild with `/guard:cf` on both cl.exe and link.exe |
| BA2009 | EnableAddressSpaceLayoutRandomization | Error | Don't set `/DYNAMICBASE:NO`; use default |
| BA2010 | DoNotMarkImportsSectionAsExecutable | Error | Remove `/SECTION` or `/MERGE` that makes imports executable |
| BA2011 | EnableStackProtection | Error | Don't use `/GS-`; keep default `/GS` |
| BA2012 | DoNotModifyStackProtectionCookie | Error | Remove custom `__security_cookie` symbol |
| BA2013 | InitializeStackProtection | Error | Use default CRT entry point or call `__security_init_cookie()` |
| BA2014 | DoNotDisableStackProtectionForFunctions | Error | Remove `__declspec(safebuffers)` |
| BA2015 | EnableHighEntropyVirtualAddresses | Error | Don't set `/HIGHENTROPYVA:NO` |
| BA2016 | MarkImageAsNXCompatible | Error | Don't set `/NXCOMPAT:NO` |
| BA2018 | EnableSafeSEH (x86 only) | Error | Pass `/SAFESEH` to linker (x86 builds only) |
| BA2019 | DoNotMarkWritableSectionsAsShared | Error | Remove shared+writable section attributes |
| BA2021 | DoNotMarkWritableSectionsAsExecutable | Error | Don't use writable+executable sections; disable incremental linking in release |
| BA2022 | SignSecurely | Error | Sign with SHA-256 or stronger; don't use SHA-1 |
| BA2024 | EnableSpectreMitigations | **Warning** | Rebuild with `/Qspectre` and Spectre-mitigated libs |
| BA2025 | EnableShadowStack (CET) | **Warning** | Pass `/CETCOMPAT` to linker |
| BA2026 | EnableMicrosoftCompilerSdlSwitch | **Warning** | Pass `/sdl` to cl.exe |
| BA2027 | EnableSourceLink | **Warning** | Enable SourceLink in project properties |
| BA2028 | EnableCastGuard | Error | Pass `/guard:ehcont` to cl.exe and `/GUARD:EHCONT` to linker. **Note: may be scoped to specific orgs per SDL policy.** |
| BA2029 | EnableIntegrityCheck | Error | Pass `/INTEGRITYCHECK` to linker (required for drivers, PPL) |

### Linux ELF Rules (BA3xxx)

These apply to `.so` shared libraries and executables built with GCC or Clang on Linux.

| Rule | Name | Severity | Typical fix |
|---|---|---|---|
| BA3001 | EnablePositionIndependentExecutable | Error | Compile with `-fpie`; link with `-pie` |
| BA3002 | DoNotMarkStackAsExecutable | Error | Compile/link with `-z noexecstack` |
| BA3003 | EnableStackProtector | Error | Compile with `--fstack-protector-strong` or `-all` |
| BA3004 | GenerateRequiredSymbolFormat | Error | Use `-gdwarf-5` for debug symbols |
| BA3005 | EnableStackClashProtection | Error | Compile with `-fstack-clash-protection` |
| BA3006 | EnableNonExecutableStack | Error | Compile with `-z noexecstack` |
| BA3010 | EnableReadOnlyRelocations | Error | Link with `-Wl,-z,relro` |
| BA3011 | EnableBindNow | Error | Link with `-Wl,-z,now` |
| BA3030 | UseGccCheckedFunctions (GCC only) | Error | Compile with `-D_FORTIFY_SOURCE=2 -O2` |
| BA3031 | EnableClangSafeStack (Clang only) | Error | Compile/link with `-fsanitize=safe-stack` |

### macOS Mach-O Rules (BA5xxx)

These apply to `.dylib` and executables built for macOS/iOS.

| Rule | Name | Severity | Typical fix |
|---|---|---|---|
| BA5001 | EnablePositionIndependentExecutable | Error | Compile with `-fpie` |
| BA5002 | DoNotAllowExecutableStack | Error | Don't use `--allow_stack_execute` |

### Key notes

- **Not all Error-level rules are SDL-required.** Guardian filters findings based on internal SDL policy requirement mappings before reporting to the central portal. Some Error-level rules (e.g., BA2028 CastGuard) may be scoped to specific orgs and filtered out for others. Use the `-PortalRulesFrom` parameter in `Invoke-BinSkimScan.ps1` to auto-discover which rules your pipeline actually reports.
- **Which rules are required depends on your service tree registration** (`es-metadata.yml`). Different orgs have different SDL policy scopes. For example, `devdiv` repos (most dotnet/* repos) require BA2008/BA2009/BA2021, while `nettel` repos (e.g., microsoft/perfview) require BA2004/BA2027 instead. Always check your own portal — don't assume rules from another repo apply to yours.
- **Managed-only assemblies** (pure C#/VB) are generally **not subject** to most BA2xxx rules — BinSkim auto-skips IL-only and mixed-mode binaries as NotApplicable. BA2008 (EnableControlFlowGuard) specifically **only applies to native PE binaries** — it will never fire on C# assemblies. Rules like BA2004 (secure hashing) and BA2027 (SourceLink) can apply to managed code.
- **BA2008 findings are almost always on third-party native binaries** consumed via NuGet (e.g., Intel MKL/oneDAL/TBB, WiX winterop.dll, emsdk toolchain). These can't be fixed in your repo — the upstream vendor must recompile with `/guard:cf`. Fix options: update to a newer package version, suppress/baseline, or file an issue upstream.
- **BA2022 (SignSecurely) can produce thousands of raw findings** — especially on satellite resource DLLs (`.resources.dll`). These are typically all filtered by Guardian before reaching the portal. Don't be alarmed by high BA2022 counts in raw SARIF.
- **`<ControlFlowGuard>Guard</ControlFlowGuard>` only works for C++ (`.vcxproj`)** — it maps to `/guard:cf` in the MSVC toolchain. The C# compiler (`csc`) has no `/guard:cf` support, and the .NET SDK doesn't wire this MSBuild property to anything for `.csproj` projects. This MSBuild property does nothing for managed code.
- **BA2024 (Spectre) is Warning, not Error** — it fires frequently on third-party native dependencies.
- **Cross-platform repos** shipping both Windows and Linux binaries need to pass **both** BA2xxx and BA3xxx rules. BinSkim auto-detects binary format — you don't need separate rule configs.
- **BA4002** (ReportElfOrMachoCompilerData) is informational only — it emits CSV data about compilers found, with no pass/fail.
- **BA6004** (EnableComdatFolding) and **BA6006** (EnableLinkTimeCodeGeneration) are optimization hints, not security rules. They may appear in SARIF but have no SDL compliance impact.

### Observed portal requirements by service tree org

Which BinSkim rules actually appear in the portal depends on the `es-metadata.yml` service tree registration (the `routing.defaultAreaPath.org` field). Based on empirical observation across multiple repos:

| Rule | Description | devdiv org (most dotnet/*) | nettel org (microsoft/perfview) |
|------|-------------|----------------------------|---------------------------------|
| BA2004 | EnableSecureSourceCodeHashing | ❌ filtered | ✅ required |
| BA2008 | EnableControlFlowGuard | ✅ required | ? |
| BA2009 | EnableAddressSpaceLayoutRandomization | ✅ required | ? |
| BA2021 | DoNotMarkWritableSectionsAsExecutable | ✅ required | ? |
| BA2027 | EnableSourceLink | ❌ filtered | ✅ required |
| BA2022 | SignSecurely | ❌ filtered | ? |
| BA2024 | EnableSpectreMitigations | ❌ filtered | ? |
| BA2025 | EnableShadowStack (CET) | ❌ filtered | ? |
| BA2026 | EnableMicrosoftCompilerSdlSwitch | ❌ filtered | ? |
| BA2028 | EnableCastGuard | ❌ filtered | ? |

> ⚠️ This table is **observational** — derived from comparing raw `binskim.sarif` vs `Results.sarif` across repos. "❌ filtered" means confirmed absent from portal despite raw findings existing. "?" means untested. Always use `-PortalRulesFrom` to discover your own repo's requirements rather than relying on this table.

## Understanding Guardian Filtering

The official pipeline runs BinSkim via Guardian, and the results go through multiple filtering layers before reaching the central portal. Understanding this pipeline is important for interpreting what the portal shows (and doesn't show).

### The filtering pipeline

```
BinSkim runs → raw binskim.sarif (ALL findings)
     ↓
Guardian merges/filters → Results.sarif (subset of findings)
     ↓
Results.sarif uploaded → Central portal shows only what survived
```

The raw `binskim.sarif` is available in the SDL build artifacts (e.g., `drop_build_Windows_x64_sdl_analysis` for most repos, or `drop_VMR_Vertical_Build_Windows_x64_sdl_analysis` for the VMR). The merged `Results.sarif` is in the same artifact. **Always compare both** to understand what's being filtered.

### What gets filtered and why

Guardian filters BinSkim findings before reporting them to the central portal. The primary mechanism is **SDL policy requirement mappings** — an internal, centrally-managed policy that defines which BinSkim rules are required for SDL compliance. Only findings for rules with applicable policy mappings are promoted to `Results.sarif` and the portal. Other findings are silently dropped.

**The required rules vary by service tree org** (from `es-metadata.yml`). For example, `devdiv` org repos (most `dotnet/*` repos) have BA2008, BA2009, and BA2021 as required rules, while `nettel` org repos (e.g., `microsoft/perfview`) have BA2004 and BA2027 instead. See the "Observed portal requirements by service tree org" table above.

This filtering is:
- **Not severity-based**: Some Error-level rules may be filtered out if they lack a policy mapping for your org
- **Not auto-baselining**: The `.gdnbaselines` files track known findings but don't remove them from reporting
- **Not a human suppression**: No one in your repo explicitly chose to hide these findings
- **Centrally managed**: The SDL team maintains which rules have policy mappings, and some rules are scoped to specific orgs

The practical implication: **your local BinSkim scan will find more issues than the portal reports.** This is expected and correct — the portal only shows what SDL policy requires for your org.

> 💡 **To match the portal locally**: Use `-PortalRulesFrom` with the `Invoke-BinSkimScan.ps1` script. It downloads the `Results.sarif` from your pipeline and extracts the set of rules that survived Guardian filtering, then filters your local results to match. See "Matching Portal Results Locally" below.

Other filtering layers:

1. **Break policy (`IncludeTools`)**: Controls whether BinSkim can fail the build. Found in the `break/001/options.json` artifact. Many repos don't include BinSkim in `IncludeTools` — meaning BinSkim never breaks the build regardless of findings. This is separate from reporting.

2. **Auto-baselining**: The `.config/1espt/PipelineAutobaseliningConfig.yml` file enables auto-baselining. Guardian generates `.gdnbaselines` and `.gdnsuppress` files as pipeline artifacts (not checked into source). These track known findings for break-on-new-only logic but do **not** remove findings from the portal.

### How to investigate

When asked about BinSkim findings for a repo, **don't trust the central portal alone**. Download the SDL artifacts and examine both:

1. **Download the SDL artifact** from the official build (e.g., `drop_build_Windows_x64_sdl_analysis` or `drop_VMR_Vertical_Build_Windows_x64_sdl_analysis` for VMR repos)
2. **Parse raw `binskim.sarif`** (in `binskim/001/binskim.sarif`) — this has everything BinSkim actually found
3. **Parse merged `Results.sarif`** (in the artifact root) — this is what the portal sees
4. **Compare them** — the delta is what Guardian filtered out
5. **Check `break/001/options.json`** — look at `IncludeTools` to see if BinSkim can actually break the build

```powershell
# Compare raw vs merged findings
$raw = (Get-Content "binskim\001\binskim.sarif" -Raw | ConvertFrom-Json).runs[0].results
$merged = (Get-Content "Results.sarif" -Raw | ConvertFrom-Json).runs[0].results

Write-Host "Raw BinSkim findings: $($raw.Count)"
Write-Host "After Guardian filtering: $($merged.Count)"
Write-Host "`nRaw findings by rule:"
$raw | Group-Object ruleId | ForEach-Object {
    $levels = ($_.Group | ForEach-Object { $_.level } | Sort-Object -Unique) -join ","
    Write-Host "  $($_.Name): count=$($_.Count) levels=[$levels]"
}
```

### Suppression mechanisms (where human decisions go)

If someone wants to **explicitly** suppress a finding, these are the mechanisms:

| Mechanism | File | Scope | Human decision? |
|---|---|---|---|
| SDL Policy filtering | Internal SDL rule database (not in repo) | Per-rule, per-org | No — managed centrally |
| Auto-baselining | `.config/1espt/PipelineAutobaseliningConfig.yml` | Pipeline-level | No — automatic |
| Guardian baselines | `.gdnbaselines` (pipeline artifact) | Per-finding | No — auto-generated, tracks known findings |
| Guardian suppress | `.gdnsuppress` (can be checked into repo) | Per-finding | Yes — if in source control |
| Break policy | Pipeline YAML / template config | Per-tool | Semi — configured once |

The primary filtering is SDL Policy — only rules the SDL team has marked as required for your org are reported to the portal. To explicitly suppress a specific finding that IS reported, teams would add it to a `.gdnsuppress` file in source control — but this is rarely done in dotnet repos.

### Matching Portal Results Locally

To filter local BinSkim results to match what the portal reports, use the `-PortalRulesFrom` parameter:

```powershell
# Point to a downloaded Results.sarif from your official pipeline's SDL artifact
.\Invoke-BinSkimScan.ps1 -ScanDir artifacts\pkgassets -PortalRulesFrom path\to\Results.sarif
```

This extracts the set of rule IDs that appear in the Guardian-merged `Results.sarif` and filters your local results to only show those rules. This way:
- Your local scan matches the portal — no confusing extra findings
- You can verify a fix worked before merging
- You don't need to know which rules have SDL policy mappings (the pipeline tells you)

To get the `Results.sarif`, download the SDL artifact from your official pipeline (e.g., `drop_build_Windows_x64_sdl_analysis`) and look for `Results.sarif` in the artifact root.

## References

- **Installing BinSkim**: [references/binskim-install.md](references/binskim-install.md)
- **Build prerequisites**: [references/build-prereqs.md](references/build-prereqs.md)
- **Per-repo profiles**: [references/repo-profiles.md](references/repo-profiles.md)
- **Arcade SDL infrastructure**: [references/arcade-sdl.md](references/arcade-sdl.md)
