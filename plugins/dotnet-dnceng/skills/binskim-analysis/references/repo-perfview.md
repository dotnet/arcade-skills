# microsoft/perfview — BinSkim Profile

- **Pipeline YAML**: `.ado.yml` (root), templates in `.pipelines/`
- **Official pipeline**: In devdiv/DevDiv org (not dnceng)
- **BinSkim config**: **None found** — no explicit BinSkim config, no `eng/common/sdl/`, no `PipelineAutobaseliningConfig.yml`
- **NOT an arcade repo** — uses raw `msbuild /restore /m` via `build.cmd`, output in `src\bin\` not `artifacts\`
- **Scan target**: Published artifacts are `PerfViewBinaries-Release` from `$(build.artifactstagingdirectory)` (copies `**\bin\Release\**`)
- **Published artifacts**: Built binaries only — no NuGet packages, no installers
- **es-metadata.yml**: `org: nettel`, `path: PerfView`, `isProduction: true`
- **Known findings (central portal)**: BA2027 and BA2004 (different required rules from dotnet repos due to `nettel` org):
  - `EtwClrProfiler.dll` (BA2027 × 22 instances) — **C++ source in repo** (`src/EtwClrProfiler/`); BA2027 (EnableSourceLink) on native C++ binaries requires `/d1sourcelink` or PDB embedding approach rather than the .NET SourceLink project property — may warrant an exception instead
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
