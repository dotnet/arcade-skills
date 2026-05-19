# dotnet/dotnet (VMR) — BinSkim Profile

- **Pipeline YAML**: `eng/pipelines/unified-build.yml`
- **Official pipeline**: [`dotnet-unified-build`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1330) (dnceng/internal #1330)
- **Build results URL pattern**: `https://dev.azure.com/dnceng/internal/_build/results?buildId=<id>&view=results`
- **Finding a recent build**: use `ado-dnceng-pipelines_build` with `action=list`, `definitions=[1330]`, `project=internal`, `branchName=refs/heads/main`, `statusFilter=completed`. Pick the most recent `result=Succeeded` to avoid partially-published artifacts.
- **BinSkim config**: Via 1ES autobaselining — applied at the VMR level, scans outputs from ALL sub-repos
- **Published artifacts**: Multiple SDL legs, e.g., `drop_VMR_Vertical_Build_Windows_x64_sdl_analysis` (note: `VMR_Vertical_Build`, not `build`)
- **SDL legs**: 9 Windows legs (x64/x86/arm64 + Pgo variants + BuildPass2 + Workloads), plus Linux/macOS legs (which produce 0-byte BinSkim SARIF). Empirically only ~6 Windows legs contain non-empty BinSkim findings (main 3 + Pgo 3); BuildPass2/3 and Workloads legs are usually empty or contain only BA2024/BA2028 raw entries.
- **Artifact-size sanity check**: the `ado-dnceng-pipelines_artifact action=list` response's `artifactsize` field reflects total *uncompressed* dedup-chunk size. The MCP `download` returns a dedup-compressed zip that is typically 5–20× smaller. Verify by extracting and checking `binskim.sarif` size, not the zip size.
- **⚠️ OS coverage gap**: Linux and macOS SDL legs produce **0-byte** BinSkim SARIF. Native binaries built for those platforms are not scanned. This is confirmed as of build 2950889 (Apr 2026).
- **es-metadata.yml**: 27 separate `es-metadata.yml` files across sub-repos (root + each src/*), each potentially a distinct SDL compliance boundary
- **Known findings (main branch, build 2950889, Apr 2026)**:
  - **46 BA2008 findings** across all Windows legs (24 x64, 21 arm64, 1 Pgo_x86)
  - **ALL are foreign/third-party** — ZERO first-party code BA2008 failures
  - By binary: wasm-*.exe (12, binaryen/emsdk), python.exe/python311.dll/pythonw.exe (emsdk), node.exe, sqlite3.dll, libcrypto/libssl (emsdk), libffi-8.dll (emsdk), winterop.dll ×3 (WiX/arcade NonShipping), pgort140.dll (Pgo only)
- **Known findings (main branch, build 2978061, May 2026)**: same BA2008 pattern (45 hits, same foreign binaries) **plus a new first-party rule firing**:
  - **42 BA2007 findings** survive Guardian filtering, all on two WPF native mixed-mode binaries: `System.Printing.dll` and `DirectWriteForwarder.dll`. The 42 hits = 2 binaries × ~21 packaging paths (Shipping/NonShipping nupkg, symbols nupkg, SDK zip, Pgo SDK zip, across win-x64/arm64/x86)
  - Fix owner: `dotnet/wpf` (these binaries are built there)
  - First-party WPF native binaries are a recurring source of newly-surviving findings — when a new rule fires post-filter, check WPF before assuming a Guardian policy change
- **Raw SARIF stats (build 2950889 main)**: 5972 raw findings across 3 rules
  - BA2022: 5475 (`Error_DidNotVerify` on unsigned — all filtered by Guardian)
  - BA2028: 451 (CastGuard on 43 unique first-party native binaries — not SDL-required, filtered)
  - BA2008: 46 (all foreign, these survive filtering to portal)
  - ERR997: 25,809 ExceptionLoadingPdb notifications (PDBs not co-located)
- **Linux scan (local, ELF on Windows)**: All 5 SDL-required BA3xxx rules PASS. BA3031 (SafeStack, not required) fails on 32 binaries.
- **macOS scan (local, Mach-O on Windows)**: 35 unique binaries (14 executables + 21 dylibs) per arch. BA5001 (PIE): 14 executables pass, dylibs correctly NotApplicable. BA5002 (No exec stack): all 35 pass. **Zero failures** on both arm64 and x64. Foreign binaries (node, python3) also pass.
- **Sub-repo attribution** (from release/10.0.3xx raw SARIF):
  - vstest: 138 raw findings
  - msbuild: 128 raw findings
  - roslyn: 67 raw findings
  - sdk: 7 raw findings
  - arcade: 6 raw findings (includes the 6 portal winterop.dll hits)
- **How to reproduce locally**: NOT recommended for BinSkim investigation — building the full VMR takes hours. Instead:
  1. Download official SDL artifacts and parse the SARIF files (use the MCP HTTP workaround in `SKILL.md` if the agent host suppresses the embedded zip)
  2. Download build artifacts (Linux/macOS) and scan extracted natives with BinSkim
  3. For fixes: build the specific sub-repo standalone (e.g., `src/arcade`) and scan that
- **Recommended download workflow** (avoids `az login` hangs):
  1. `ado-dnceng-pipelines_artifact action=list` to enumerate all `*sdl_analysis` artifacts and their sizes
  2. Skip the 0-byte non-Windows artifacts up front; download only the 12 Windows legs that produce real SARIF (3 main + 3 Pgo + 3 BuildPass2 + 3 BuildPass3, plus `Asset_Registry_Publish`)
  3. Use the MCP-HTTP base64 path documented in `SKILL.md` — total download is only ~10 MB of zips and extracts to ~150 MB of SARIF
  4. Parse with PowerShell: walk all `binskim.sarif` files for raw, and the BinSkim run inside each `Results.sarif` for Guardian-filtered. Aggregate by `ruleId` and binary path
- **Quirks**:
  - Raw SARIF files can be 50-80MB+ — too large to read into agent context. Use PowerShell to parse
  - Artifact naming uses `VMR_Vertical_Build` prefix, not just `build`
  - Only Windows SDL legs currently produce BinSkim results (macOS/Linux binaries are not scanned because the 1ES template uses Windows-centric glob patterns — this is a pipeline configuration gap, not a BinSkim limitation)
  - Large Pipeline Artifacts require CDN URL metadata fetch — see analysis skill download notes
  - Fixes should target the **source sub-repo** (e.g., `dotnet/arcade`), not the VMR itself
  - Each sub-repo has its own `es-metadata.yml` — SDL requirements may theoretically vary by sub-repo
