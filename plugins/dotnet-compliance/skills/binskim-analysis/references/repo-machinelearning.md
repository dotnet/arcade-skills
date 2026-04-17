# dotnet/machinelearning — BinSkim Profile

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
