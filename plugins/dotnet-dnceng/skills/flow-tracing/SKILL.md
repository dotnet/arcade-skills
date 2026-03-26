---
name: flow-tracing
description: >
  Trace dependency flow across .NET repos through the VMR pipeline.
  USE FOR: checking if a PR/commit from repo A has reached repo B,
  finding what runtime SHA is in an SDK build, tracing dependency
  versions through the VMR, checking if a commit is included in an
  SDK build, decoding SDK version strings, "has my fix reached runtime",
  "did roslyn#80873 flow to runtime", "what SHA is in SDK version X",
  cross-repo dependency tracing, mapping SDK versions to VMR commits.
  DO NOT USE FOR: codeflow PR health or staleness (use flow-analysis
  skill), CI build failures (use ci-analysis skill).
  INVOKES: maestro and GitHub MCP tools, Get-SdkVersionTrace.ps1 script.
---

# Flow Tracing

Trace dependency flow across .NET repositories through the VMR pipeline. Two workflows:

1. **Cross-repo flow trace**: Has a change from repo A reached repo B? → Use Steps 1-4 below (reads GitHub files + maestro MCP directly)
2. **SDK version trace**: What component SHA is in a specific SDK version? → **Run `Get-SdkVersionTrace.ps1`** (handles version decoding, build lookup, and servicing topology automatically)

## When to Use This Skill

Use this skill when:
- Asked "has my fix/PR from repo A reached repo B?" (e.g., "has roslyn#80873 reached runtime?")
- Asked "did the change from dotnet/aspnetcore flow to dotnet/sdk yet?"
- Asked "what runtime SHA is in SDK version X"
- Asked "is commit X in SDK version Y" or "does this SDK include my fix"
- Need to trace whether a specific fix has flowed through the VMR pipeline to a downstream repo
- Need to decode an SDK version string (date, band, branch)

Do **NOT** use this skill when:
- Asked about codeflow PR health or whether a backflow PR is stale → use **flow-analysis** skill
- Asked about CI build failures or test results → use **ci-analysis** skill

## Cross-Repo Flow Trace

**Question**: "Has change X from repo A reached repo B?"

### Step 1: Resolve the Source Change

Identify the merge commit in repo A:
- If given a **PR number**: Read the PR to get its merge commit SHA. If you get a 404, try reading it as an issue instead — the number may be an issue, not a PR. If not yet merged, stop — the change hasn't entered the pipeline.
- If given an **issue number**: Search for linked PRs, then get the merge commit SHA.
- If given a **commit SHA**: Use directly.
- If given a **description** (e.g., "the async Main change"): Search issues/PRs in the source repo by keyword. If multiple candidates match, present the top 3 and ask the user to confirm before proceeding.

**Resolve "latest build"**: If the user says "latest SDK" without a version, default to `main` (current dev). If they say "latest .NET 10", resolve to the latest build on the `.NET 10.0.1xx SDK` channel.

Determine the **target VMR branch**: Usually `main` for current dev, or `release/X.0.1xx` for a specific version. Resolve using `.NET major = year − 2015`.

### Step 2: Check VMR Intake (source-manifest.json)

Read `src/source-manifest.json` from `dotnet/dotnet` on the target VMR branch. Find the entry for repo A — the `commitSha` field shows the latest commit from repo A that the VMR has consumed.

**Determine if the change is included** — practical approaches (try in order):
1. **Date comparison** (fastest): If the VMR commit date is months after the PR merge date, the change is included — no further checking needed.
2. **Compare API**: Use GitHub compare endpoint if dates are close (within days).
3. **Commit history walk**: List recent commits on repo A if compare is unavailable.

- **If repo A's SHA in source-manifest is at or past the merge commit** → VMR has it. Proceed to Step 3.
- **If not** → The change hasn't reached the VMR yet. Check forward flow: is there an open PR from repo A into `dotnet/dotnet`? If yes, it's in transit.

> ⚠️ **2xx/3xx bands**: Only the **1xx branch** source-builds all components. If tracing to a 2xx/3xx branch, runtime/aspnetcore won't appear in source-manifest — they're consumed as prebuilts from 1xx. See [references/servicing-topology.md](references/servicing-topology.md).

### Step 3: Check Downstream Delivery (repo B)

If the VMR has the change, check if it has flowed to repo B:

> ⚠️ **`eng/Version.Details.xml`** is the file you want — it contains source dependency entries with `Sha` fields pointing to upstream commits. Do NOT use `eng/Versions.props` (that file has NuGet package versions, not source SHAs).

