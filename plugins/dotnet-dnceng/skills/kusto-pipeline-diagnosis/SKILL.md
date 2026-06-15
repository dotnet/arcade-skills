---
name: kusto-pipeline-diagnosis
description: >
  Diagnose AzDO build pipeline failures by querying the dnceng Kusto cluster
  (engsrvprod / engineeringdata) with Kusto.Cli. Queries TimelineBuilds (one row
  per build) then TimelineRecords (one row per stage/job/task) as separate steps
  (no joins) to find failed builds and their failing step + log link, then reads
  the AzDO logs to categorize failures across many builds at once.
  USE FOR: "which builds failed for definition X on main", "what step is failing
  most often", "show failing tasks and their logs for the last N builds",
  cross-build / historical failure trends, fast aggregate analysis without
  per-build REST calls or AzDO PATs. A pipeline = DefinitionId + Project +
  Organization (definition ids are not globally unique).
  DO NOT USE FOR: deep single-build log/binlog root-causing (use
  pipeline-investigation), Helix test failures (use helix-investigation),
  codeflow/subscription data (use flow-analysis / maestro-cli).
  INVOKES: bash/powershell (Kusto.Cli queries against an internal Kusto cluster).
---

# Kusto Pipeline Diagnosis

Diagnose .NET engineering build pipelines by querying their telemetry in Kusto
instead of calling the AzDO REST API per build. Kusto holds build and timeline
metadata for the whole org, so you can answer "what failed and where" across
hundreds of builds in a single query, then hand off the specific failing step's
log to a deeper skill.

## When to Use This Skill

- You want failures across **many** builds (a definition, a branch, a time range), not one build.
- You want **trends**: which step/job fails most often, how often a pattern recurs.
- You want the failing leaf step **and** its AzDO log URL without downloading each build timeline over REST.
- You don't have (or don't want to manage) an AzDO PAT — Kusto uses AAD sign-in.

**Prefer another skill when:**

- You already have one build URL and need to read logs/binlogs deeply → `pipeline-investigation`.
- The failure is a Helix test → `helix-investigation`.
- The question is about codeflow/subscriptions → `flow-analysis` or `maestro-cli`.

## Prerequisites

- .NET SDK (`dotnet`) available on PATH.
- Network access to the internal cluster (corporate network — on-site, or via VPN when remote) and an AAD account authorized for it.
- `Kusto.Cli`, installed from the `Microsoft.Azure.Kusto.Tools` NuGet package (steps below).

## Install Kusto.Cli

`Kusto.Cli` ships inside the `Microsoft.Azure.Kusto.Tools` NuGet package. It is
**not** a `dotnet tool`, so download and extract the package:

```powershell
# Windows (PowerShell)
$base = "https://api.nuget.org/v3-flatcontainer/microsoft.azure.kusto.tools"
$ver  = (Invoke-RestMethod "$base/index.json").versions[-1]
$dir  = "$env:USERPROFILE\kusto-cli"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Invoke-WebRequest "$base/$ver/microsoft.azure.kusto.tools.$ver.nupkg" -OutFile "$dir\pkg.zip"
Expand-Archive "$dir\pkg.zip" -DestinationPath $dir -Force
# Kusto.Cli.exe is under $dir\tools\net8.0\
```

```bash
# Linux / macOS (bash) — run the framework-dependent build via dotnet
base="https://api.nuget.org/v3-flatcontainer/microsoft.azure.kusto.tools"
ver=$(curl -s "$base/index.json" | jq -r '.versions[-1]')
dir="$HOME/kusto-cli"
mkdir -p "$dir"
curl -sL "$base/$ver/microsoft.azure.kusto.tools.$ver.nupkg" -o "$dir/pkg.zip"
unzip -oq "$dir/pkg.zip" -d "$dir"
# Run with: dotnet "$dir/tools/net8.0/Kusto.Cli.dll" <connection> -execute:"<query>"
```

## Connect

The cluster is `engsrvprod` and the database is `engineeringdata`. Use a
connection string with `Fed=true` for interactive AAD sign-in (token is cached
after the first prompt):

```powershell
$cli  = "$env:USERPROFILE\kusto-cli\tools\net8.0\Kusto.Cli.exe"
$conn = "https://engsrvprod.kusto.windows.net/engineeringdata;Fed=true"

# One-off query:
& $cli $conn -execute:"TimelineBuilds | take 2"

# Interactive REPL (type queries; 'q' to quit):
& $cli $conn
```

> If you get `KustoClientTimeoutException: Failed to retrieve cluster
> authentication metadata`, retry — the auth-metadata fetch is occasionally slow
> on the first call. If it keeps failing, or you see DNS resolution errors for
> `engsrvprod.kusto.windows.net`, the user likely isn't on the corporate network
> — if they're remote, ask them to connect to the **VPN** before retrying (not
> needed when working on-site). Chain multiple `-execute:` flags to run several
> queries in one invocation.

