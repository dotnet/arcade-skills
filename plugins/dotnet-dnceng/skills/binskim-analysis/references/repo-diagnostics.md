# dotnet/diagnostics — BinSkim Profile

- **Pipeline YAML**: `eng/pipelines/build.yml`
- **Official pipeline**: [`dotnet-diagnostics`](https://dev.azure.com/dnceng/internal/_build/definition?definitionId=528) (dnceng/internal #528)
- **BinSkim config**: Via 1ES autobaselining
- **Published artifacts**: Build artifacts from `artifacts/bin/`, release drop `DiagnosticsRelease`, `BundledTools`
- **es-metadata.yml**: `org: devdiv`, `path: DevDiv\NET Runtime\Diagnostics\SDL`, `isProduction: true`
- **Known findings (central portal)**: BA2009 on pre-built test fixture DLLs:
  - `mockclr_amd64.dll`, `mockclr_arm64.dll`, `mockclr_i386.dll`, `mockdac.dll`, `mockdbi.dll`, `mocksos.dll`
  - These are pre-built test binaries in `src/tests/Microsoft.SymbolStore.UnitTests/TestBinaries/` — not compiled from source
  - Fix: exclude from scan scope or suppress/baseline (test fixtures shouldn't be in shipped artifacts)
- **How to reproduce locally**: Build + scan `artifacts\bin\` outputs
- **Coverage concern**: Release drops and bundled tools may contain binaries beyond NuGet output
