# Guardian Filtering

The official pipeline runs BinSkim via Guardian, and the results go through multiple filtering layers before reaching the central portal. Understanding this pipeline is critical for interpreting what the portal shows (and doesn't show).

## The filtering pipeline

```text
BinSkim runs -> raw binskim.sarif (ALL findings)
     |
Guardian merges/filters -> Results.sarif (subset of findings)
     |
Results.sarif uploaded -> Central portal shows only what survived
```

The raw `binskim.sarif` is available in the SDL build artifacts (e.g., `drop_build_Windows_x64_sdl_analysis` for most repos, or `drop_VMR_Vertical_Build_Windows_x64_sdl_analysis` for VMR repos). The merged `Results.sarif` is in the same artifact. **Always compare both** to understand what's being filtered.

## What gets filtered and why

Guardian filters BinSkim findings before reporting them to the central portal. The primary mechanism is **SDL policy requirement mappings** — an internal, centrally-managed policy that defines which BinSkim rules are required for SDL compliance. Only findings for rules with applicable policy mappings are promoted to `Results.sarif` and the portal. Other findings are silently dropped.

**The required rules vary by service tree org** (from `es-metadata.yml`). See the complete SDL requirement table in [binskim-rules.md](binskim-rules.md#sdl-requirement-status-all-rules).

### BA2022 filtering explained

BA2022 (SignSecurely) can produce **thousands** of raw findings in repos with many unsigned binaries. In BinSkim 4.x, unsigned binaries fire `Error_DidNotVerify` with `CRYPT_E_FILE_ERROR` — this is NOT "not applicable", it's an actual error-level finding. Guardian filters ALL of these because `CRYPT_E_FILE_ERROR` indicates the binary is simply unsigned (not improperly signed). Don't be alarmed by large BA2022 counts in raw SARIF — they will all be filtered.

This filtering is:

- **Not severity-based**: Some Error-level rules may be filtered out if they lack a policy mapping for your org
- **Not auto-baselining**: The `.gdnbaselines` files track known findings but don't remove them from reporting
- **Not a human suppression**: No one in your repo explicitly chose to hide these findings
- **Centrally managed**: The SDL team maintains which rules have policy mappings

The practical implication: **your local BinSkim scan will find more issues than the portal reports.** The filtered-out findings should still be examined — some may represent real security gaps that aren't yet SDL-required but are still worth fixing.

## Suppression mechanisms

If someone wants to **explicitly** suppress a finding, these are the mechanisms:

| Mechanism | File | Scope | Human decision? |
|-----------|------|-------|-----------------|
| SDL Policy filtering | Internal SDL rule database (not in repo) | Per-rule, per-org | No — managed centrally |
| Auto-baselining | `.config/1espt/PipelineAutobaseliningConfig.yml` | Pipeline-level | No — automatic |
| Guardian baselines | `.gdnbaselines` (pipeline artifact) | Per-finding | No — auto-generated |
| Guardian suppress | `.gdnsuppress` (can be checked into repo) | Per-finding | Yes — if in source control |
| Break policy | Pipeline YAML / template config | Per-tool | Semi — configured once |

The primary filtering is SDL Policy. To explicitly suppress a specific finding that IS reported, teams add it to a `.gdnsuppress` file in source control — but this is rarely done in dotnet repos.

## Other filtering layers

1. **Break policy (`IncludeTools`)**: Controls whether BinSkim can fail the build. Found in the `break/001/options.json` artifact. Many repos don't include BinSkim in `IncludeTools` — meaning BinSkim never breaks the build regardless of findings. This is separate from reporting.

2. **Auto-baselining**: The `.config/1espt/PipelineAutobaseliningConfig.yml` file enables auto-baselining. Guardian generates `.gdnbaselines` and `.gdnsuppress` files as pipeline artifacts (not checked into source). These track known findings for break-on-new-only logic but do **not** remove findings from the portal.

## Comparing raw vs merged SARIF

```powershell
$raw = (Get-Content "binskim\001\binskim.sarif" -Raw | ConvertFrom-Json).runs[0].results
# IMPORTANT: Results.sarif has multiple runs — filter to BinSkim
$mergedSarif = Get-Content "Results.sarif" -Raw | ConvertFrom-Json
$binskimRun = $mergedSarif.runs | Where-Object { $_.tool.driver.name -like '*BinSkim*' } | Select-Object -First 1
$merged = if ($binskimRun) { $binskimRun.results } else { $mergedSarif.runs[0].results }

Write-Host "Raw BinSkim findings: $($raw.Count)"
Write-Host "After Guardian filtering: $($merged.Count)"
Write-Host "`nRaw findings by rule:"
$raw | Group-Object ruleId | ForEach-Object {
    $levels = ($_.Group | ForEach-Object { $_.level } | Sort-Object -Unique) -join ","
    Write-Host "  $($_.Name): count=$($_.Count) levels=[$levels]"
}
```

## Matching portal results locally

To filter local BinSkim results to match what the portal reports, use the `-PortalRulesFrom` parameter on the scan skill's `Invoke-BinSkimScan.ps1`:

```powershell
.\Invoke-BinSkimScan.ps1 -ScanDir artifacts\pkgassets -PortalRulesFrom path\to\Results.sarif
```

This extracts the set of rule IDs from the Guardian-merged `Results.sarif` and filters local results to only show those rules. To get the `Results.sarif`, download the SDL artifact from your official pipeline (e.g., `drop_build_Windows_x64_sdl_analysis`) and look for `Results.sarif` in the artifact root.
