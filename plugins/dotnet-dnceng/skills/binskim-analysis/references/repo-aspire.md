# dotnet/aspire — BinSkim Profile

- **Pipeline YAML**: `eng/pipelines/azure-pipelines.yml`
- **Official pipeline**: [`dotnet-aspire`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=1309) (dnceng/internal #1309)
- **BinSkim config**: Via 1ES autobaselining
- **Non-NuGet artifacts**: CLI zips/tarballs (`aspire-cli-*.zip`), VS Code extension (`.vsix`), WinGet manifests, Homebrew casks
- **How to reproduce locally**: Build + scan `artifacts\bin\` outputs
- **Coverage concern**: CLI archives and VSIX contain binaries that may not be in NuGet packages
