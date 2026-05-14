# dotnet/extensions -- BinSkim Profile

- **Pipeline YAML**: `azure-pipelines.yml`
- **Official pipeline**: Pipeline definition #179 (from PipelineAutobaseliningConfig.yml)
- **1ES template**: `v1/1ES.Official.PipelineTemplate.yml@1ESPipelineTemplates`
- **BinSkim config**: Via 1ES template defaults + auto-baselining. No explicit `sdl.binskim` section.
  - Feature flag: `binskimScanAllExtensions: true`
  - `GDN_EXTRACT_TOOLS: 'binskim,bandit,roslynanalyzers'`
  - `GDN_EXTRACT_FILTER: 'f|**/*.zip;f|**/*.nupkg;f|**/*.vsix;f|**/*.cspkg;f|**/*.sfpkg;f|**/*.package'`
- **Published artifacts**: `PackageArtifacts_Windows` (NuGet packages from `artifacts/packages`), `VSIXArtifacts` (Azure DevOps extension from `artifacts/VSIX`)
- **es-metadata.yml**: `org: devdiv`, `path: DevDiv\ASP.NET Core`, `isProduction: true`
- **Known findings (local scan)**: None. Repo is 100% managed C# -- no native PE binaries, no `.vcxproj` files, no pre-built native DLLs. BA2008 explicitly skips IL-only assemblies (NotApplicable). BA2009 and BA2021 do evaluate IL-only assemblies but are arguably bugs in BinSkim -- DYNAMICBASE (BA2009) and W+X section flags (BA2021) are meaningless for IL-only code where the CLR/JIT controls execution. In practice, the C# compiler sets DYNAMICBASE and does not produce W+X sections, so managed assemblies pass these rules -- but the checks are not security-meaningful for IL.
- **BinSkim auto-baselining**: Enabled (binary/binskim last modified 2025-01-10)
- **Guardian baselines**: `.config/guardian/.gdnbaselines` contains only a credscan entry -- no BinSkim baselines needed
- **Post-build SDL**: `SDLValidationParameters.enable: false` -- SDL runs via 1ES template natively, not post-build
- **How to reproduce locally**:
  1. Build: `build.cmd -c Release -pack -ci`
  2. Scan: `Invoke-BinSkimScan.ps1 -RepoRoot C:\git\dotnet\extensions` (auto-discovers Shipping nupkgs, extracts, scans)
  3. Expected: 0 findings (742 DLL/EXE files scanned; BA2008 skips IL-only as NotApplicable; BA2009/BA2021 evaluate managed assemblies but all pass)
- **VSIX note**: The `VSIXArtifacts` publish is an Azure DevOps extension for AI Evaluation Reporting (`src/Libraries/Microsoft.Extensions.AI.Evaluation.Reporting/TypeScript/azure-devops-report/`). This is a TypeScript/JS web extension -- no native binaries. The VSIX is included in `GDN_EXTRACT_FILTER` for scanning.
- **Quirks**:
  - The `Microsoft.Extensions.AI.Evaluation.Console` package contains self-contained publish output (178 files per TFM) including managed apphost `.exe` stubs -- these are not native PE binaries and BinSkim correctly skips them
  - Build requires `build.cmd -restore` first if toolset has not been restored (arcade SDK version must match)
  - No native code in this repo at all -- BinSkim is effectively a no-op but runs as part of standard SDL compliance
