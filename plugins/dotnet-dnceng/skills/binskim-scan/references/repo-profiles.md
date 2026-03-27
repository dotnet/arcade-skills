# Per-Repo BinSkim Profiles

Known BinSkim configurations for major dotnet product repositories. These profiles document where the pipeline config lives, what it scans, and quirks to watch for.

## dotnet/machinelearning

- **Pipeline YAML**: `build/vsts-ci.yml`
- **Official pipeline**: [`dotnet-machinelearning-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1110) (dnceng/internal #1110)
- **BinSkim config**: `sdl.binskim.enabled: true`, `scanOutputDirectoryOnly: true`
- **Scan target**: Published `pkgassets` artifact from `artifacts/pkgassets/`
- **Published artifacts**: `pkgassets` (native blobs for NuGet redistribution)
- **Known findings (central)**: BA2008 on 5 third-party Intel native DLLs:
  - `MklImports.dll` (from MlNetMklDeps NuGet, built externally with Intel MKL Custom Builder)
  - `onedal_core.1.dll`, `onedal_thread.1.dll`, `tbb12.dll`, `tbbmalloc.dll` (Intel oneDAL/TBB)
- **Known findings (raw SARIF, filtered by Guardian before reaching portal)**:
  - BA2028 (EnableCastGuard, Error): 7 first-party DLLs — LdaNative, FastTreeNative, CpuMathNative, SymSgdNative, MklProxyNative, MatrixFactorizationNative, OneDalNative
  - BA2024/BA2025/BA2026 (Warning): all 8 native DLLs (first-party + MklImports)
  - BA2004, BA2027 (Error/Warning): MklImports.dll only
  - BA6004, BA6006 (optimization hints): MklImports.dll only
- **Guardian config note**: BinSkim is NOT in the break policy `IncludeTools` — it can never fail the build. The `break/001/options.json` only includes credscan, fxcop, roslynanalyzers.
- **How to reproduce locally**:
  1. Build native: `build.cmd -c Release -projects src\Native\Native.proj /p:CopyPackageAssets=true` (requires MSVC + Spectre libs)
  2. Scan: `BinSkim.exe analyze "artifacts\pkgassets\**\*.dll" --recurse --output results.sarif --pretty-print --force`
  3. Or scan NuGet cache directly: find `mlnetmkldeps`, `inteldal.devel.win-x64`, `inteltbb.devel.win` under `$env:USERPROFILE\.nuget\packages\`
- **Quirks**:
  - Native build requires git submodule init (`git submodule update --init`)
  - Native build requires MSVC Spectre-mitigated libraries (VS individual component)
  - `MklImports.dll` is NOT built in this repo — it's externally pre-built and consumed via NuGet (see `docs/building/MlNetMklDeps/README.md`)
  - Tracked tech debt: issue #5805 (MKL PDB not included with packages), in `.github/health-baseline.md`
- **Coverage concern**: Only scans `pkgassets/` — test/sample outputs and managed DLLs are not scanned

## dotnet/sdk

- **Pipeline YAML**: `.vsts-ci.yml` (CI/official), `.vsts-pr.yml` (PR validation — no SDL)
- **Official pipeline**: Look up in AzDO (may be in DevDiv org)
- **BinSkim config**: `sdl.binskim.enabled: true`, explicit `analyzeTargetGlob`
- **Scan target**: Explicit glob — `artifacts\bin\**\*.dll`, `artifacts\bin\**\*.exe`, plus `eng\**\*.props`
- **Exclusions**: Known third-party DLLs: `msdia140.dll`, `pgort140.dll`, `capstone.dll`, and others
- **How to reproduce locally**:
  1. Build: `build.cmd -c Release`
  2. Scan: Use the exact glob from `.vsts-ci.yml` `analyzeTargetGlob` value
- **Quirks**:
  - Most explicit BinSkim config of any dotnet repo — fine-grained include/exclude glob
  - Ships MSI installers and zip archives in addition to NuGet — these contain binaries not covered by NuGet-only scanning

## dotnet/runtime

- **Pipeline YAML**: `eng/pipelines/runtime-official.yml`
- **Official pipeline**: [`dotnet-runtime-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=679) (dnceng/internal #679)
- **BinSkim config**: Via 1ES autobaselining (`.config/1espt/PipelineAutobaseliningConfig.yml`)
- **Scan target**: Likely `artifacts/bin/` and installer outputs (via pipeline template defaults)
- **How to reproduce locally**:
  1. Build: `build.cmd -subset clr+libs -c Release` (full) or `build.cmd -subset libs -c Release` (managed only)
  2. Pack: `build.cmd -subset libs -c Release -pack`
  3. Scan: `BinSkim.exe analyze "artifacts\packages\Release\Shipping\*.nupkg"` (extract first)
- **Quirks**:
  - Massive repo — full build takes a long time; target specific subsets
  - Ships runtime installers, host binaries, and crossgen output — NuGet scanning alone is insufficient
  - Native CLR components (coreclr, JIT) are the most interesting BinSkim targets
  - No explicit repo-local BinSkim glob — relies on 1ES template defaults

## dotnet/roslyn

- **Pipeline YAML**: `azure-pipelines-official.yml`
- **Official pipeline**: [`dotnet-roslyn-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=327) (dnceng/internal #327)
- **BinSkim config**: Pipeline-level via Guardian with `-ArtifactToolsList @("binskim")`
- **Scan target**: `VSSetup` drop (installer VSIXes) and `PackageArtifacts` (NuGet packages)
- **How to reproduce locally**:
  1. Build: `build.cmd -c Release`
  2. Pack: `build.cmd -c Release -pack`
  3. Scan NuGet packages and/or VSIX contents
- **Quirks**:
  - Publishes VSSetup/VSIX artifacts — these contain binaries that NuGet scanning misses
  - Has guardian suppression entries in pipeline YAML

## dotnet/aspnetcore

- **Pipeline YAML**: `eng/pipelines/aspnetcore-ci.yml` or `azure-pipelines.yml`
- **Official pipeline**: Look up in AzDO (may be in DevDiv org)
- **BinSkim config**: Check for `sdl.binskim` section
- **How to reproduce locally**:
  1. Build: `build.cmd -c Release`
  2. Pack: `build.cmd -c Release -pack`
  3. Scan: `artifacts\packages\` extracted contents
- **Quirks**: Ships shared framework components — scanning the shared framework output is important

## dotnet/aspire

- **Pipeline YAML**: `eng/pipelines/azure-pipelines.yml`
- **Official pipeline**: [`dotnet-aspire`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1309) (dnceng/internal #1309)
- **BinSkim config**: Via 1ES autobaselining
- **Non-NuGet artifacts**: CLI zips/tarballs (`aspire-cli-*.zip`), VS Code extension (`.vsix`), WinGet manifests, Homebrew casks
- **How to reproduce locally**: Build + scan `artifacts\bin\` outputs
- **Coverage concern**: CLI archives and VSIX contain binaries that may not be in NuGet packages

## dotnet/diagnostics

- **Pipeline YAML**: `eng/pipelines/build.yml`
- **Official pipeline**: [`dotnet-diagnostics`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=528) (dnceng/internal #528)
- **BinSkim config**: Via 1ES autobaselining
- **Published artifacts**: Build artifacts from `artifacts/bin/`, release drop `DiagnosticsRelease`, `BundledTools`
- **How to reproduce locally**: Build + scan `artifacts\bin\` outputs
- **Coverage concern**: Release drops and bundled tools may contain binaries beyond NuGet output

## microsoft/perfview

- **Pipeline YAML**: `.ado.yml` (root), templates in `.pipelines/`
- **BinSkim config**: **None found** — no explicit BinSkim config, no `eng/common/sdl/`, no `PipelineAutobaseliningConfig.yml`
- **NOT an arcade repo** — uses raw `msbuild /restore /m` via `build.cmd`, output in `src\bin\` not `artifacts\`
- **Scan target**: Published artifacts are `PerfViewBinaries-Release` from `$(build.artifactstagingdirectory)` (copies `**\bin\Release\**`)
- **Published artifacts**: Built binaries only — no NuGet packages, no installers
- **Native code**: Yes — `src/EtwClrProfiler/ETWClrProfilerX64.vcxproj` and `ETWClrProfilerX86.vcxproj` (requires MSVC)
- **How to reproduce locally**:
  1. Build: `build.cmd` (or `msbuild /restore /m /p:Configuration=Release`)
  2. Scan: `BinSkim.exe analyze "src\bin\Release\**" --recurse --output results.sarif --pretty-print --force`
- **Quirks**:
  - Non-arcade: no `eng/common/sdl/`, no `artifacts\` directory convention
  - The repo is `microsoft/perfview`, not `dotnet/perfview`
  - If BinSkim isn't configured in the pipeline, findings may only come from org-level 1ES defaults (if any)
  - No baseline suppression file found — all findings would be new

## Discovering New Repos

For repos not listed above:

1. Search for `binskim` in pipeline YAML files:
   ```powershell
   Get-ChildItem -Recurse -Include "*.yml","*.yaml" | Select-String -Pattern "binskim" -SimpleMatch
   ```
2. Check `.config/1espt/PipelineAutobaseliningConfig.yml` for autobaselining
3. Check `eng/common/sdl/` for arcade SDL infrastructure (most dotnet repos share this)
4. Look for `BinskimAdditionalRunConfigParams` for custom exclusions
5. Identify all `PublishPipelineArtifact` steps to understand what's scanned
