---
name: binskim-analysis
description: >
  Investigate BinSkim SDL findings from official pipelines — understand Guardian filtering,
  compare raw vs merged SARIF, decode portal results, and determine fix ownership.
  Use when asked about SDL scan results, portal findings, Guardian filtering, rule meanings,
  or discrepancies between local and official results. Also use when asked "why does the portal
  show X", "what's filtered", "BA2008", "explain Guardian", "investigate SDL findings",
  "binskim failures in pipeline", or "what rules are required". DO NOT USE FOR: running BinSkim
  locally (use binskim-scan), source code analysis (use CodeQL), or credential scanning (use CredScan).
---

# BinSkim Official Results Analysis

Investigate and interpret BinSkim findings from official 1ES SDL pipelines. This skill helps you understand what the central portal reports, what gets filtered, and how to determine fix ownership.

> For running BinSkim locally against a repo, use the **binskim-scan** skill instead.

## When to Use This Skill

- Investigating BinSkim findings reported in the central SDL portal
- Understanding why the portal shows (or doesn't show) specific findings
- Comparing local scan results with official pipeline results
- Determining whether a finding is fixable in the repo or requires an upstream vendor fix
- Questions like "why does the portal show BA2008 on X.dll?", "what rules apply to my repo?"

## How Official SDL Scanning Works

Official pipelines run BinSkim via Guardian, not directly. Results go through filtering before reaching the portal:

```text
BinSkim runs -> raw binskim.sarif (ALL findings)
     |
Guardian merges/filters -> Results.sarif (subset)
     |
Results.sarif uploaded -> Central portal
```

**Your local scan will find more issues than the portal reports.** This is expected — the portal only shows findings for rules with SDL policy requirement mappings for your org. See [references/guardian-filtering.md](references/guardian-filtering.md) for the full filtering pipeline.

## Downloading SDL Artifacts

To investigate official results, download the SDL artifact from the repo's official build:

```powershell
# Use AzDO tools or ado-dnceng-pipelines_download_artifact
# Artifact naming pattern:
#   Most repos:  drop_build_Windows_x64_sdl_analysis
#   VMR repos:   drop_VMR_Vertical_Build_Windows_x64_sdl_analysis
# Some repos have multiple SDL legs — check all Windows legs

# Key files inside the artifact:
# - binskim/001/binskim.sarif    <- Raw BinSkim output (everything found)
# - Results.sarif                 <- Guardian-merged output (portal sees this)
# - break/001/options.json        <- Break policy (which tools can fail the build)
# - .gdnbaselines                 <- Auto-generated baseline suppressions
```

> **Large SARIF files**: For repos with many binaries (especially the VMR), raw and merged SARIF can be **50-80MB+**. Use `Get-Content -Raw | ConvertFrom-Json` and stream results with `Group-Object`.

> **SDL does NOT run on PR validation builds.** It only runs on official/CI pipelines (gated by `Build.Reason != PullRequest`). Users must manually queue the official pipeline for SDL results before merging.

**Per-repo pipeline names** — see [references/repo-profiles.md](references/repo-profiles.md) for full details including AzDO links and definition IDs.

## Comparing Raw vs Merged SARIF

Always compare both files to understand what Guardian filtered:

```powershell
$raw = (Get-Content "binskim\001\binskim.sarif" -Raw | ConvertFrom-Json).runs[0].results
$merged = (Get-Content "Results.sarif" -Raw | ConvertFrom-Json).runs[0].results

Write-Host "Raw BinSkim findings: $($raw.Count)"
Write-Host "After Guardian filtering: $($merged.Count)"
Write-Host "`nRaw findings by rule:"
$raw | Group-Object ruleId | ForEach-Object {
    $levels = ($_.Group | ForEach-Object { $_.level } | Sort-Object -Unique) -join ","
    Write-Host "  $($_.Name): count=$($_.Count) levels=[$levels]"
}
```

The delta between raw and merged is what Guardian filtered out based on SDL policy. See [references/guardian-filtering.md](references/guardian-filtering.md) for why things get filtered and the suppression mechanisms available.

## Service Tree and Org Awareness

Which rules the portal reports depends on `es-metadata.yml` — the `routing.defaultAreaPath.org` field determines your SDL policy scope. Different orgs have different required rules. For example, `devdiv` org (most `dotnet/*` repos) requires BA2008/BA2009/BA2021, while `nettel` org requires BA2004/BA2027 instead.

See [references/binskim-rules.md](references/binskim-rules.md) for the full rules tables and the observed portal requirements by org.

## Coverage Gap Detection

After examining results, check whether the scan covers everything the repo ships:

1. **List all published artifacts** from the pipeline YAML
2. **Compare with scan targets** — are installers, CLI archives, VSIXes, or native blobs excluded?
3. **Report gaps**: "This repo ships X.zip containing native binaries, but `scanOutputDirectoryOnly: true` only scans the NuGet output."

## Fix Ownership

Not all findings can be fixed in the repo where they're reported:

| Binary origin | Example | Fix approach |
|---|---|---|
| **C++ source in repo** (`.vcxproj`) | EtwClrProfiler.dll | Add compiler/linker flags (e.g., `/guard:cf` for BA2008) |
| **Pre-built native from NuGet** | Intel MKL/TBB, WiX winterop.dll | Cannot fix here — update package, file upstream issue, or suppress |
| **Test framework binaries** | xunit.*.dll | Fix scan scope — exclude from shipped artifacts |
| **Managed C# assembly** | Most `.dll` from `.csproj` | BA2008 not applicable (BinSkim skips IL-only). BA2004/BA2027 may apply |

**VMR (dotnet/dotnet)**: Findings map to source sub-repos. Look at the artifact path in the SARIF (e.g., `src/arcade/artifacts/...` means fix goes to `dotnet/arcade`).

### Common misconception

`<ControlFlowGuard>Guard</ControlFlowGuard>` in a `.csproj` does **nothing**. The C# compiler has no `/guard:cf` support. This MSBuild property only works in `.vcxproj` (MSVC C++). BA2008 only fires on native PE binaries.

## Non-Arcade Repos

Some repos (e.g., microsoft/perfview) don't use arcade infrastructure:
- No `eng/common/sdl/` — BinSkim config is in the 1ES template or pipeline YAML directly
- Build output may be in `src\bin\` instead of `artifacts\`
- Look for `.ado.yml` or `.pipelines/` for pipeline config
- The general analysis approach still works — find the SDL artifact, compare raw vs merged SARIF

## Anti-Patterns

> **Don't trust the central portal as the complete picture.** Download the raw `binskim.sarif` and compare with `Results.sarif`. The portal shows only findings for rules with SDL policy mappings.

> **Don't assume "not in the portal" means "not a problem."** Guardian filtering removes findings without SDL policy mappings for your org. These may still be good security practice.

> **Don't confuse break policy with reporting.** Break policy controls whether BinSkim fails the build. It does NOT control what gets reported to the portal. Findings can be reported without breaking the build.

> **Don't report NuGet transitive dependency findings as repo issues.** If `libSkiaSharp.dll` fails BA2008, that's SkiaSharp's issue — unless this repo ships it.

## References

- **BinSkim rules (all platforms)**: [references/binskim-rules.md](references/binskim-rules.md)
- **Guardian filtering deep-dive**: [references/guardian-filtering.md](references/guardian-filtering.md)
- **Per-repo profiles**: [references/repo-profiles.md](references/repo-profiles.md)
- **Arcade SDL infrastructure**: [references/arcade-sdl.md](references/arcade-sdl.md)
- **Local scanning**: Use the **binskim-scan** skill
