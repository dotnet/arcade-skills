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
- **Known findings (local scan)**: None. Repo is 100% managed C# -- no native PE binaries, no `.vcxproj` files, no pre-built native DLLs.
- **BinSkim auto-baselining**: Enabled (binary/binskim last modified 2025-01-10)
- **Guardian baselines**: `.config/guardian/.gdnbaselines` contains only a credscan entry -- no BinSkim baselines needed
- **Post-build SDL**: `SDLValidationParameters.enable: false` -- SDL runs via 1ES template natively, not post-build
- **How to reproduce locally**:
  1. Build: `build.cmd -c Release -pack -ci`
  2. Scan: `Invoke-BinSkimScan.ps1 -RepoRoot C:\git\dotnet\extensions` (auto-discovers Shipping nupkgs, extracts, scans)
  3. Expected: 0 findings (742 DLL/EXE files scanned, all managed = NotApplicable for BA2008/BA2009/BA2021)
- **VSIX note**: The `VSIXArtifacts` publish is an Azure DevOps extension for AI Evaluation Reporting (`src/Libraries/Microsoft.Extensions.AI.Evaluation.Reporting/TypeScript/azure-devops-report/`). This is a TypeScript/JS web extension -- no native binaries. The VSIX is included in `GDN_EXTRACT_FILTER` for scanning.
- **Quirks**:
  - The `Microsoft.Extensions.AI.Evaluation.Console` package contains self-contained publish output (178 files per TFM) including managed apphost `.exe` stubs -- these are not native PE binaries and BinSkim correctly skips them
  - Build requires `build.cmd -restore` first if toolset has not been restored (arcade SDK version must match)
  - No native code in this repo at all -- BinSkim is effectively a no-op but runs as part of standard SDL compliance
