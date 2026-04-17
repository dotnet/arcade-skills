# dotnet/aspnetcore — BinSkim Profile

- **Pipeline YAML**: `eng/pipelines/aspnetcore-ci.yml` or `azure-pipelines.yml`
- **Official pipeline**: Look up in AzDO (may be in DevDiv org)
- **BinSkim config**: Check for `sdl.binskim` section
- **How to reproduce locally**:
  1. Build: `build.cmd -c Release`
  2. Pack: `build.cmd -c Release -pack`
  3. Scan: `artifacts\packages\` extracted contents
- **Quirks**: Ships shared framework components — scanning the shared framework output is important