1. **Check subscription health** for repo B using maestro MCP — is the backflow subscription current?
2. **If subscription is current**: The change has reached repo B. Confirm by reading `eng/Version.Details.xml` in repo B on the target branch — look for the `dotnet/dotnet` source entry's `Sha` field.
3. **If subscription is stale**: The subscription is behind, but the change may still be there. Read `eng/Version.Details.xml` in repo B — the `dotnet/dotnet` source entry's `Sha` field is the VMR commit that repo B last consumed. Then read `src/source-manifest.json` from `dotnet/dotnet` at *that specific SHA* and check repo A's `commitSha`. If it's at or past the merge commit, the change reached repo B despite the subscription being behind on newer builds.
4. **If subscription is stale AND the change isn't in repo B's consumed VMR SHA**: The change is in the VMR but hasn't flowed to repo B yet. Suggest checking backflow PR status (use flow-analysis skill for deeper diagnosis).

### Step 4: Report

Summarize the trace chain:
- "✅ roslyn#80873 merged at SHA `abc123` → VMR consumed it (source-manifest shows `def456`) → runtime backflow is current (subscription healthy)"
- "⚠️ aspnetcore#54321 merged at SHA `abc123` → VMR has it → but runtime backflow is 3 builds behind — change hasn't reached runtime yet"
- "❌ PR#999 hasn't merged yet — change hasn't entered the pipeline"

## SDK Version Trace

Trace the dependency chain from a .NET SDK version string to the exact component commit SHA.

> ⚠️ **Internal builds**: The script queries `dnceng/internal` via `az pipelines` CLI. If that fails, try the Azure DevOps MCP tools instead, or vice versa.

### Quick Start

For **cross-repo flow trace** — use the workflow above (Steps 1-4). No script needed; the agent reads GitHub files and Maestro data directly.

For **SDK version trace** — use the script:

```powershell
# Trace runtime SHA in a specific SDK version
./scripts/Get-SdkVersionTrace.ps1 -SdkVersion "10.0.300-preview.26117.103"

# Trace a specific component
./scripts/Get-SdkVersionTrace.ps1 -SdkVersion "10.0.300-preview.26117.103" -Component "aspnetcore"

# Check if specific commits are included in that SDK
./scripts/Get-SdkVersionTrace.ps1 -SdkVersion "10.0.300-preview.26117.103" -CheckCommit "b226ba1f77a4","f3bc0212e637"

# Just decode the version string without tracing
./scripts/Get-SdkVersionTrace.ps1 -SdkVersion "10.0.300-preview.26117.103" -DecodeOnly
```

### Key Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-SdkVersion` | Yes | — | Full SDK version string (e.g., `10.0.300-preview.26117.103`) |
| `-Component` | No | `runtime` | Component to trace. Matched against `source-manifest.json` entries (e.g., `runtime`, `aspnetcore`, `nuget`, `roslyn`). Supports partial matching. |
| `-CheckCommit` | No | — | One or more commit SHAs to check if they are included in the resolved component SHA. Requires a local clone. |
| `-DecodeOnly` | No | `$false` | Only decode the version string; don't trace the full chain |

### What the Script Does

1. **Decodes the SDK version** — Extracts major/minor, band, build date (SHORT_DATE → calendar date), revision
2. **Maps to VMR branch** — Determines `release/X.Y.Nxx` branch from the SDK band
3. **Finds the build** — Queries AzDO internal builds on that branch around the decoded date
4. **Gets the VMR commit** — Extracts `sourceVersion` from the matching build
5. **Walks the dependency chain**:
   - Checks `source-manifest.json` at that VMR commit for the component
   - If not found (servicing branches don't source-build all components), follows `Version.Details.xml` to the upstream VMR branch and checks `source-manifest.json` there

### Interpreting Script Results

The script outputs a structured trace showing each step of the dependency chain:

- **✅ Found in source-manifest.json** — Component is source-built in this VMR branch; SHA is direct
- **⚠️ Not in source-manifest; following Version.Details.xml** — Component is consumed as a prebuilt package; tracing through the upstream 1xx branch
- **🔴 Component not found** — Component is not referenced in either manifest

> ⚠️ **Servicing branches (2xx, 3xx)** do NOT source-build runtime. The script automatically follows the dependency chain through `Version.Details.xml` to the 1xx branch. See [references/servicing-topology.md](references/servicing-topology.md).

> ⚠️ **SDK version dates use Arcade's SHORT_DATE formula**: `YY*1000 + MM*50 + DD` (NOT YYDDD day-of-year). `26117` = `26*1000 + 02*50 + 17` = February 17, 2026, NOT April 27. See [references/sdk-version-format.md](references/sdk-version-format.md).

## References

- **SDK version format**: See [references/sdk-version-format.md](references/sdk-version-format.md)
- **Servicing branch topology**: See [references/servicing-topology.md](references/servicing-topology.md)
- **AzDO pipeline IDs and queries**: See [references/azdo-pipelines.md](references/azdo-pipelines.md)
