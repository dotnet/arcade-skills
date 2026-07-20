---
name: helix-cli
description: >
  Investigate .NET CI failures using the hlx CLI tool via bash.
  USE FOR: checking Helix job status, searching build logs, downloading
  test results, AzDO build timeline analysis — when MCP tools aren't
  loaded or when scripting with JSON output and jq. This is the
  context-efficient default: it pays no MCP tool-schema cost up front.
  DO NOT USE FOR: tasks where the Helix/AzDO MCP tools are already
  available in context (prefer the ci-analysis / helix-investigation
  skills from the dotnet-helix plugin when that MCP server is loaded).
  INVOKES: bash (hlx CLI commands with --json output).
allowed-tools: shell
---
# Helix CLI

Investigate Helix and Azure DevOps CI failures with `hlx` when you want shell pipelines, `--json`, and `jq` without loading the MCP toolset into context.

## When to Use This Skill

Use this skill when:

- You want `hlx describe` as the fastest first step to understand which MCP-equivalent investigation commands exist before drilling into help or schemas.
- Helix/AzDO MCP tools are not loaded, but `hlx` is installed or available via `dotnet run`.
- You want to script investigations with shell pipelines, `--json`, and optionally `jq`.
- You need to move quickly through a build → timeline → logs → tests workflow without paying the context cost of loading many tools.
- You are working in a plain terminal, CI job, or one-off bash session where CLI output is easier than MCP round-trips.

Prefer the MCP tools or the `ci-analysis` / `helix-investigation` skills (in the `dotnet-helix` plugin) when those tools are already loaded in context. The CLI is the context-efficient fallback.

## Installation

```bash
dotnet tool install -g lewing.helix.mcp
```

Local repo fallback:

```bash
dotnet run --project src/HelixTool -- <command>
```

Examples in this skill use `hlx`; replace it with the local `dotnet run` form if needed.

## Authentication

`hlx` supports anonymous access for public data and explicit auth for private Helix/AzDO.

- Helix: set `HELIX_ACCESS_TOKEN=...` or run `hlx login`; `hlx logout` removes the stored token.
- AzDO: resolution order is `AZDO_TOKEN` → Azure CLI / `az login` → `az account get-access-token` → anonymous for public projects such as `dnceng-public/public`.
- Useful checks:

```bash
hlx auth-status
hlx azdo auth-status --json
```

## Progressive Discovery

```bash
hlx describe
hlx describe azdo search-log
hlx azdo search-log --schema
hlx azdo search-log --help
```

1. `hlx describe` — routing: which command handles what?
2. `hlx describe <command>` — usage: parameters, defaults, and `--schema` hints.
3. `hlx <command> --schema` — full JSON output shape (when you need exact nesting).
4. `<command> --help` — all flags and arguments.

`hlx llms-txt` still exists for compact CLI notes, but `describe` is now the recommended discovery path for agents. There is no `hlx ci-guide` CLI command yet; use `helix_ci_guide(repo)` / `ci://profiles` when MCP is available.

## Common Patterns

### 1. Find recent builds for a PR

```bash
hlx azdo builds --pr-number 118282 --top 5 --json
```

Get build IDs before drilling into timeline, logs, or test runs.

### 2. Show only the failing parts of a build timeline

```bash
hlx azdo timeline 12345678 --filter failed --json
```

Use this to surface failed jobs/tasks and the `log.id` values needed for targeted log reads.

### 3. Search ranked AzDO logs without knowing the failing step yet

```bash
hlx azdo search-log 12345678 --pattern error --max-matches 20 --json
```

When `--log-id` is omitted, `hlx` searches ranked build logs across the build.

### 4. Drill into one specific AzDO log step

```bash
hlx azdo log 12345678 42 --tail-lines 300
```

Run this after `timeline` or `search-log` identifies a promising `log.id`.

### 5. Pivot from build failure to Helix job details

```bash
hlx status 02d8bd09-9400-4e86-8d2b-7a6ca21c5009 all --json
hlx work-item 02d8bd09-9400-4e86-8d2b-7a6ca21c5009 "System.Net.Tests" --json
hlx files 02d8bd09-9400-4e86-8d2b-7a6ca21c5009 "System.Net.Tests"
```

Use this when the failure signal lives in Helix work items rather than AzDO orchestration.

### 6. Pull structured test results before scraping logs

```bash
hlx azdo test-runs 12345678 --json
hlx azdo test-results 12345678 987654 --json
```

If the work item uploaded test results to Helix instead, use:

```bash
hlx parse-uploaded-trx 02d8bd09-9400-4e86-8d2b-7a6ca21c5009 "System.Net.Tests"
```

### 7. Check auth before assuming the service is broken

```bash
hlx auth-status
hlx azdo auth-status --json
```

Do this early when a public build works for others but fails locally.

## Chaining with jq

Examples below assume `jq` is available; if it is not, plain CLI output is still useful.

```bash
# Failed work items (.failed[].Name, .failed[].failureCategory, .failed[].ConsoleLogUrl)
hlx status "$JOB" all --json \
  | jq -r '.failed[] | [.Name, .failureCategory, .ConsoleLogUrl] | @tsv'

# Recent builds (.[] .id, .definition.name, .sourceBranch, .triggerInfo["pr.number"])
hlx azdo builds --pr-number 118282 --top 20 --json \
  | jq -r '.[] | select(.result == "failed") | [.id, .definition.name, .sourceBranch, (.triggerInfo // {} | .["pr.number"] // "-")] | @tsv'

# Failed timeline records (.records[].type, .records[].name, .records[].log.id)
hlx azdo timeline "$BUILD" --filter failed --json \
  | jq -r '.records[] | select(.log != null) | [.type, .name, (.log.id | tostring)] | @tsv'

# Ranked AzDO log hits (.steps[].logId, .steps[].stepName, .steps[].stepResult, .steps[].matchCount)
hlx azdo search-log "$BUILD" --pattern error --max-matches 20 --json \
  | jq -r '.steps[] | [.logId, .stepName, .stepResult, (.matchCount | tostring)] | @tsv'

# Failed tests (.[] .id, .testCaseTitle, .outcome, .automatedTestName)
hlx azdo test-results "$BUILD" "$RUN" --json \
  | jq -r '.[] | [.id, .testCaseTitle, .outcome, .automatedTestName] | @tsv'
```

`hlx azdo builds --json` returns a bare array. `hlx search-log` (Helix) is text output only in the CLI; use MCP `helix_search` for structured matches.

## Cache

`hlx` uses a shared SQLite-backed cache across CLI and stdio MCP usage. Use `hlx cache status` to inspect the current auth context and `hlx cache clear` to wipe all contexts. Full TTL and sizing details live in `hlx llms-txt`.
