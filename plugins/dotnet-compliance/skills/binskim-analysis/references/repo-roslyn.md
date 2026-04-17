# dotnet/roslyn — BinSkim Profile

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