## Data Model

Two tables drive diagnosis. Full column lists and more queries are in
[references/kusto-schema.md](references/kusto-schema.md).

- **`TimelineBuilds`** — one row per build. Key columns: `BuildId`, `Result`
  (`succeeded` / `failed` / ...), `DefinitionId`, `Definition`, `SourceBranch`,
  `Reason` (`schedule`, `batchedCI`, `pullRequest`, ...), `StartTime`,
  `FinishTime`, `BuildNumber`, `Project`, `Organization`. A pipeline is the triple
  `(DefinitionId, Project, Organization)` — `DefinitionId` alone is ambiguous.
- **`TimelineRecords`** — one row per node in a build's timeline, forming a tree
  via `Path` (dotted) and `ParentId`. Key columns: `BuildId`, `Path`, `Name`,
  `Result`, `TaskName`, `LogUri`, `StartTime`, `FinishTime`.

**Hierarchy by `Path` depth** (verified):

| Depth | Example `Path`     | Level                 |
|-------|--------------------|-----------------------|
| 1     | `004`              | Stage                 |
| 2     | `004.002`          | Job                   |
| 3     | `004.002.001`      | Job phase / attempt   |
| 4     | `004.002.001.018`  | Task / step (leaf)    |

A failure propagates **up** the tree: a failed leaf task marks its job and stage
`failed` too. The **root-cause steps** are the depth-4 records with
`Result == 'failed'` and a non-empty `TaskName`; their `LogUri` points at the
actual Azure DevOps log. `ErrorCount` is unreliable (often `0` on failed
records) — filter on `Result`, not `ErrorCount`.

## Inputs

Before querying, establish **which pipeline** the user means. A pipeline is
identified by three values, because `DefinitionId` is **not** globally unique —
the same id can exist in different projects and organizations:

| Input          | Required | Notes                                                       |
|----------------|----------|-------------------------------------------------------------|
| `DefinitionId` | yes      | Numeric pipeline id, or discover it from a `Definition` name.|
| `Project`      | yes      | AzDO project (e.g. `internal`, `public`).                   |
| `Organization` | yes      | AzDO org (e.g. `dnceng`).                                    |

If the user gives only a `DefinitionId` (or only a pipeline name), **do not
assume** the project/organization — disambiguate first (Step 1). Optionally
narrow by `SourceBranch` and a time range; otherwise default to recent builds.

## Workflow

### Step 1: Identify the pipeline

Resolve the user's input to a unique `(DefinitionId, Project, Organization)`
triple before running any analysis.

If you have a `DefinitionId` but not the project/org, list every combination it
maps to and confirm with the user which one they mean:

```kusto
TimelineBuilds
| where DefinitionId == <definitionId> and StartTime > ago(90d)
| summarize Builds = count(), LastBuild = max(StartTime)
        by Organization, Project, Definition, DefinitionId
| sort by LastBuild desc
```

If you only have a pipeline **name**, find its id/project/org:

```kusto
TimelineBuilds
| where Definition has '<name fragment>' and StartTime > ago(90d)
| summarize Builds = count(), LastBuild = max(StartTime)
        by Organization, Project, Definition, DefinitionId
| sort by LastBuild desc
```

- **One row** → use that triple in the steps below.
- **Multiple rows** → ask the user which `Organization` / `Project` they want; never guess.
- **No rows** → widen the time range, or re-check the id/name with the user.

> Throughout the rest of this skill, substitute the confirmed values for
> `<definitionId>`, `<project>`, and `<organization>`.

### Step 2: List the failed builds

Filter `TimelineBuilds` to the confirmed pipeline and collect the failed build
ids. `TimelineBuilds` holds **multiple snapshot rows per build**, so dedupe with
`distinct` (or `summarize ... by BuildId`) — otherwise the same build is counted
many times. `SourceBranch` may be `main` or `refs/heads/main`, so match both:

```kusto
TimelineBuilds
| where DefinitionId == <definitionId>
        and Project == '<project>' and Organization == '<organization>'
        and SourceBranch in ('main', 'refs/heads/main')
        and Result == 'failed'
        and StartTime > ago(7d)
| distinct BuildId, BuildNumber
```

Keep the resulting `BuildId` list — you feed it into Step 3. (Run a separate
query per step; **do not** `join` the tables.)

> 💡 Scheduled (rolling) builds give the cleanest signal — add
> `| where Reason == 'schedule'`. PR builds include broken topic branches that
> inflate failure counts.

### Step 3: List the failed records (with log links) for those builds

Query `TimelineRecords` for the build ids from Step 2, restricted to failing
leaf tasks. Pass the ids inline with `in (...)` — again, no join. `distinct`
removes duplicate snapshot rows:

