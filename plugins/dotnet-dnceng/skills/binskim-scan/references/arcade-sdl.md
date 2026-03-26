# Arcade SDL Infrastructure

The shared SDL (Security Development Lifecycle) infrastructure lives in `eng/common/sdl/` in arcade-based repos. This is how BinSkim gets configured and run in official 1ES pipelines.

## Key Files

### `eng/common/sdl/configure-sdl-tool.ps1`

Configures Guardian tools including BinSkim. Key behavior for BinSkim:

```powershell
# The target pattern it generates:
"Target < $TargetDirectory\**;-:file|$TargetDirectory\**\_.pdb"
```

- `$TargetDirectory` is the artifact directory passed from the pipeline
- Excludes `_.pdb` files (BinSkim crashes on some PDBs — see https://github.com/microsoft/binskim/issues/924)
- Accepts `$BinskimAdditionalRunConfigParams` for per-repo custom configuration

### `eng/common/sdl/extract-artifact-packages.ps1`

Extracts .nupkg files for scanning. Behavior:
- Takes `$InputPath` (directory with .nupkg files) and `$ExtractPath` (output)
- Extracts only `.dll`, `.exe`, `.pdb` files from each .nupkg
- Creates per-package subdirectories under extract path
- Runs extraction jobs in parallel

This is what you're reproducing when you locally extract .nupkg files for scanning.

### `eng/common/sdl/execute-all-sdl-tools.ps1`

Orchestrator that runs all SDL tools. Takes:
- `$ArtifactsDirectory` — what to scan
- `$ArtifactToolsList` — which tools to run (e.g., `@("binskim")`)

### `eng/common/sdl/run-sdl.ps1`

Executes Guardian with the generated configuration.

## Pipeline YAML Integration

### 1ES Pipeline Template (most repos)

The 1ES pipeline template (`1ES/PipelineTemplate`) handles SDL scanning automatically. Repos configure it via:

```yaml
# In the pipeline YAML
extends:
  template: v1/1ES/Official/PipelineTemplate/...
  parameters:
    sdl:
      binskim:
        enabled: true
        scanOutputDirectoryOnly: true  # Only scan published artifacts
        # analyzeTargetGlob: "..."     # Override default target
```

### `scanOutputDirectoryOnly`

When `true` (common), BinSkim only scans the directory where the pipeline published its artifacts — typically `artifacts/pkgassets/` or the extracted .nupkg contents. When `false`, it scans the full build output.

### `PipelineAutobaseliningConfig.yml`

Located at `.config/1espt/PipelineAutobaseliningConfig.yml`. This is the 1ES auto-baselining configuration that tracks known findings. If a repo has this but no explicit `sdl.binskim` section in its pipeline YAML, BinSkim runs with default settings via the template.

### Custom Parameters

Some repos pass additional BinSkim configuration:

```yaml
sdl:
  binskim:
    enabled: true
    additionalRunConfigParams: "--some-flag value"
```

These map to `BinskimAdditionalRunConfigParams` in `configure-sdl-tool.ps1`.

## Reproducing Locally

To match what the pipeline does:

1. **Build + pack** the repo (produces .nupkg or pkgassets)
2. **Extract packages** (mirrors `extract-artifact-packages.ps1`):
   ```powershell
   Get-ChildItem "artifacts\packages\Release\Shipping\*.nupkg" | ForEach-Object {
       $dest = Join-Path "artifacts\extracted" $_.BaseName
       Expand-Archive $_.FullName $dest -Force
   }
   ```
3. **Run BinSkim** with the same target pattern:
   ```powershell
   & $binskim analyze "artifacts\extracted\**;-:file|artifacts\extracted\**\_.pdb" --recurse --output results.sarif --pretty-print --force
   ```

This produces results equivalent to the official pipeline (minus any baseline suppression).
