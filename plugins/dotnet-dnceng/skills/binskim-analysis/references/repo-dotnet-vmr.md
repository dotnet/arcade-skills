# dotnet/dotnet (VMR) — BinSkim Profile

- **Pipeline YAML**: `eng/pipelines/unified-build.yml`
- **Official pipeline**: [`dotnet-unified-build`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1330) (dnceng/internal #1330)
- **BinSkim config**: Via 1ES autobaselining — applied at the VMR level, scans outputs from ALL sub-repos
- **Published artifacts**: Multiple SDL legs, e.g., `drop_VMR_Vertical_Build_Windows_x64_sdl_analysis` (note: `VMR_Vertical_Build`, not `build`)
- **SDL legs**: 9 Windows legs (x64/x86/arm64 + Pgo variants + BuildPass2 + Workloads), plus Linux/macOS legs (which produce 0-byte BinSkim SARIF)
- **⚠️ OS coverage gap**: Linux and macOS SDL legs produce **0-byte** BinSkim SARIF. Native binaries built for those platforms are not scanned. This is confirmed as of build 2950889 (Apr 2026).
- **es-metadata.yml**: 27 separate `es-metadata.yml` files across sub-repos (root + each src/*), each potentially a distinct SDL compliance boundary
- **Known findings (main branch, build 2950889)**:
  - **46 BA2008 findings** across all Windows legs (24 x64, 21 arm64, 1 Pgo_x86)
  - **ALL are foreign/third-party** — ZERO first-party code BA2008 failures
  - By binary: wasm-*.exe (12, binaryen/emsdk), python.exe/python311.dll/pythonw.exe (emsdk), node.exe, sqlite3.dll, libcrypto/libssl (emsdk), libffi-8.dll (emsdk), winterop.dll ×3 (WiX/arcade NonShipping), pgort140.dll (Pgo only)
- **Raw SARIF stats (build 2950889 main)**: 5972 raw findings across 3 rules
  - BA2022: 5475 (`Error_DidNotVerify` on unsigned — all filtered by Guardian)
  - BA2028: 451 (CastGuard on 43 unique first-party native binaries — not SDL-required, filtered)
  - BA2008: 46 (all foreign, these survive filtering to portal)
  - ERR997: 25,809 ExceptionLoadingPdb notifications (PDBs not co-located)
- **Linux scan (local, ELF on Windows)**: All 5 SDL-required BA3xxx rules PASS. BA3031 (SafeStack, not required) fails on 32 binaries.
- **macOS scan**: Not yet done. Can be scanned from any OS (BinSkim analyzes Mach-O by magic bytes) — just pass `*.dylib` or `**` as the target glob. Download macOS build artifacts and scan locally.
- **Sub-repo attribution** (from release/10.0.3xx raw SARIF):
  - vstest: 138 raw findings
  - msbuild: 128 raw findings
  - roslyn: 67 raw findings
  - sdk: 7 raw findings
  - arcade: 6 raw findings (includes the 6 portal winterop.dll hits)
- **How to reproduce locally**: NOT recommended for BinSkim investigation — building the full VMR takes hours. Instead:
  1. Download official SDL artifacts and parse the SARIF files
  2. Download build artifacts (Linux/macOS) and scan extracted natives with BinSkim
  3. For fixes: build the specific sub-repo standalone (e.g., `src/arcade`) and scan that
- **Quirks**:
  - Raw SARIF files can be 50-80MB+ — too large to read into agent context. Use PowerShell to parse
  - Artifact naming uses `VMR_Vertical_Build` prefix, not just `build`
  - Only Windows SDL legs currently produce BinSkim results (macOS/Linux binaries are not scanned because the 1ES template uses Windows-centric glob patterns — this is a pipeline configuration gap, not a BinSkim limitation)
  - Large Pipeline Artifacts require CDN URL metadata fetch — see analysis skill download notes
  - Fixes should target the **source sub-repo** (e.g., `dotnet/arcade`), not the VMR itself
  - Each sub-repo has its own `es-metadata.yml` — SDL requirements may theoretically vary by sub-repo
