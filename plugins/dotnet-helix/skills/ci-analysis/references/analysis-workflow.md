# Analysis Workflow (Steps 1–3)

After completing Step 0 (Gather Context — see SKILL.md), follow these steps.

## Step 1: Run the Script

Run with `-ShowLogs` for detailed failure info. See [script-modes.md](script-modes.md) for parameter details.

## Step 1b: Investigate with AzDO Tools

When the script output is insufficient (e.g., build timeline fetch fails), use AzDO MCP tools to query builds directly. **Match the org from the build URL to the correct AzDO tools** — see [azdo-helix-reference.md](azdo-helix-reference.md#azure-devops-organizations). PR builds are in `dnceng-public`; internal builds are in `dnceng`.

## Reading the Build Analysis Check Report

Use AzDO/Helix tools for build and failure details, but use the **GitHub Build Analysis check report** for KBE matches. `azdo_build_analysis` `knownIssues` is derived from AzDO tags/timeline; its empty array and timeline `unmatchedFailures` do not tell you what Build Analysis matched. The script's `[CI_ANALYSIS_SUMMARY]` `knownIssues` can also be empty when it cannot read the report; do not treat an empty array as a negative finding.

1. Identify the PR/repo and the AzDO build ID(s) under investigation. Find the PR's head SHA (for example, `gh pr view PR --repo OWNER/REPO --json headRefOid --jq .headRefOid`) and inspect its check runs:

   ```bash
   gh api --paginate "repos/OWNER/REPO/commits/SHA/check-runs?per_page=100" \
     --jq '.check_runs[] | select(.name == "Build Analysis") | {id, html_url, status, conclusion, completed_at, output: .output}'
   ```

   Use the check's `html_url` to read it on GitHub, or read its `output.summary` and `output.text` from this response (the report may contain HTML markup). `gh pr checks` can help locate the check, but its `link` may point to Build Analysis documentation rather than the report. Paginate: busy PRs can have more check runs than one page.
2. Match known-error entries (linked KBE issue plus build/job/test) and unmatched-error entries to the AzDO timeline and Helix failures by **specific AzDO build ID**. Build Analysis updates its check as each pipeline completes: even when the check's `status` is `in_progress`, a linked KBE match for a finished pipeline is evidence for that build. Report it now, identifying the build, while labeling other builds/pipelines still pending as incomplete. A PR can have several pipelines, builds, or commits; a check on the latest head may not cover an older build. For historical builds, locate the corresponding check on the relevant PR head commit/checks view instead of attributing current-head matches to them. AzDO's `sourceVersion` can be a PR merge commit, not the PR head SHA; use report build links to verify the association. Do not assume a Helix failure can be matched before its own AzDO pipeline finishes.
3. If the check is absent or unreadable, say **Build Analysis unavailable**. If it is in progress or lists the relevant pipeline as pending, report any already linked matches for completed builds but say **Build Analysis incomplete for the remaining build(s)**; absence of a match in a partial report does not mean zero matches. Only if the check is `completed`, its report covers the specific finished build, and that build has no KBE matches should you say **zero Build Analysis matches for that build**. An overridden green check is not proof every failure matched; read the report and its override note, and verify coverage before recommending a retry.

## Step 2: Analyze Results

1. **Check Build Analysis** — Use the check report for per-build KBE matches, including matches already present while the check is in progress; wait for complete coverage before concluding a failure has no match. Do not infer coverage from check color alone (it may be overridden), AzDO `knownIssues`, or an empty script summary. For 3+ failures, use SQL tracking to avoid missed matches (see [sql-tracking.md](sql-tracking.md)).
2. **Correlate with PR changes** — Same files failing = likely PR-related
3. **Compare with baseline** — If a test passes on the target branch but fails on the PR, compare Helix binlogs. See [binlog-comparison.md](binlog-comparison.md) — **delegate binlog download/extraction to subagents** to avoid burning context on mechanical work.
4. **Check build progression** — If the PR has multiple builds (multiple pushes), check whether earlier builds passed. A failure that appeared after a specific push narrows the investigation to those commits. See [build-progression-analysis.md](build-progression-analysis.md). Present findings as facts, not fix recommendations.
5. **Interpret patterns** (but don't jump to conclusions):
   - Same error across many jobs → Real code issue
   - Build Analysis flags a known issue → That *specific failure* is safe to retry (but others may not be)
   - Failure is **not** in Build Analysis → Investigate further before assuming transient
   - Device failures, Docker pulls, network timeouts → *Could* be infrastructure, but verify against the target branch first
   - Test timeout but tests passed → Executor issue, not test failure
6. **Check for mismatch with user's question** — The script only reports builds for the current head SHA. If the user asks about a job, error, or cancellation that doesn't appear in the results, **ask** if they're referring to a prior build. Common triggers:
   - User mentions a canceled job but `canceledJobNames` is empty
   - User says "CI is failing" but the latest build is green
   - User references a specific job name not in the current results
   Offer to re-run with `-BuildId` if the user can provide the earlier build ID from AzDO.

## Step 3: Verify Before Claiming

Before stating a failure's cause, verify your claim:

- **"Infrastructure failure"** → Did Build Analysis flag it? Does the same test pass on the target branch? If neither, don't call it infrastructure.
- **"Transient/flaky"** → Has it failed before? Is there a known issue? A single non-reproducing failure isn't enough to call it flaky.
- **"PR-related"** → Do the changed files actually relate to the failing test? Correlation in the script output is heuristic, not proof.
- **"Safe to retry"** → Are ALL failures accounted for (known issues or verified infrastructure), or are you ignoring some? Check the relevant Build Analysis report's entries and coverage, not just the status. Map each failing job to a specific issue or other evidence before concluding "safe to retry."
- **"Not related to this PR"** → Have you checked if the test passes on the target branch? Don't assume — verify.
