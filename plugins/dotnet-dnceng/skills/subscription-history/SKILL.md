---
name: subscription-history
description: >
  Tell the history of a Maestro subscription using the darc CLI's
  get-subscription-history command. USE FOR: "what happened the last
  times this subscription ran", "show the trigger history for a
  subscription", "why did this subscription fail/not update", "did this
  subscription open a PR recently", inspecting subscription trigger
  outcomes (Updated, NoUpdate, NotUpdatable, Failure, UserError,
  HasConflict, Rescheduled), filtering outcomes by build id, date range,
  outcome type or free-text repo/branch search. DO NOT USE FOR: checking
  current subscription staleness/health (use flow-analysis or maestro-cli),
  tracing whether a commit reached a repo (use flow-tracing), CI build
  failures (use ci-analysis). INVOKES: shell (darc get-subscription-history).
allowed-tools: shell
---

# Subscription History

Tell the history of a Maestro subscription — what happened each time it was
triggered — using `darc get-subscription-history`. Each result is a
**subscription trigger outcome** recorded by Maestro describing what happened
when a subscription ran (a PR was opened/updated, there was nothing to update,
the update failed, etc.).

## When to Use This Skill

Use this skill when the user wants the **history** of a subscription's trigger
outcomes — for example:

- "Show me the history of subscription `<guid>`"
- "Why has this subscription been failing?"
- "Did this subscription open a PR in the last week?"
- "What were the last 5 outcomes for the core-sdk subscription?"

Do **not** use this skill for current staleness/health (use `flow-analysis` or
`maestro-cli`), for tracing a commit across repos (use `flow-tracing`), or for
CI build failures (use `ci-analysis`).

## Inputs

- **darc** installed and authenticated (see below).
- One or more filters describing the subscription of interest. The most precise
  filter is the subscription id (GUID). If the user gives a repo/branch instead,
  use `--search` or first resolve the id with `darc get-subscriptions`.

## Prerequisites

`darc` (Dependency ARcade) manages dependency flow in the .NET ecosystem.

1. Install (or update) from any arcade-enabled repo by running the
   `darc-init` script in `eng/common`:
   ```powershell
   .\eng\common\darc-init.ps1   # Windows
   ```
   ```bash
   ./eng/common/darc-init.sh    # macOS / Linux
   ```
   This installs the version of darc the repo expects; re-run it to update an
   out-of-date darc.
2. Authenticate once: `darc authenticate` (caches Entra ID credentials under
   `~/.darc/`). Required to read Maestro/BAR data.

Verify with `darc get-subscription-history --help`. If the command is not
recognized, the installed darc is too old — re-run `darc-init` to update it.

## Workflow

### Step 1: Identify the subscription

The most precise filter is the subscription id. If the user provided one, use
`--id <guid>`. Otherwise, resolve it:

```bash
# Find the subscription id from the source/target repos
darc get-subscriptions --source-repo <source> --target-repo <target>
```

You can also skip resolution and pass a `--search` term that is matched against
the subscription's source repo, target repo and target branch.

### Step 2: Query the history

```bash
# Full history of one subscription (most recent first)
darc get-subscription-history --id <subscription-guid>

# Narrow to failures only
darc get-subscription-history --id <subscription-guid> --type Failure

# By repo/branch free-text search instead of id
darc get-subscription-history --search core-sdk --limit 5

# Outcomes produced by a specific build
darc get-subscription-history --build <bar-build-id>

# Restrict to a date range (ISO 8601, treated as UTC)
darc get-subscription-history --id <guid> --after "2025-01-01T00:00:00Z" --before "2025-02-01T00:00:00Z"

# Machine-readable output for scripting/jq
darc get-subscription-history --id <guid> --output-format json
```

All filters can be combined.

### Step 3: Interpret and report

Each text outcome looks like:

```
2025-01-15 12:34:56Z  [Failure]  build 1234567
  Subscription: https://github.com/dotnet/runtime ==> 'https://github.com/dotnet/dotnet' ('main')
  Subscription Id: 510286a9-8cd5-47bd-a259-08d68641480a
  PR: https://github.com/dotnet/dotnet/pull/4242
  Failed to update dependencies: <details>
```

Summarize for the user: the timeline of outcomes (newest first), how many of
each `[Type]`, any recurring failures with their messages, and links to the PRs
that were opened. Outcome types:

| Type | Meaning |
|------|---------|
| `Updated` | Dependencies were updated; a PR was opened or updated. |
| `NoUpdate` | Nothing to update — already current. |
| `NotUpdatable` | The subscription could not be updated (e.g. config issue). |
| `Failure` | The update attempt failed. Read the message for the cause. |
| `UserError` | Failure caused by user/config input. |
| `HasConflict` | A merge conflict blocked the update. |
| `Rescheduled` | The update was deferred and will retry. |

## Options Reference

| Option | Description |
|--------|-------------|
| `--id` | Filter by subscription id (GUID). |
| `--build` | Filter by the BAR build id that triggered the outcome. |
| `--type` | Filter by outcome type (`Updated`, `NoUpdate`, `NotUpdatable`, `Failure`, `UserError`, `HasConflict`, `Rescheduled`). |
| `--search` | Free-text match against source repo, target repo and target branch. |
| `--after` / `--before` | Restrict to outcomes on/after or on/before a date (e.g. `"2025-01-15T12:00:00Z"`). |
| `--limit` | Max outcomes to return (1-1000, default 10). |
| `--output-format` | `text` (default) or `json`. |

## Validation

- `darc get-subscription-history --help` lists the verb and options → darc is
  current and authenticated.
- A successful run prints one or more outcome blocks (text) or a JSON array.
- "No subscription trigger outcomes found matching the specified criteria."
  means the filters matched nothing — broaden `--search`/date range or confirm
  the `--id` is correct via `darc get-subscriptions`.

## Common Pitfalls

- **GUID, not repo name, for `--id`.** A non-GUID value errors out. Use
  `--search` for repo/branch text matching.
- **Dates are UTC, ISO 8601.** Use a form like `"2025-01-15T12:00:00Z"`.
- **Default `--limit` is 10.** Increase it to see deeper history.
- **Old darc.** If the verb is unknown, re-run `eng/common/darc-init.ps1`
  (or `.sh`) to update darc — the command was added recently.
