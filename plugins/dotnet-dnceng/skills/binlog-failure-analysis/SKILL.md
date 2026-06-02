---
name: binlog-failure-analysis
description: >
  Analyze a failed Azure DevOps PR build by reusing the binlog that build already
  produced — instead of rebuilding locally. Use when an `azure-pipelines` check on
  a GitHub PR transitions to `failure` and you need a structured root-cause analysis
  posted back as a PR review. Downloads `PostBuildLogs_*` / `Logs_Build_*` from the
  AzDO build artifacts, invokes the `binlog` MCP server (Microsoft.AITools.BinlogMcp)
  for build overview / errors / warnings (with deeper diagnostic capabilities — root-cause
  reports, property-value tracing — when the basics aren't enough), groups symptoms
  by root cause,
  and emits a single summary comment. Optionally attaches inline `suggestion`
  blocks when an error maps to a one-line fix on a diffed line. Cuts per-PR
  analysis cost from ~5–8 min (rebuild + analyze) to ~2–3 min (download + analyze).
  DO NOT USE FOR: pipelines that don't publish a binlog artifact, GitHub-Actions-only
  repos (no AzDO build to reuse), or general CI health dashboards (use `ci-analysis`).
---

# Binlog Failure Analysis (reuse AzDO binlog, don't rebuild)

Analyze a failed AzDO PR build by reading the **binlog that build already produced**, not by re-running the local build (`./build.sh -bl` or equivalent) on a GitHub Actions runner. This is the AI-build-failure-analyst pattern: it makes the analyst run cheap enough to be turned on for every failing PR sync.

> 🛑 **NEVER** use `gh pr review --approve` or `--request-changes`. Only `--comment` is allowed. Approval and blocking are human-only actions.

**Workflow**: gate on `check_run: completed` → resolve PR + build id → download AzDO artifact → ask the `binlog` MCP server for the build overview, errors, and warnings (drilling into root-cause diagnostics or property-value tracing when the basics aren't enough) → group symptoms by root cause → post a single summary comment → optionally attach ≤10 inline `suggestion` blocks. The agent drives the analysis; tools provide the data.

## When to use

- A GitHub PR check from app slug `azure-pipelines` (or the repo's AzDO check slug) transitions to `failure`.
- The pipeline publishes a binlog artifact (arcade-onboarded repos do this via `eng/common/core-templates/steps/publish-logs.yml`; arbitrary AzDO pipelines may not).
- You want a structured per-PR comment with grouped root causes and concrete `suggestion` blocks — not just a link to the raw log.

## When NOT to use

- The PR has no AzDO check (GH-Actions-only repos) — use a rebuild-based skill instead, or wait for an AzDO migration.
- The pipeline doesn't publish a binlog artifact — there's nothing to reuse.
- You want pipeline-wide health analysis across many builds — use `ci-analysis` or `pipeline-investigation`.
- You want to investigate a non-build leg failure (test failures, Helix work item failures) — see `helix-investigation`.

## Prerequisites

- **`binlog` MCP server** — `Microsoft.AITools.BinlogMcp` is wired in `plugins/dotnet-dnceng/plugin.json` under the namespace `binlog`. The same server is also published by `dotnet/skills/dotnet-msbuild` under the same `binlog` name, so installing both plugins resolves to a single MCP instance. This skill invokes the server's capabilities semantically (build overview, error list, warning list, root-cause diagnose, property-value trace, structured search, task details, tasks-in-target) — discover the exact tool names for your server version via `tools/list`. With `Microsoft.AITools.BinlogMcp`, typical names start with `binlog_` (e.g., `binlog_overview`, `binlog_errors`); the server exposes ~29 tools total.
- **`curl`** for the AzDO REST artifact download.
- **`jq`** for parsing the AzDO artifacts JSON and the GitHub check-runs payload (Step 2 + `references/azdo-artifact-fetch.md`).
- **`unzip`** for extracting the artifact.
- **Azure DevOps access:**
  - Anonymous read for `dev.azure.com/dnceng-public/public` — no token needed.
  - For `devdiv/DevDiv` or `dnceng/internal`: a federated identity (`azure/login@v2`) or `azureauth ado token`. See `references/azdo-artifact-fetch.md`.
- **`gh` CLI** for posting the summary comment + inline review comments.

## Inputs

The caller must provide these as environment variables (or equivalent):

| Variable                | Meaning |
| ----------------------- | ------- |
| `AZDO_ORG`              | AzDO organisation (e.g., `dnceng-public`, `devdiv`). |
| `AZDO_PROJECT`          | AzDO project (e.g., `public`, `DevDiv`). |
| `AZDO_BUILD_ID`         | Numeric build ID to fetch the binlog from. |
| `PR_NUMBER`             | GitHub PR number where the analysis comment will be posted. |
| `PR_HEAD_SHA`           | Head SHA of the PR (used for permalinks in the comment). |
| `GITHUB_WORKSPACE`      | Repo checkout root; used to convert absolute paths in the binlog to repo-relative paths. |

If only a PR number is known, see `references/azdo-artifact-fetch.md` for finding the build ID via the GitHub check-runs API.

## Workflow

The skill executes seven sequential steps. Each step gates the next — stop early if a step's preconditions aren't met.

1. **Sanity check** — verify the trigger is a real failure with a known build id.
2. **Download the binlog** from AzDO build artifacts.
3. **Dump the binlog as JSON** via the `binlog` MCP server (build overview, errors, warnings; drill-down capabilities on demand).
4. **Group errors by root cause** using common .NET / MSBuild failure patterns.
5. **Post the summary comment** on the PR with grouped clusters and proposed fixes.
6. **Post inline `suggestion` review comments** (≤10, **optional / best-effort**) only when an error has a clear one-line fix on a line touched by the PR diff. Skip if no error fits cleanly.
7. **Stop** — never approve or request changes; this skill is comment-only.

### Step 1 — Sanity check

If `AZDO_BUILD_ID` is empty or the check-run that triggered this skill has `conclusion != 'failure'`, stop. There's nothing to analyse.

### Step 2 — Download the binlog from AzDO

```bash
# 1. List artifacts on the build, find the binlog artifact.
ARTIFACTS=$(curl -fsSL \
  ${AZDO_TOKEN:+ -H "Authorization: Bearer $AZDO_TOKEN"} \
  "https://dev.azure.com/$AZDO_ORG/$AZDO_PROJECT/_apis/build/builds/$AZDO_BUILD_ID/artifacts?api-version=7.1")

# Arcade-onboarded repos publish binlogs under artifact name
# `PostBuildLogs_<StageLabel>_<JobLabel>_Attempt<N>`. dnceng-public legs
# typically use `Logs_Build_Attempt<N>_<leg>`. Prefer PostBuildLogs* first.
ARTIFACT_NAME=$(echo "$ARTIFACTS" | jq -r '.value[] | select(.name | test("^PostBuildLogs_|^Logs_Build_")) | .name' | head -1)
if [ -z "$ARTIFACT_NAME" ]; then
  echo "No PostBuildLogs_* or Logs_Build_* artifact on build $AZDO_BUILD_ID — pipeline likely doesn't publish a binlog. Post a one-line PR comment noting this and stop."
  exit 0
fi
DOWNLOAD_URL=$(echo "$ARTIFACTS" | jq -r --arg n "$ARTIFACT_NAME" '.value[] | select(.name == $n) | .resource.downloadUrl')
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
  echo "Artifact '$ARTIFACT_NAME' has no downloadUrl — unexpected AzDO response shape. Stop."
  exit 0
fi

# 2. Download and unzip.
mkdir -p /tmp/azdo-binlog
curl -fsSL ${AZDO_TOKEN:+ -H "Authorization: Bearer $AZDO_TOKEN"} -o /tmp/azdo-artifact.zip "$DOWNLOAD_URL"
unzip -q -o /tmp/azdo-artifact.zip -d /tmp/azdo-binlog

# 3. Pick the most-recently-modified *.binlog (the failing leg's binlog
#    is typically the newest in the artifact).
BINLOG=$(find /tmp/azdo-binlog -name '*.binlog' -type f -printf '%T@ %p\n' \
         | sort -nr | head -1 | cut -d' ' -f2-)
if [ -z "$BINLOG" ]; then
  echo "Artifact '$ARTIFACT_NAME' extracted but contains no *.binlog — pipeline isn't binlog-producing. Post a one-line PR comment noting this and stop."
  exit 0
fi
```

Full REST recipe (incl. dnceng/internal auth, fallback when no `PostBuildLogs_*` artifact exists): see `references/azdo-artifact-fetch.md`.

### Step 3 — Dump the binlog as JSON

Use the `binlog` MCP server (`Microsoft.AITools.BinlogMcp`). Every tool takes a `binlog_file` argument (no separate load step needed).

> **Discover the tool surface first.** Tool names below are the typical ones exposed by `Microsoft.AITools.BinlogMcp` and are listed as hints — if names differ on your server version, call `tools/list` on the `binlog` MCP namespace and use the equivalent capability. The capability you need is what matters; the exact name is incidental.

**Always gather the basics first** — they're cheap and feed Step 4's clustering:

| Information you need | Typical tool | Output file |
| -------------------- | ------------ | ----------- |
| Build status + project totals + which target failed | `binlog_overview` | `/tmp/binlog-data/binlog-overview.json` |
| Per-error structured rows | `binlog_errors` | `/tmp/binlog-data/binlog-errors.json` |
| Top-N warnings (pass `top: 10`) | `binlog_warnings` | `/tmp/binlog-data/binlog-warnings.json` |

Each error row contains: `severity`, `code`, `message`, `file`, `line`, `column`, `projectFile`, `targetName`, `taskName`.

**Drill down on-demand when the basics aren't enough** — e.g., overview says FAILED but the errors list is empty, or two clusters look like they share a hidden cause:

| Information you need | When to gather it | Typical tool | Output file |
| -------------------- | ----------------- | ------------ | ----------- |
| Automated root-cause report (task failures, OnError targets, process exits) | Overview says FAILED but the errors list is empty or uninformative | `binlog_diagnose` | `/tmp/binlog-data/binlog-diagnose.json` |
| Where a property value came from (which import/file set `$(TargetFramework)`, `$(OutputPath)`, etc.) | An error blames a property value | `binlog_explain_property` | `/tmp/binlog-data/binlog-explain-<name>.json` |
| Every occurrence of a string/path/regex across the build (StructuredLog-Viewer query syntax) | You need to locate every mention of a token | `binlog_search` | `/tmp/binlog-data/binlog-search-<slug>.json` |
| One task's inputs, outputs, and timing | A specific task is responsible for the failure | `binlog_task_details` | `/tmp/binlog-data/binlog-task-<name>.json` |
| Which task inside a target actually failed | A failing target has many tasks; you need to find the culprit | `binlog_tasks_in_target` | `/tmp/binlog-data/binlog-tasks-in-<target>.json` |

If the overview says the build FAILED but every error/diagnose tool returns empty, the failure was non-MSBuild (process crash, signing, network). Fall back to grepping the raw artifact for `error` / `failed` lines.

### Step 4 — Group errors by root cause

Common .NET / MSBuild root-cause patterns:

| Pattern                       | Telltale codes              | Typical root cause |
|-------------------------------|-----------------------------|--------------------|
| Missing API / using directive | `CS0103`, `CS0246`, `CS0234`| Removed namespace, missing project reference, missing TFM-conditional code. |
| Nullable / type mismatch      | `CS8600`–`CS8618`, `CS0029` | Recent nullability change cascading across call sites. |
| Public API mismatch           | `RS0016`, `RS0017`, `RS0026`| Public API not declared in `PublicAPI.Unshipped.txt`. |
| StyleCop violation            | `SA####`                    | Trailing whitespace, missing newline, tuple casing. |
| Analyzer rule violation       | `CA####`                    | Code-quality rule promoted via `WarnAsError`. |
| MSBuild task / target failure | `MSB####`                   | Missing file, malformed XML, broken import. |
| NuGet resolution failure      | `NU####`, `NETSDK####`      | Version conflict, banned dependency, missing TFM. |
| Localization regression       | `xlf` parsing error         | `.resx` modified without `dotnet msbuild /t:UpdateXlf`. |
| TFM-specific failure          | error only fires for one TFM| Missing `#if NET` guard or conditional reference. |

Group every error in the binlog under exactly one root-cause cluster. If two clusters share a probable common cause, merge them.

### Step 5 — Post the summary comment

Post exactly one comment via `gh pr comment` (or the safe-output equivalent in the calling workflow). Mark it with `<!-- binlog-failure-analysis -->` so later runs can supersede the previous one.

Template (keep under 400 lines total):

```markdown
<!-- binlog-failure-analysis -->
## 🔍 Build Failure Analysis

**Summary** — <one sentence stating what failed, with a link to the AzDO build URL>

### Root cause 1: <short title>
<2–3 sentences explaining the underlying issue and which symptoms it produces.>

**Affected files / errors**
- [`path/to/file.cs:42`](<permalink>) — `CS0103: ...`

**Proposed fix**
```diff
- old line
+ new line
```

### Root cause 2: <short title>
… (repeat) …

---
<details><summary><b>Build overview</b></summary>
<paste the build-overview output: configuration, TFM, target that failed.>
</details>

<details><summary><b>All MSBuild errors (N)</b></summary>
| Code | Project | File:Line | Message |
| ---- | ------- | --------- | ------- |
| `CS0103` | `Foo` | `Bar.cs:42` | The name 'foo' does not exist… |
</details>

<sub>🤖 Generated by the `binlog-failure-analysis` skill · binlog from AzDO build <code>$AZDO_BUILD_ID</code></sub>
```

Build permalinks as `${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/blob/${PR_HEAD_SHA}/<relative-path>#L<line>`.

### Step 6 — Post inline suggestions (optional, best-effort)

> ℹ️ **This step is best-effort.** Skip it entirely if no error fits cleanly — a high-quality summary comment alone is more valuable than speculative inline edits. The skill is considered successful even when Step 6 produces zero comments.

When (and **only** when) an error has all of the following:

- a `file:line` that lies **inside the PR diff** (verify with `gh pr diff`),
- a fix that is exactly one or a few contiguous lines, and
- a fix you can render as valid code (no pseudo-code, no TODOs),

post one inline review comment via `gh api /repos/{owner}/{repo}/pulls/{n}/comments` with a `suggestion` code block:

````markdown
🔧 **`<error-code>`** — <one-sentence explanation>

```suggestion
<replacement line(s); preserve indentation>
```
````

Hard caps:

- ≤10 inline suggestions per run.
- **Zero is a valid outcome** — if no error meets all three criteria above, post nothing. Don't fabricate a suggestion to hit a quota.
- Suggestions must be valid code when applied — no pseudo-code.
- Only post inline on lines that are *part of the PR diff* — GitHub rejects otherwise.
- If the offending line is not in the diff but the root cause is, prefer mentioning the cascade in the summary comment (Step 5) rather than picking an unrelated declaration line.

### Step 7 — Stop

Do not post `gh pr review --approve` / `--request-changes`. The skill is read-only with respect to merge decisions.

## Validation

A successful run leaves:

- `/tmp/azdo-binlog/*.binlog` — the binlog downloaded from AzDO (not produced by a local build).
- `/tmp/binlog-data/binlog-overview.json`, `binlog-errors.json`, `binlog-warnings.json` — structured tool output.
- One PR comment with the `<!-- binlog-failure-analysis -->` marker.
- 0 – 10 inline review comments (Step 6 is optional). When present, every `suggestion` block must apply cleanly.

## Defensive behaviour

- If the build-overview output returns "SUCCEEDED" but the AzDO check is `failure`, the failure was downstream of MSBuild (test runner, Helix work item, ESRP signing). Post a one-line comment noting this and link to the AzDO build URL — don't fabricate root causes.
- If the AzDO REST call returns 401/403, the project isn't anonymously readable. Caller must wire an `azure/login@v2` or `azureauth ado token` step before this skill runs.
- If the artifact doesn't contain a `*.binlog`, the pipeline isn't binlog-producing. Note that and stop; this skill cannot help.
- Never propose a fix that disables an analyzer (`#pragma warning disable`, adding to `<NoWarn>`) without explicit justification — analyzers exist for a reason.
- If the build pattern looks like a flake (NuGet feed timeout, intermittent SDK download error), say so and recommend a re-run rather than a code change.

## References

- `references/azdo-artifact-fetch.md` — full AzDO REST recipe: artifact listing, fallback when `PostBuildLogs_*` is absent, internal-project authentication, and discovering the build id from a GitHub check-run event.
