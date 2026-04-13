# Per-Repo BinSkim Profiles

Each file documents the BinSkim pipeline configuration, scan targets, known findings, local reproduction steps, and quirks for a specific repository.

**Pick the file matching the repo you're investigating.** Only load one at a time.

| Repository | File |
|---|---|
| dotnet/machinelearning | [machinelearning.md](machinelearning.md) |
| dotnet/dotnet (VMR) | [dotnet-vmr.md](dotnet-vmr.md) |
| dotnet/sdk | [sdk.md](sdk.md) |
| dotnet/runtime | [runtime.md](runtime.md) |
| dotnet/roslyn | [roslyn.md](roslyn.md) |
| dotnet/aspnetcore | [aspnetcore.md](aspnetcore.md) |
| dotnet/aspire | [aspire.md](aspire.md) |
| dotnet/diagnostics | [diagnostics.md](diagnostics.md) |
| microsoft/perfview | [perfview.md](perfview.md) |

## Discovering New Repos

For repos not listed above:

1. Search for `binskim` in pipeline YAML files:
   ```powershell
   Get-ChildItem -Recurse -Include "*.yml","*.yaml" | Select-String -Pattern "binskim" -SimpleMatch
   ```
2. Check `.config/1espt/PipelineAutobaseliningConfig.yml` for autobaselining
3. Check `eng/common/sdl/` for arcade SDL infrastructure (most dotnet repos share this)
4. Look for `BinskimAdditionalRunConfigParams` for custom exclusions
5. Identify all `PublishPipelineArtifact` steps to understand what's scanned
