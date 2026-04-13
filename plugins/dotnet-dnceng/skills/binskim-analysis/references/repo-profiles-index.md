# Per-Repo BinSkim Profiles

Each file documents the BinSkim pipeline configuration, scan targets, known findings, local reproduction steps, and quirks for a specific repository.

**Pick the file matching the repo you're investigating.** Only load one at a time.

| Repository | File |
|---|---|
| dotnet/machinelearning | [repo-machinelearning.md](repo-machinelearning.md) |
| dotnet/dotnet (VMR) | [repo-dotnet-vmr.md](repo-dotnet-vmr.md) |
| dotnet/sdk | [repo-sdk.md](repo-sdk.md) |
| dotnet/runtime | [repo-runtime.md](repo-runtime.md) |
| dotnet/roslyn | [repo-roslyn.md](repo-roslyn.md) |
| dotnet/aspnetcore | [repo-aspnetcore.md](repo-aspnetcore.md) |
| dotnet/aspire | [repo-aspire.md](repo-aspire.md) |
| dotnet/diagnostics | [repo-diagnostics.md](repo-diagnostics.md) |
| microsoft/perfview | [repo-perfview.md](repo-perfview.md) |

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
