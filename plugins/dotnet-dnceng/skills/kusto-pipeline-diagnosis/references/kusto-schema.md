# Kusto Schema & Query Reference

Reference for the `engsrvprod` cluster, `engineeringdata` database. Discover the
live schema at any time with `<table> | getschema`.

## TimelineBuilds — one row per build

| Column         | Type     | Notes                                                        |
|----------------|----------|--------------------------------------------------------------|
| `BuildId`      | int      | Primary key; join key to `TimelineRecords`.                  |
| `Status`       | string   | e.g. `completed`.                                            |
| `Result`       | string   | `succeeded`, `failed`, `canceled`, `partiallySucceeded`.     |
| `Repository`   | string   | Repo name (e.g. `dotnet-dotnet`).                            |
| `Reason`       | string   | `schedule`, `batchedCI`, `pullRequest`, `manual`, ...        |
| `BuildNumber`  | string   | e.g. `20260604.17`.                                          |
| `QueueTime`    | datetime | When queued.                                                 |
| `StartTime`    | datetime | When the build started running.                              |
| `FinishTime`   | datetime | When the build finished.                                     |
| `Project`      | string   | AzDO project (e.g. `internal`, `public`).                    |
| `DefinitionId` | int      | Pipeline definition id (e.g. `1330` = dotnet-unified-build). |
| `Definition`   | string   | Pipeline path/name.                                          |
| `SourceBranch` | string   | `main` or `refs/heads/main`; PRs use `refs/pull/<n>/merge`.  |
| `TargetBranch` | string   | PR target branch, if applicable.                             |
| `Organization` | string   | AzDO org (e.g. `dnceng`).                                     |

## TimelineRecords — one row per timeline node

| Column         | Type     | Notes                                                          |
|----------------|----------|----------------------------------------------------------------|
| `BuildId`      | int      | Join key to `TimelineBuilds`.                                  |
| `RecordId`     | string   | Node id.                                                       |
| `ParentId`     | string   | Parent node's `RecordId` (tree linkage).                       |
| `Path`         | string   | Dotted path; depth = level (see below).                        |
| `Order`        | int      | Sibling ordering.                                              |
| `Name`         | string   | Stage/job/step display name.                                   |
| `Result`       | string   | `succeeded`, `failed`, `skipped`, ...                          |
| `ResultCode`   | string   | Extra detail (e.g. skip reason).                               |
| `TaskName`     | string   | Non-empty on leaf task records (e.g. `CmdLine`).               |
| `TaskVersion`  | string   | Task version.                                                  |
| `LogUri`       | string   | AzDO REST URL to the node's log (`dev.azure.com`).             |
| `StartTime`    | datetime | Node start.                                                    |
| `FinishTime`   | datetime | Node finish.                                                   |
| `ErrorCount`   | int      | Unreliable — often `0` on failed records. Prefer `Result`.     |
| `WarningCount` | int      | Warning count.                                                 |
| `WorkerName`   | string   | Agent/pool worker.                                             |
| `Attempt`      | int      | Retry attempt.                                                 |
| `TimelineId`   | string   | Timeline id.                                                   |

### Path depth = hierarchy level

| Depth | Example           | Level               | `TaskName` populated? |
|-------|-------------------|---------------------|-----------------------|
| 1     | `004`             | Stage               | no                    |
| 2     | `004.002`         | Job                 | no                    |
| 3     | `004.002.001`     | Job phase / attempt | no                    |
| 4     | `004.002.001.018` | Task / step (leaf)  | yes (mostly)          |

Compute depth with `array_length(split(Path, '.'))`.

## Useful queries

### Discover a pipeline's identity (disambiguate a DefinitionId or name)

```kusto
TimelineBuilds
| where DefinitionId == <definitionId> and StartTime > ago(90d)   // or: Definition has '<name fragment>'
| summarize Builds = count(), LastBuild = max(StartTime)
        by Organization, Project, Definition, DefinitionId
| sort by LastBuild desc
```

### Pass/fail breakdown for a definition over time

```kusto
TimelineBuilds
| where DefinitionId == <definitionId>
        and Project == '<project>' and Organization == '<organization>'
        and StartTime > ago(7d)
| where SourceBranch in ('main', 'refs/heads/main')
| summarize Builds = count() by Result
```

### Result counts within a single build

```kusto
TimelineRecords
| where BuildId == <buildId>
| summarize count() by Result
```

### Failing leaf steps for one build (root causes only)

```kusto
TimelineRecords
| where BuildId == <buildId> and Result == 'failed' and isnotempty(TaskName)
| project Path, Name, TaskName, StartTime, FinishTime, LogUri
```

### Distribution of records by level for a build

```kusto
TimelineRecords
| where BuildId == <buildId>
| extend Depth = array_length(split(Path, '.'))
| summarize Count = count(), Leaves = countif(isnotempty(TaskName)) by Depth
| sort by Depth asc
```

### Slowest failing steps across recent builds (two queries, no join)

First get the failed build ids:

```kusto
TimelineBuilds
| where DefinitionId == <definitionId>
        and Project == '<project>' and Organization == '<organization>'
        and Result == 'failed' and StartTime > ago(14d)
| distinct BuildId
```

Then feed them into a records query:

```kusto
TimelineRecords
| where BuildId in (<buildId1>, <buildId2>, ...)
        and Result == 'failed' and isnotempty(TaskName)
| extend DurationMin = datetime_diff('minute', FinishTime, StartTime)
| distinct BuildId, Name, DurationMin, LogUri
| top 20 by DurationMin desc
| project Name, DurationMin, LogUri
```

## Tips

- **Run sequenced queries, not joins**: query `TimelineBuilds` for `BuildId`s, then a `TimelineRecords` query with `in (...)`.
- **Dedupe**: both tables have multiple snapshot rows per build — use `distinct` (or `summarize ... by BuildId`).
- Filter to `Reason == 'schedule'` for rolling builds to remove PR-branch noise.
- `SourceBranch` is `main` on some builds and `refs/heads/main` on others — match both.
- Use `ago(Nd)` / `StartTime > datetime(...)` to bound time ranges and keep queries fast.
- `datetime_diff('minute', FinishTime, StartTime)` gives step/build duration in minutes.
- There is no `Type` column on `TimelineRecords`; classify nodes by `Path` depth.
