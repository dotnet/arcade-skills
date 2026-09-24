# SQL Tracking for CI Investigations

Use the SQL tool to track structured data during complex investigations. This avoids losing context across tool calls and enables queries that catch mistakes (like claiming "all failures known" when some are unmatched).

## Failure Tracking

Track each distinct failure from the script output and map it to known issues as you verify them. This is a new table rather than an in-place change to the older `failed_jobs` example: a reused SQL session may already have that job-level table without a match-status column. Create this table once per session; if it already exists, reuse it instead of rerunning the `CREATE TABLE` statement.

```sql
CREATE TABLE ci_failures (
  build_id INT,
  job_name TEXT,
  failure_id TEXT,        -- unique within the job: test/work-item ID or distinct error
  error_category TEXT,   -- from failedJobDetails: test-failure, build-error, crash, etc.
  error_snippet TEXT,
  known_issue_url TEXT,  -- NULL for unknown coverage or verified unmatched
  known_issue_title TEXT,
  ba_match_status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (ba_match_status IN ('unknown', 'matched', 'unmatched')),
  is_pr_correlated BOOLEAN DEFAULT FALSE,
  recovery_status TEXT DEFAULT 'not-checked',  -- effectively-passed, real-failure, no-results
  notes TEXT,
  PRIMARY KEY (build_id, job_name, failure_id)
);
```

Do not collapse multiple failing tests/work items in one job into a single match verdict. If the script gives only job-level details, inspect the Helix work items or failure logs to identify distinct failures before assigning `ba_match_status`; otherwise leave coverage `unknown` for failures you cannot distinguish.

### Key queries

```sql
-- Failures with no Build Analysis verdict yet (pending or unavailable coverage)
SELECT build_id, job_name, failure_id, error_category FROM ci_failures
WHERE ba_match_status = 'unknown';

-- Verified unmatched failures in a report covering the build
SELECT build_id, job_name, failure_id, error_category, error_snippet FROM ci_failures
WHERE ba_match_status = 'unmatched';

-- Counts by match status; unknown is not a verified unmatched failure
SELECT ba_match_status, COUNT(*) AS failures
FROM ci_failures
GROUP BY ba_match_status;

-- Which crash/canceled jobs need recovery verification?
SELECT build_id, job_name, failure_id FROM ci_failures
WHERE error_category IN ('crash', 'unclassified') AND recovery_status = 'not-checked';

-- PR-correlated failures (fix before retrying)
SELECT build_id, job_name, failure_id, error_snippet FROM ci_failures WHERE is_pr_correlated = TRUE;
```

### Workflow

1. After the script runs, expand each `failedJobDetails` entry (with its `buildId`) into one row per distinct failing test, work item, or build error; identify each using a stable `failure_id` within its job
2. Read the relevant GitHub Build Analysis report (see [analysis-workflow.md](analysis-workflow.md#reading-the-build-analysis-check-report)); for each verified per-build, per-failure KBE match, including those already available in an in-progress report, set `ba_match_status = 'matched'` and store the issue URL on that failure
3. Set `ba_match_status = 'unmatched'` only after the completed report covers that build and confirms that specific failure is unmatched. Leave failures in pending, unavailable, or uncovered builds as `unknown`; a NULL `known_issue_url` alone is not evidence of an unmatched failure
4. Query unknown and verified unmatched failures separately; investigate the latter and report incomplete coverage for the former
5. For crash/canceled work items, update `recovery_status` after checking Helix results

## Build Progression

See [build-progression-analysis.md](build-progression-analysis.md) for the `build_progression` and `build_failures` tables that track pass/fail across multiple builds.

> **`ci_failures` vs `build_failures` — when to use each:**
> - `ci_failures` (above): **Failure-level** — maps each error/test/work item within an AzDO job to its own known-issue verdict. Use for single-build triage ("are all failures accounted for?").
> - `build_failures` (build-progression-analysis.md): **Test-level** — tracks individual test names across builds. Use for progression analysis ("which tests started failing after commit X?").

## PR Comment Tracking

For deep-dive analysis — especially across a chain of related PRs (e.g., dependency flow failures, sequential merge PRs, or long-lived PRs with weeks of triage) — store PR comments so you can query them without re-fetching:

```sql
CREATE TABLE IF NOT EXISTS pr_comments (
  pr_number INT,
  repo TEXT DEFAULT 'dotnet/runtime',
  comment_id INT PRIMARY KEY,
  author TEXT,
  created_at TEXT,
  body TEXT,
  is_triage BOOLEAN DEFAULT FALSE  -- set TRUE if comment diagnoses a failure
);
```

### Key queries

```sql
-- What has already been diagnosed? (avoid re-investigating)
SELECT author, created_at, substr(body, 1, 200) FROM pr_comments
WHERE is_triage = TRUE ORDER BY created_at;

-- Cross-PR: same failure discussed in multiple PRs?
SELECT pr_number, author, substr(body, 1, 150) FROM pr_comments
WHERE body LIKE '%BlazorWasm%' ORDER BY created_at;

-- Who was asked to investigate what?
SELECT author, substr(body, 1, 200) FROM pr_comments
WHERE body LIKE '%PTAL%' OR body LIKE '%could you%look%';
```

### When to use

- Long-lived PRs (>1 week) with 10+ comments containing triage context
- Analyzing a chain of related PRs where earlier PRs have relevant diagnosis
- When the same failure appears across multiple merge/flow PRs and you need to know what was already tried

## When to Use SQL vs. Not

| Situation | Use SQL? |
|-----------|----------|
| 1-2 failed jobs, all match known issues | No — straightforward, hold in context |
| 3+ failed jobs across multiple builds | Yes — prevents missed matches |
| Build progression with 5+ builds | Yes — see [build-progression-analysis.md](build-progression-analysis.md) |
| Crash recovery across multiple work items | Yes — cache testResults.xml findings |
| Single build, single failure | No — overkill |
| PR chain or long-lived PR with extensive triage comments | Yes — preserves diagnosis context across tool calls |
| Downloading artifacts from 2+ Helix jobs (e.g., binlog comparison) | Yes — see [helix-artifacts.md](helix-artifacts.md) |
