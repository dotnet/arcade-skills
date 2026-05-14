# dotnet/runtime — BinSkim Profile

- **Pipeline YAML**: `eng/pipelines/runtime-official.yml`
- **Official pipeline**: [`dotnet-runtime-official`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=679) (dnceng/internal #679)
- **BinSkim config**: Via 1ES autobaselining (`.config/1espt/PipelineAutobaseliningConfig.yml`)
- **Scan target**: Likely `artifacts/bin/` and installer outputs (via pipeline template defaults)
- **How to reproduce locally**:
  1. Build: `build.cmd -subset clr+libs -c Release` (full) or `build.cmd -subset libs -c Release` (managed only)
  2. Pack: `build.cmd -subset libs -c Release -pack`
  3. Scan: Extract .nupkg files first, then scan the extracted binaries (see `Invoke-BinSkimScan.ps1 -PackagesDir` for automated extraction)
- **Quirks**:
  - Massive repo — full build takes a long time; target specific subsets
  - Ships runtime installers, host binaries, and crossgen output — NuGet scanning alone is insufficient
  - Native CLR components (coreclr, JIT) are the most interesting BinSkim targets
  - No explicit repo-local BinSkim glob — relies on 1ES template defaults