```kusto
TimelineRecords
| where BuildId in (<buildId1>, <buildId2>, ...)
        and Result == 'failed' and isnotempty(TaskName)
| distinct BuildId, Name, TaskName, LogUri
```

Each row is a real failing step: `Name` (e.g. `Run Tests (ubuntuArmContainer)`),
`TaskName` (e.g. `CmdLine`), and `LogUri` (the AzDO log to read in Step 4). The
step `Name` is only a **coarse** bucket — two builds can fail the same step for
different reasons — so the actual failure *type* comes from the log (Step 4).

### Step 4: Read each failed step's log

`LogUri` points at the Azure DevOps REST API (`dev.azure.com`). For the
`internal` project it requires a bearer token (Kusto's AAD sign-in does **not**
cover AzDO). Get one with the Azure CLI:

```bash
# AzDO resource id is constant across orgs
TOKEN=$(az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv)

# Fetch one failing step's log
curl -s -H "Authorization: Bearer $TOKEN" "<logUri>" -o /tmp/step.log
```

Read the tail of each log and extract the concrete error. Look for `##[error]`,
`[ERROR]`, MSBuild codes (`MSB####`, `NETSDK####`, `NU####`), `exit code null`
(process killed — OOM/timeout), `exit code 57005` (crossgen2 crash), and network
errors (`ETIMEDOUT`, `ECONNREFUSED`). For the catalogue of known dnceng failure
categories and owners, defer to the `pipeline-investigation` skill — don't
re-derive it here.

### Step 5: Group and report the most common failure type

Bucket the builds by the failure *type* you extracted in Step 4 (not just the
step name), then report the most common one with supporting evidence:

- The failure type and how many of the failed builds hit it.
- One representative `LogUri` (and `BuildNumber`) per type so the user can verify.
- A short root-cause line per type, and the owner if known (via `pipeline-investigation`).

> **Worked example** — *"most common failure type in pipeline 1330, dnceng /
> internal, main, last week"*: Step 2 lists the failed builds; Step 3 returns
> their failing steps + `LogUri`s; Step 4 reads those logs; Step 5 reports, e.g.,
> "`Run Tests` timeouts in `*ArmContainer` legs — N of M failed builds — see
> build 20260604.17". Track the buckets in a SQL table if there are many builds.

### Optional: quick step-frequency overview

Before reading logs, a fast `Name`-level frequency check can show where to focus.
This groups by step name only (coarse), so still confirm the type via logs:

```kusto
TimelineRecords
| where BuildId in (<buildId1>, <buildId2>, ...)
        and Result == 'failed' and isnotempty(TaskName)
| distinct BuildId, Name
| summarize Hits = dcount(BuildId) by Name
| sort by Hits desc
```

## Validation

- A query against `TimelineBuilds | take 2` returns rows → connection and auth work.
- Step 1 resolves the input to exactly one `(DefinitionId, Project, Organization)` triple (confirm with the user if more than one).
- Step 2 returns a **deduped** `BuildId` list for the pipeline/branch/time range.
- Step 3 returns at least one failing record with a populated `LogUri` per failed build.
- Step 4 token works: fetching a `LogUri` returns log text, not a sign-in page (re-acquire the token on a 401).
- Open a representative `LogUri` (it points to `dev.azure.com`) to confirm the reported failure type matches the log.

## Common Pitfalls

- **Don't filter on `DefinitionId` alone** — it is not globally unique. Always pin `Project` and `Organization` too, and disambiguate (Step 1) before analyzing.
- **Don't `join` the tables** — query `TimelineBuilds` first, then pass the `BuildId` list into a `TimelineRecords` query with `in (...)`. Sequenced queries are clearer and avoid join cost.
- **Dedupe builds and records** — both tables have multiple snapshot rows per build; use `distinct` (or `summarize ... by BuildId`) so counts aren't inflated.
- **Step `Name` is a coarse bucket** — the real failure *type* comes from reading the `LogUri` (Step 4), not from the step name alone.
- **Don't filter on `ErrorCount`** — it is frequently `0` even on failed records. Filter on `Result == 'failed'`.
- **Don't treat parent (stage/job) failures as root causes** — they only propagate the leaf failure. Root cause = depth-4 records with a non-empty `TaskName`.
- **Branch naming varies** — match both `main` and `refs/heads/main` (same for release branches).
- **There is no `Type` column** on `TimelineRecords` — derive the level from `Path` depth (`array_length(split(Path, '.'))`).
- **PR builds skew trends** — prefer `Reason == 'schedule'` for systemic-failure analysis.
- **Auth-metadata timeout / DNS errors on first call** — retry; it is often transient. If it persists or DNS can't resolve the cluster, the user probably isn't on the corporate network — if remote, ask them to connect to the **VPN** (not needed on-site).
