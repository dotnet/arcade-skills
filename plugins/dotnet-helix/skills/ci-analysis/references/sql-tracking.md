# SQL Tracking for CI Investigations

Use the SQL tool to track structured data during complex investigations. This avoids losing context across tool calls and enables queries that catch mistakes (like claiming "all failures known" when some are unmatched).

## Failed Job Tracking

Track each failure from the script output and map it to known issues as you verify them:

```sql
CREATE TABLE IF NOT EXISTS failed_jobs (
  build_id INT,
  job_name TEXT,
  error_category TEXT,   -- from failedJobDetails: test-failure, build-error, crash, etc.
  error_snippet TEXT,
  known_issue_url TEXT,  -- NULL for unknown coverage or verified unmatched
  known_issue_title TEXT,
  ba_match_status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (ba_match_status IN ('unknown', 'matched', 'unmatched')),
  is_pr_correlated BOOLEAN DEFAULT FALSE,
  recovery_status TEXT DEFAULT 'not-checked',  -- effectively-passed, real-failure, no-results
  notes TEXT,
  PRIMARY KEY (build_id, job_name)
);
```

### Key queries

```sql
-- Failures with no Build Analysis verdict yet (pending or unavailable coverage)
SELECT build_id, job_name, error_category FROM failed_jobs
WHERE ba_match_status = 'unknown';

-- Verified unmatched failures in a report covering the build
SELECT build_id, job_name, error_category, error_snippet FROM failed_jobs
WHERE ba_match_status = 'unmatched';

-- Counts by match status; unknown is not a verified unmatched failure
SELECT ba_match_status, COUNT(*) AS jobs
FROM failed_jobs
GROUP BY ba_match_status;

-- Which crash/canceled jobs need recovery verification?
SELECT job_name, build_id FROM failed_jobs
WHERE error_category IN ('crash', 'unclassified') AND recovery_status = 'not-checked';

-- PR-correlated failures (fix before retrying)
SELECT job_name, error_snippet FROM failed_jobs WHERE is_pr_correlated = TRUE;
```

### Workflow

1. After the script runs, insert one row per failed job from `failedJobDetails` (each entry includes `buildId`)
2. Read the relevant GitHub Build Analysis report (see [analysis-workflow.md](analysis-workflow.md#reading-the-build-analysis-check-report)); for each verified per-build KBE match, including those already available in an in-progress report, set `ba_match_status = 'matched'` and store the issue URL on the corresponding job
3. Set `ba_match_status = 'unmatched'` only after the completed report covers that build and confirms its failure is unmatched. Leave jobs in pending, unavailable, or uncovered builds as `unknown`; a NULL `known_issue_url` alone is not evidence of an unmatched failure
4. Query unknown and verified unmatched failures separately; investigate the latter and report incomplete coverage for the former
5. For crash/canceled jobs, update `recovery_status` after checking Helix results

## Build Progression

See [build-progression-analysis.md](build-progression-analysis.md) for the `build_progression` and `build_failures` tables that track pass/fail across multiple builds.

> **`failed_jobs` vs `build_failures` — when to use each:**
> - `failed_jobs` (above): **Job-level** — maps each failed AzDO job to a known issue. Use for single-build triage ("are all failures accounted for?").
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
