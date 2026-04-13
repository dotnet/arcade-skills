---
name: binskim-scan
description: >
  Run BinSkim binary security analysis locally against a dotnet repository.
  Use when asked to scan binaries, check BinSkim compliance, verify a fix for a rule violation,
  or run a local SDL scan. Also use when asked "run binskim", "binary security scan", "scan binaries",
  "check binskim", "verify my fix", "repro BA2008 locally", or "verify BA2008 fix". DO NOT USE FOR:
  investigating official pipeline results or portal findings (use binskim-analysis), source code
  analysis (use CodeQL), credential scanning (use CredScan), or general build/test failures
  (use ci-analysis).
---

# BinSkim Local Scanning

Run BinSkim locally against a dotnet repository to find binary security issues. This skill covers installing BinSkim, building the repo, discovering what the official pipeline scans, running BinSkim with matching targeting, and interpreting results.

> **Local scans are an approximation.** The official pipeline runs BinSkim via Guardian with additional filtering. Local scans produce a **superset** of official findings. For understanding what the portal reports vs what BinSkim finds, use the **binskim-analysis** skill. For authoritative pass/fail confirmation, recommend the user manually queue the official CI pipeline against their branch — SDL does not run on PR validation builds.

## When to Use This Skill

- Running BinSkim locally to scan binaries for security issues
- Verifying a fix for a BinSkim rule violation before pushing
- Checking whether a repo's scan config covers everything it ships
- Iterating on a fix with fast local feedback

**Not for**: interpreting official pipeline results (use **binskim-analysis**), source code security (CodeQL), or credential scanning (CredScan).

## Prerequisites

- **BinSkim**: See [references/binskim-install.md](references/binskim-install.md) for installation.
  - Windows: `C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe`
  - Linux: `~/binskim-tool/extracted/tools/net9.0/linux-x64/BinSkim`
- **Build toolchain**: .NET SDK (managed builds). For native code: MSVC + CMake on Windows, gcc/clang + CMake on Linux. See [references/build-prereqs.md](references/build-prereqs.md).
- **Repo cloned locally**: Typically under `C:\git\<repo-name>` (Windows) or `~/git/<repo-name>` (Linux).

## Local Scan Workflow

### Step 1: Discover Pipeline BinSkim Configuration

Before scanning, read the repo's pipeline YAML to understand what the official scan targets.

1. **Find the pipeline YAML** — look for `azure-pipelines-official.yml`, `vsts-ci.yml`, `.vsts-ci.yml`, `azure-pipelines.yml`, or `.ado.yml` at the repo root or under `eng/pipelines/`. SDL is typically only in the CI/official pipeline, not the PR one.
2. **Find the `sdl.binskim` section**:
   ```yaml
   sdl:
     binskim:
       enabled: true
       scanOutputDirectoryOnly: true
   ```
3. **Check for `BinskimAdditionalRunConfigParams`** — custom flags/exclusions.
4. **Identify what artifacts are published** — look for `PublishPipelineArtifact` steps. The scan targets these.

> **Report what you find.** Tell the user: "The official pipeline scans X with config Y. I'll reproduce that locally."

> **No SDL config?** Some repos have no `sdl.binskim` section at all. In that case, identify what the pipeline publishes as artifacts (e.g., `**\bin\Release\**`) and scan that. Note to the user: "This repo has no explicit BinSkim/SDL configuration. Scanning the published artifact directory as a best-effort approximation. Results may differ from any central SDL portal findings."

### Step 2: Build the Repo

**BinSkim scans built/packaged binaries, not source code.** You must build (and often pack) the repo.

```powershell
# Windows
build.cmd -c Release -pack

# Linux
./build.sh -c Release -pack
```

**What to build depends on pipeline config:**

| Pipeline config | Build command | Scan target |
|---|---|---|
| `scanOutputDirectoryOnly` + publishes `pkgassets` | `build.cmd -c Release -pack` | `artifacts\pkgassets\**` |
| `scanOutputDirectoryOnly` + publishes NuGet packages | `build.cmd -pack` then extract .nupkg | Extracted .nupkg contents |
| Explicit `analyzeTargetGlob` | `build.cmd -c Release` | Use the glob from YAML |
| Autobaselining only | `build.cmd -c Release` | `artifacts\bin\**` (best guess) |

**Extracting .nupkg for scanning** (mirrors `eng/common/sdl/extract-artifact-packages.ps1`):

```powershell
$nupkgDir = Join-Path "artifacts" "packages" "Release" "Shipping"
$extractDir = Join-Path "artifacts" "extracted-for-scan"
Add-Type -AssemblyName System.IO.Compression.FileSystem
Get-ChildItem (Join-Path $nupkgDir "*.nupkg") | ForEach-Object {
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

> Only extract **Shipping** packages unless you have reason to scan NonShipping too.

> **Native builds may require extra setup.** If native code fails to build, you can still scan pre-built native DLLs from the NuGet cache. Many rules (including BA2008) don't need PDBs. See [references/build-prereqs.md](references/build-prereqs.md).
>
> **NuGet cache limitation**: This only covers third-party native blobs consumed via NuGet. It misses first-party native code compiled from source, managed assemblies the repo builds, and pack-only artifacts. For repos where all findings are on NuGet-sourced binaries (e.g., machinelearning's Intel DLLs), this is sufficient. For repos that compile native code from source, a full build is needed.

### Step 3: Run BinSkim

**Preferred: Use the helper script** (from the skill's `scripts/` directory, or provide its full path):

```powershell
$script = Join-Path "plugins" "dotnet-dnceng" "skills" "binskim-scan" "scripts" "Invoke-BinSkimScan.ps1"

# Scan a directory:
& $script -RepoRoot C:\git\machinelearning -ScanDir (Join-Path "artifacts" "pkgassets")

