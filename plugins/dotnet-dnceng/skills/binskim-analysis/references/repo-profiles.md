# Per-Repo BinSkim Profiles

Known BinSkim configurations for major dotnet product repositories. These profiles document where the pipeline config lives, what it scans, and quirks to watch for.

## dotnet/machinelearning

- **Pipeline YAML**: `build/vsts-ci.yml`
- **Official pipeline**: [`dotnet-machinelearning-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1110) (dnceng/internal #1110)
- **BinSkim config**: `sdl.binskim.enabled: true`, `scanOutputDirectoryOnly: true`
- **Scan target**: Published `pkgassets` artifact from `artifacts/pkgassets/`
- **Published artifacts**: `pkgassets` (native blobs for NuGet redistribution)
- **Known findings (central portal)**: BA2008 on 5 third-party Intel native DLLs:
  - `MklImports.dll` (from MlNetMklDeps NuGet, built externally with Intel MKL Custom Builder)
  - `onedal_core.1.dll`, `onedal_thread.1.dll`, `tbb12.dll`, `tbbmalloc.dll` (Intel oneDAL/TBB)
- **Additional findings (raw SARIF, filtered by Guardian SDL policy before reaching portal)**:
  - BA2028 (EnableCastGuard, Error): 7 first-party DLLs — filtered because this rule's SDL policy is scoped to specific orgs
  - BA2024/BA2025/BA2026 (Warning): all 8 native DLLs — filtered (no SDL policy mapping)
  - BA2004, BA2027 (Error/Warning): MklImports.dll only — filtered (no SDL policy mapping)
  - BA6004, BA6006 (optimization hints): MklImports.dll only — not security rules
- **Guardian config note**: BinSkim is NOT in the break policy `IncludeTools` — it can never fail the build. The `break/001/options.json` only includes credscan, fxcop, roslynanalyzers.
- **How to reproduce locally**:
  1. Build native: `build.cmd -c Release -projects src\Native\Native.proj /p:CopyPackageAssets=true` (requires MSVC + Spectre libs)
  2. Scan: `BinSkim.exe analyze "artifacts\pkgassets\**\*.dll" --recurse --output results.sarif --pretty-print --force`
  3. Or scan NuGet cache directly: find `mlnetmkldeps`, `inteldal.redist.win-x64`, `inteltbb.devel.win`/`inteltbb.redist.win` under `$env:USERPROFILE\.nuget\packages\`
- **Quirks**:
  - Native build requires git submodule init (`git submodule update --init`)
  - Native build requires MSVC Spectre-mitigated libraries (VS individual component)
  - `MklImports.dll` is NOT built in this repo — it's externally pre-built and consumed via NuGet (see `docs/building/MlNetMklDeps/README.md`)
  - Tracked tech debt: issue #5805 (MKL PDB not included with packages), in `.github/health-baseline.md`
- **Coverage concern**: Only scans `pkgassets/` — test/sample outputs and managed DLLs are not scanned

## dotnet/dotnet (VMR — Virtual Monolithic Repository)

- **Pipeline YAML**: `eng/pipelines/unified-build.yml`
- **Official pipeline**: [`dotnet-unified-build`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1330) (dnceng/internal #1330)
- **BinSkim config**: Via 1ES autobaselining — applied at the VMR level, scans outputs from ALL sub-repos
- **Published artifacts**: Multiple SDL legs, e.g., `drop_VMR_Vertical_Build_Windows_x64_sdl_analysis` (note: `VMR_Vertical_Build`, not `build`)
- **SDL legs**: 6 Windows legs (x64/x86/arm64, possibly Release/Debug), plus Linux/macOS legs (produce 0-byte BinSkim SARIF — Windows-only tool)
- **es-metadata.yml**: 27 separate `es-metadata.yml` files across sub-repos (root + each src/*), each potentially a distinct SDL compliance boundary
- **Known findings (central portal, release branch)**: 6 BA2008 findings, all on `winterop.dll` (WiX toolset native DLL)
  - `winterop.dll` lives in `src/arcade/artifacts/` — pre-built native from `Microsoft.Signed.Wix` NuGet package
  - Cannot be fixed in the VMR or dotnet/arcade — fix must come from WiX upstream
- **Known findings (central portal, main branch)**: Additional BA2021 findings on Roslyn language server DLLs
- **Raw SARIF stats**: 346+ findings across 10+ rules (release), 3,100+ on main — overwhelming majority filtered by Guardian
- **Sub-repo attribution** (from release/10.0.3xx raw SARIF):
  - vstest: 138 raw findings
  - msbuild: 128 raw findings
  - roslyn: 67 raw findings
  - sdk: 7 raw findings
  - arcade: 6 raw findings (includes the 6 portal winterop.dll hits)
- **How to reproduce locally**: NOT recommended for BinSkim investigation — building the full VMR takes hours. Instead:
  1. Download official SDL artifacts and parse the SARIF files
  2. For fixes: build the specific sub-repo standalone (e.g., `src/arcade`) and scan that
- **Quirks**:
  - Raw SARIF files can be 50-80MB+ — too large to read into agent context. Use PowerShell to parse
  - Artifact naming uses `VMR_Vertical_Build` prefix, not just `build`
  - Only Windows SDL legs produce BinSkim results
  - Linux/macOS legs may fail to download if authentication isn't configured (internal feeds)
  - Fixes should target the **source sub-repo** (e.g., `dotnet/arcade`), not the VMR itself
  - Each sub-repo has its own `es-metadata.yml` — SDL requirements may theoretically vary by sub-repo

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
- **es-metadata.yml**: `org: devdiv`, `path: DevDiv\NET Runtime\Diagnostics\SDL`, `isProduction: true`
- **Known findings (central portal)**: BA2009 on pre-built test fixture DLLs:
  - `mockclr_amd64.dll`, `mockclr_arm64.dll`, `mockclr_i386.dll`, `mockdac.dll`, `mockdbi.dll`, `mocksos.dll`
  - These are pre-built test binaries in `src/tests/Microsoft.SymbolStore.UnitTests/TestBinaries/` — not compiled from source
  - Fix: exclude from scan scope or suppress/baseline (test fixtures shouldn't be in shipped artifacts)
- **How to reproduce locally**: Build + scan `artifacts\bin\` outputs
- **Coverage concern**: Release drops and bundled tools may contain binaries beyond NuGet output

## microsoft/perfview

- **Pipeline YAML**: `.ado.yml` (root), templates in `.pipelines/`
- **Official pipeline**: In devdiv/DevDiv org (not dnceng)
- **BinSkim config**: **None found** — no explicit BinSkim config, no `eng/common/sdl/`, no `PipelineAutobaseliningConfig.yml`
- **NOT an arcade repo** — uses raw `msbuild /restore /m` via `build.cmd`, output in `src\bin\` not `artifacts\`
- **Scan target**: Published artifacts are `PerfViewBinaries-Release` from `$(build.artifactstagingdirectory)` (copies `**\bin\Release\**`)
- **Published artifacts**: Built binaries only — no NuGet packages, no installers
- **es-metadata.yml**: `org: nettel`, `path: PerfView`, `isProduction: true`
- **Known findings (central portal)**: BA2027 and BA2004 (different required rules from dotnet repos due to `nettel` org):
  - `EtwClrProfiler.dll` (BA2027 × 22 instances) — **C++ source in repo** (`src/EtwClrProfiler/`), fixable with compiler flags
  - `xunit.*.dll` (5 DLLs, BA2027 + BA2004) — third-party test framework, shouldn't be in shipped artifacts
  - `Microsoft.Diagnostics.Tracing.TraceEvent.AutomatedAnalysis.Analyzers.dll` (BA2004) — first-party managed assembly
- **Native code**: Yes — `src/EtwClrProfiler/ETWClrProfilerX64.vcxproj` and `ETWClrProfilerX86.vcxproj` (requires MSVC)
- **How to reproduce locally**:
  1. Build: `build.cmd` (or `msbuild /restore /m /p:Configuration=Release`)
  2. Scan: `BinSkim.exe analyze "src\bin\Release\**" --recurse --output results.sarif --pretty-print --force`
- **Quirks**:
  - Non-arcade: no `eng/common/sdl/`, no `artifacts\` directory convention
  - The repo is `microsoft/perfview`, not `dotnet/perfview`
  - Pipeline is in devdiv/DevDiv AzDO org, not dnceng
  - `nettel` service tree org has different SDL requirements than `devdiv` — BA2027 and BA2004 are required here but not for most dotnet/* repos
  - EtwClrProfiler.dll is one of the **rare cases where a portal-reported finding is fixable** — it's C++ source compiled in the repo

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
