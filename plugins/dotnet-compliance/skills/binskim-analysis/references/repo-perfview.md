# microsoft/perfview — BinSkim Profile

- **Pipeline YAML**: `.ado.yml` (root), templates in `.pipelines/`
- **Official pipeline**: In devdiv/DevDiv org (not dnceng)
- **BinSkim config**: **None found** — no explicit BinSkim config, no `eng/common/sdl/`, no `PipelineAutobaseliningConfig.yml`
- **NOT an arcade repo** — uses raw `msbuild /restore /m` via `build.cmd`, output in `src\bin\` not `artifacts\`
- **Scan target**: Published artifacts are `PerfViewBinaries-Release` from `$(build.artifactstagingdirectory)` (copies `**\bin\Release\**`)
- **Published artifacts**: Built binaries only — no NuGet packages, no installers
- **es-metadata.yml**: `org: nettel`, `path: PerfView`, `isProduction: true`
- **Known findings (central portal)**: BA2004 and BA2027 (neither is SDL-required at company level — no 10203 mapping — but appear in the portal as informational findings)
- **Native code**: Yes — `src/EtwClrProfiler/ETWClrProfilerX64.vcxproj` and `ETWClrProfilerX86.vcxproj` (requires MSVC)
- **How to reproduce locally**:
  1. Build: `build.cmd` (or `msbuild /restore /m /p:Configuration=Release`)
  2. Scan: `BinSkim.exe analyze "src\bin\Release\**" --recurse --output results.sarif --pretty-print --force`
- **Quirks**:
  - Non-arcade: no `eng/common/sdl/`, no `artifacts\` directory convention
  - The repo is `microsoft/perfview`, not `dotnet/perfview`
  - Pipeline is in devdiv/DevDiv AzDO org, not dnceng
  - `nettel` service tree org — BA2004 and BA2027 appear in the portal but neither is 10203-mapped (not SDL-required at company level). The portal shows informational findings alongside required ones.

## Pipeline architecture

- **PerfView-Mirror** (def 21270, devdiv/DevDiv): Triggers on GitHub repo changes. Mirrors source to internal ADO repo (`DevDiv/perfview`). Runs SDL **sources** analysis only (antimalware, armory, psscriptanalyzer) — **no BinSkim**. YAML: `.pipelines/mirror.yml`.
- **PerfView-Official** (def 20533, devdiv/DevDiv): Runs on internal ADO repo. **Scheduled weekly** (Tuesdays 9AM UTC, "Weekly Unsigned Build"). YAML: `.ado.yml`. BinSkim is injected by 1ES template — not explicitly in the YAML. Publishes `PerfViewBinaries`, `Symbols`, `Packages`, `SupportFiles`, and `drop_Build_perfview_build_sdl_analysis` (contains BinSkim SARIF results).

The weekly schedule means there can be up to a week's delay between a GitHub fix landing and the first official build that includes it.

## Known findings (as of April 2025, build 13906225)

Two BinSkim scans run per build (one per build configuration). The SDL binary analysis artifact (`drop_Build_perfview_build_sdl_analysis`) contains two SARIF files under `Build PerfView\binskim\001\` and `002\`.

### BA2004 (not SDL-required): `EtwClrProfilerSigning.dll` — managed signing stub

**BA2004** (`Error_Managed`) fires on `EtwClrProfilerSigning.dll`, which is a **managed** .NET Framework 4.6.2 stub project (`src/EtwClrProfilerSigning/EtwClrProfilerSigning.csproj`). This project has **no source files** — it exists purely for MicroBuild signing of the native EtwClrProfiler DLLs. The `Error_Managed` message with argument "Unknown" indicates BinSkim cannot determine the compiler version.

BA2004 (EnableSecureSourceCodeHashing) has **no 10203 mapping** — it is not SDL-required at the company level.

This violation is **not fixed** by [commit 3d1f2f7](https://github.com/microsoft/perfview/commit/3d1f2f7eee577596b8528517d9370f8e16c48541) (April 2025), which added Spectre mitigations and linker optimizations to the **native** C++ vcxproj files. The managed signing wrapper is a separate project.

### BA2027 (not SDL-required): `EtwClrProfiler.dll` — missing SourceLink

**BA2027** (`Warning`) fires on the native `EtwClrProfiler.dll` (both x86 and x64). Native C++ projects need `Microsoft.Build.Tasks.Git` + SourceLink NuGet packages and `/d1sourcelink` compiler flag to embed source info in PDBs — the standard .NET `<EnableSourceLink>` project property does not work for C++ projects.

BA2027 (EnableSourceLink) has **no 10203 mapping** — it is not SDL-required at the company level.

This violation is **not addressed** by commit 3d1f2f7.

### Non-SDL-required warnings on `EtwClrProfiler.dll`

| Rule | Description | Likely status after commit 3d1f2f7 |
|------|-------------|-------------------------------------|
| BA6004 | SDLC disabled for Release | Should be **fixed** (added WholeProgramOptimization, LTCG) |
| BA6005 | Linker optimizations missing | Should be **fixed** (added COMDAT folding, OptimizeReferences) |
| BA6006 | Compiler optimizations | Should be **fixed** (added Spectre mitigations) |

### Summary: what commit 3d1f2f7 fixes and doesn't fix

None of these violations are SDL-required (no 10203 mapping). The commit improved security posture but PerfView had **zero SDL-required BinSkim violations** before and after.

| Violation | Binary | Fixed by 3d1f2f7? | Why |
|-----------|--------|--------------------|-----|
| **BA2004** (not required) | `EtwClrProfilerSigning.dll` (managed) | ❌ No | Managed stub — native C++ changes don't apply |
| **BA2027** (not required) | `EtwClrProfiler.dll` (native) | ❌ No | SourceLink not added to C++ project |
| BA6004 (not required) | `EtwClrProfiler.dll` (native) | ✅ Yes | Added LTCG/WholeProgramOptimization |
| BA6005 (not required) | `EtwClrProfiler.dll` (native) | ✅ Yes | Added COMDAT folding, OptimizeReferences |
| BA6006 (not required) | `EtwClrProfiler.dll` (native) | ✅ Yes | Added Spectre mitigations |