# Filter to portal-reported rules only:
& $script -RepoRoot C:\git\machinelearning -ScanDir (Join-Path "artifacts" "pkgassets") -PortalRulesFrom C:\temp\Results.sarif

# Auto-discover scan targets:
& $script -RepoRoot C:\git\machinelearning
```

**Manual invocation:**

```powershell
# Adjust path to your platform – see binskim-install.md for installation
$binskim = Join-Path $HOME ".binskim" "tools" "net9.0" "linux-x64" "BinSkim"   # Linux
# $binskim = Join-Path $HOME ".binskim" "tools" "net9.0" "win-x64" "BinSkim.exe" # Windows
$targetGlob = Join-Path "artifacts" "pkgassets" "**"
& $binskim analyze $targetGlob --recurse --output binskim-results.sarif --pretty-print --force
```

> **Don't filter to `*.dll` only** — scan `**` and let BinSkim decide what's a PE binary. This catches `.exe` files too.

### Step 4: Analyze Results

```powershell
$sarif = Get-Content -Raw binskim-results.sarif | ConvertFrom-Json
$results = $sarif.runs[0].results
$errors = $results | Where-Object { $_.level -eq 'error' }
$warnings = $results | Where-Object { $_.level -eq 'warning' }
Write-Host "Errors: $($errors.Count), Warnings: $($warnings.Count)"
$errors | Group-Object ruleId | Sort-Object Count -Descending | Format-Table Count, Name
```

**Present results as:**
1. Summary table: rule ID, count, severity
2. Per-binary breakdown for errors
3. For each finding: first-party (built in repo) or third-party (from NuGet)?

### Step 5: Compare with Official Results (if applicable)

If the user provides official results, map findings and flag:
- **Gaps**: findings in official but not local (packaging differences)
- **Extras**: findings local but not official (scanning too broadly, or Guardian filtering)

Local scans are a **superset** — more findings than the portal is expected. Use `-PortalRulesFrom` to filter local results to match portal rules.

## Cross-Platform

BinSkim ships for Windows, Linux (x64, arm64), and macOS (x64):
- Windows: `tools/net9.0/win-x64/BinSkim.exe`
- Linux: `tools/net9.0/linux-x64/BinSkim` (`chmod +x`)
- macOS: `tools/net9.0/osx-x64/BinSkim`

**Each OS build produces different native binaries with potentially different BinSkim findings.** A Windows scan does not cover Linux `.so` or macOS `.dylib` files, and vice versa. If the repo ships native binaries for multiple platforms, scan on each target OS — not just Windows.

Use `build.sh` on Linux/macOS. If the official pipeline only runs BinSkim on Windows legs, flag this as a coverage gap — the pipeline should scan all OS configurations that produce shipped native artifacts.

## Before/After Comparison

To prove a fix works, scan before and after:

```powershell
# Baseline on main, then fix branch
$before = (Get-Content -Raw binskim-before.sarif | ConvertFrom-Json).runs[0].results | Where-Object { $_.level -eq 'error' }
$after  = (Get-Content -Raw binskim-after.sarif  | ConvertFrom-Json).runs[0].results | Where-Object { $_.level -eq 'error' }
Write-Host "Before: $($before.Count) errors, After: $($after.Count) errors"
```

> This requires two full builds. Only use when the user needs proof a fix works.

## Fix Strategies

### Classify the finding first

1. Search the repo for the binary name — is there a project that produces it?
2. Check NuGet packages — is it from a `PackageReference`?
3. Check for `<Content Include="...">` — is it a pre-built file being copied?

### Fix by origin

| Binary origin | Example | Fix approach |
|---|---|---|
| **C++ source** (`.vcxproj`) | EtwClrProfiler.dll | Add compiler/linker flags (e.g., `/guard:cf`) |
| **Pre-built native from NuGet** | Intel MKL/TBB, WiX winterop.dll | Cannot fix here — update package, file upstream, or suppress |
| **Test framework** | xunit.*.dll | Fix scan scope — exclude from shipped artifacts |
| **Managed C# assembly** | Most `.dll` from `.csproj` | BA2008 not applicable (BinSkim skips IL-only) |

> `<ControlFlowGuard>Guard</ControlFlowGuard>` in a `.csproj` does **nothing**. This MSBuild property only works in `.vcxproj` (MSVC C++).

### VMR fix ownership

In the VMR (dotnet/dotnet), look at the SARIF artifact path to find the source sub-repo (e.g., `src/arcade/artifacts/...` means the fix goes to `dotnet/arcade`).

## Anti-Patterns

> Don't scan `artifacts\bin\` if the pipeline uses `scanOutputDirectoryOnly` — you'll get findings from test dependencies that aren't shipped.

> Don't skip the pack step — many shippable binaries only materialize during packing.

> Don't assume the native build is required — scan NuGet-cached DLLs if native build fails locally.

> Don't report NuGet transitive dependency findings as repo issues — if `libSkiaSharp.dll` fails BA2008, that's SkiaSharp's issue.

> Don't be alarmed by extra local findings — use `-PortalRulesFrom` to filter to portal-reported rules. For rules reference and Guardian filtering details, see the **binskim-analysis** skill.

## References

- **Installing BinSkim**: [references/binskim-install.md](references/binskim-install.md)
- **Build prerequisites**: [references/build-prereqs.md](references/build-prereqs.md)
- **Per-repo pipeline configs**: Use the `binskim-analysis` skill for known pipeline names, SDL artifact patterns, and local repro notes per repo
- **Arcade SDL infrastructure**: Use the `binskim-analysis` skill for `configure-sdl-tool.ps1` and `extract-artifact-packages.ps1` details
- **Rules reference and Guardian filtering**: See the **binskim-analysis** skill
