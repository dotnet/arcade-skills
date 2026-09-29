# Health Assessment Report Format

Standard format for pipeline health assessments. Use when asked "how healthy is the pipeline" or similar.

## Default Time Window

Since the last rolling build (scheduled/manual build on main or release/*). This gives the most meaningful snapshot — everything since the last full pipeline validation.

## Build Classification

Classify every build into one of three types:

| Type | How to Identify |
|------|----------------|
| **Rolling** | `sourceBranch` starts with `refs/heads/` (main, release/*). No PR trigger. Requested by `Microsoft.VisualStudio.Services.TFS`. |
| **Forward Flow** | PR title matches `[branch] Source code updates from *`. These are maestro codeflow PRs. |
| **Other PR** | All remaining PRs — developer changes, release updates, infrastructure fixes. |

To classify PR builds, extract the PR number from `sourceBranch` (`refs/pull/{number}/merge`) and query GitHub for the title:

```bash
gh pr view {number} --repo dotnet/dotnet --json title -q '.title'
```

## Fatal vs Non-Fatal Issues

The report's job is to tell the QB what is **breaking builds**. Before placing any issue in a table, decide whether it is fatal:

| Impact | Timeline evidence | Where it goes |
|--------|-------------------|---------------|
| **Fatal** | Task `result == "failed"` **and** parent Job `result == "failed"` (the task caused the leg to fail) | Failed Builds Table, Failure Trends Table |
| **Non-fatal** | Task `result == "succeededWithIssues"`; task `failed` but parent Job `succeeded`/`succeededWithIssues` (`continueOnError`); warning-type `issues`; builds whose overall result is `partiallySucceeded` | Non-Fatal Issues section only |

Rules:
- A non-fatal issue that happens to appear in a failed build is **still non-fatal**. Do not list it as that build's Failure Detail and do not count it toward fatal Hits.
- Common non-fatal noise includes SBOM generation warnings, 1ES/container tooling warnings (for example locale or runner setup messages), Component Governance alerts, and post-build steps marked `continueOnError`. Verify the job result every time; don't classify by name alone.
- If a tooling problem *does* fail the job, it is fatal. Report it as a normal failure.

## Failed Builds Table

List only builds with overall result `failed`, in chronological order. `partiallySucceeded` builds are not failed builds. The Failure Detail must describe the **fatal** cause:

```
| Build | Type | Source | Failure Detail |
|-------|------|--------|---------------|
| 1332308 | Rolling | main (scheduled) | Razor race (#5391) on 3 arm legs |
| 1333526 | Forward Flow | release/10.0.3xx ← sdk | PR Validation (modified protected file) |
```

- **Build**: AzDO build ID
- **Type**: Rolling, Forward Flow, or Other PR
- **Source**: For Rolling: branch name. For Forward Flow: `target ← source-repo`. For Other PR: short description of the PR.
- **Failure Detail**: Short category + root cause. Investigate before displaying; use `(not yet investigated)` only as a temporary placeholder.

## Summary Table

Follow the build list with a breakdown by type:

```
| Type | Completed | ✅ Pass | ❌ Fail | Pass Rate |
|------|-----------|---------|---------|-----------|
| Rolling | 1 | 0 | 1 | 0% |
| Forward Flow | 31 | 23 | 8 | 74% |
| Other PR | 15 | 6 | 9 | 40% |
| **Total** | **47** | **29** | **18** | **62%** |
```

Count `partiallySucceeded` builds as ✅ Pass. Their issues are non-fatal by definition.

Note any temporal patterns (failure clusters, recent green streaks, etc.).

## Failure Trends Table

When 3+ builds are in scope and at least one **fatal** failure pattern recurs across builds, add a trends table after the summary. Cap at top 5 patterns — one-offs don't get rows. Only fatal patterns belong here (see [Fatal vs Non-Fatal Issues](#fatal-vs-non-fatal-issues)). Give each distinct root cause its own row. Don't merge unrelated issues into one pattern.

```
| Pattern | Hits | Window | Status |
|---------|------|--------|--------|
| Razor file-lock race | 3/5 rolling | Mar 12-14 | ❌ No issue filed |
| SDK CS8602 | 2/5 rolling | Mar 13-14 | ✅ Fix merged PR #5471 |
| SourcelinkTests flaky | 2/3 internal | Mar 14 | 🔄 Known #5259 |
```

- **Pattern**: Short name for the recurring failure
- **Hits**: Count of affected builds / total builds in that category (e.g., "3/5 rolling")
- **Window**: Date range of occurrences
- **Status**: Triage state — one of:
  - ❌ No issue filed — needs action
  - ✅ Fix merged (link PR) — verify in next build
  - 🔄 Known issue (link) — tracked but not yet fixed
  - ⏳ Fix in progress (link PR) — someone is working on it

This table transforms the report from "what's broken" to "what needs action." The Failed Builds Table is a per-build log; this is per-pattern triage.

## Non-Fatal Issues (Informational)

Optional. Put this section last, after all fatal content, under a heading that includes "Non-Fatal". Include only recurring non-fatal patterns (2+ builds). Cap at top 5, or omit the section entirely if there is nothing worth tracking.

```
### ℹ️ Non-Fatal Issues (did not fail any build)

| Pattern | Occurrences | Window | Notes |
|---------|-------------|--------|-------|
| ℹ️ Alpine SBOM generation warning | 18 internal builds | 24 hours | `succeededWithIssues`, all jobs passed |
| ℹ️ AlmaLinux Python locale warning | 18 internal builds | 24 hours | Container init warning, non-blocking |
```

- Prefix every Pattern with `ℹ️` so rows are unambiguous when copied elsewhere.
- Use **Occurrences**, not Hits, so these rows aren't mistaken for build failures.
- Never use ❌ or "needs action" language here. If a non-fatal issue is worth filing (for example, it's getting worse or could become fatal), say so in Notes.

## Branch Filtering

Not all builds are equally interesting when assessing pipeline health.

**Internal (dnceng/internal):** Requires authentication (see SKILL.md Authentication section). If authenticated, include `main`, `release/*`, and `internal/release/*` branches. All three carry batchedCI builds that represent the shipping product. `internal/release/*` branches are **not** duplicates — they are the internal-only counterparts used for signing and secure build steps, and their health matters for release readiness. Ignore `dev/*` branches — those are experiments. If authentication fails, skip internal and note the limitation.

When reporting, group `internal/release/*` builds separately from `release/*` builds so their distinct failure patterns (e.g., signing, feed auth) are visible.

```bash
# AzDO API: filter to a specific branch
&branchName=refs/heads/main
```

**Public (dnceng-public/public):** Three categories of interest:

| Category | Branch Pattern | Reason | Signal |
|----------|---------------|--------|--------|
| **Main & release** | `main`, `release/*` | Same as internal — product health | batchedCI reason |
| **Codeflow PRs** | PR branches from `dotnet-maestro[bot]` | Automated dependency updates flowing between repos | pullRequest reason, author = `dotnet-maestro[bot]` |
| **Developer PRs** | All other PR branches | Individual contributor changes | pullRequest reason |

Codeflow PRs are especially useful — they test dependency updates before merge. A codeflow PR failing repeatedly signals a cross-repo integration break, not a one-off contributor mistake.

> ⚠️ **AzDO shows "GitHub" as the requester for ALL GitHub PRs.** You cannot distinguish codeflow from developer PRs using AzDO data alone. Extract the PR number from `sourceBranch` (`refs/pull/{number}/merge`) and query GitHub:

```bash
# Get PR author to classify codeflow vs developer
gh pr view {number} --repo dotnet/dotnet --json author,title --jq '{author: .author.login, title: .title}'
# Codeflow: author = "app/dotnet-maestro"
# Bot: author starts with "app/" (copilot-swe-agent, github-actions)
# Developer: all other authors
```

## Branch Health via Codeflow Analysis

When assessing overall pipeline health, group codeflow PRs by **target branch** to reveal which branches are healthy vs blocked:

1. Collect all PR builds in the time range
2. Query GitHub for each unique PR to get the author and target branch
3. Classify: codeflow (maestro) / bot / developer
4. Group codeflow PRs by target branch, count pass/fail

A codeflow PR failing **repeatedly** (e.g., 5 consecutive failures) is a stronger signal than any single build failure — it means dependency flow into that branch is blocked.

> 💡 **When asked about "pipeline health", default to main + release branches.** Only include PR builds if the user specifically asks or if looking for codeflow integration issues.
