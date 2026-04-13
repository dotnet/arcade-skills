# dotnet/dotnet (VMR) — BinSkim Profile

- **Pipeline YAML**: `eng/pipelines/unified-build.yml`
- **Official pipeline**: [`dotnet-unified-build`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1330) (dnceng/internal #1330)
- **BinSkim config**: Via 1ES autobaselining — applied at the VMR level, scans outputs from ALL sub-repos
- **Published artifacts**: Multiple SDL legs, e.g., `drop_VMR_Vertical_Build_Windows_x64_sdl_analysis` (note: `VMR_Vertical_Build`, not `build`)
- **SDL legs**: 6 Windows legs (x64/x86/arm64, possibly Release/Debug), plus Linux/macOS legs (which produce 0-byte BinSkim SARIF because the official pipeline only runs BinSkim on Windows legs)
- **⚠️ OS coverage gap**: Linux and macOS SDL legs do not produce BinSkim results. Native binaries built for those platforms (e.g., Linux `.so` files, macOS `.dylib` files) are not scanned. This is a pipeline gap that should be fixed if those platforms ship native binaries.
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
