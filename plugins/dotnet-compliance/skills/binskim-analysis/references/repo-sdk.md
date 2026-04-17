# dotnet/sdk — BinSkim Profile

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
