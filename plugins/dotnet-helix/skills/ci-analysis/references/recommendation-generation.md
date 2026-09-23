# Generating Recommendations

After the script outputs the `[CI_ANALYSIS_SUMMARY]` JSON block, **you** synthesize recommendations. Do not parrot the JSON — reason over it.

## Decision Logic

Read `recommendationHint` as a starting point, then layer in context:

| Hint | Action |
|------|--------|
| `BUILD_SUCCESSFUL` | No failures. Confirm CI is green. |
| `KNOWN_ISSUES_DETECTED` | Known tracked issues found — but this does NOT mean all failures are covered. Read the relevant Build Analysis check report, including in-progress reports with linked matches for completed builds; mark other builds pending rather than unmatched. Check status alone can be overridden. |
| `LIKELY_PR_RELATED` | Failures correlate with PR changes. Lead with "fix these before retrying" and list `correlatedFiles`. |
| `POSSIBLY_TRANSIENT` | Failures could not be automatically classified — does NOT mean they are transient. Use `failedJobDetails` to investigate each failure individually. |
| `REVIEW_REQUIRED` | Could not auto-determine cause. Review failures manually. If the relevant Build Analysis report leaves failures unmatched and they are not PR-related, suggest considering a Known Build Error issue — see [kbe-issue-creation.md](kbe-issue-creation.md). |
| `MERGE_CONFLICTS` | PR has merge conflicts — CI won't run. Tell the user to resolve conflicts. Offer to analyze a previous build by ID. |
| `NO_BUILDS` | No AzDO builds found (CI not triggered). Offer to check if CI needs to be triggered or analyze a previous build. |

## Refining with Context

Refine the recommendation with context the heuristic can't capture:

- **Unmatched novel failures**: A completed Build Analysis report covers the build but leaves failures unmatched, and they don't match any existing issue or PR correlation → suggest the user consider filing a Known Build Error issue. If the report is unavailable/incomplete, report any explicit matches for completed pipelines, but investigate the rest rather than claiming a BA mismatch from absent entries. **Before drafting any issue, you MUST first**: (1) download/extract the actual failure log, (2) run `scripts/Test-KnownIssuePattern.ps1 -ErrorMessage "<pattern>" -LogFile <log>` (or `-ErrorPattern` for regex), (3) confirm the script outputs `RESULT: PASS`. Only then draft a `gh issue create` command. Do NOT skip validation — patterns that look correct often don't match due to invisible characters, line breaks, or log formatting. See [kbe-issue-creation.md](kbe-issue-creation.md).
- **Mixed signals**: Some failures match known issues AND some correlate with PR changes → separate them. Known issues = safe to retry; correlated = fix first.
- **Canceled jobs with recoverable results**: If `canceledJobNames` is non-empty, mention that canceled jobs may have passing Helix results (see [failure-interpretation.md](failure-interpretation.md) — Recovering Results).
- **Build still in progress**: If `lastBuildJobSummary.pending > 0`, note that more failures may appear.
- **Multiple builds**: If `builds` has >1 entry, `lastBuildJobSummary` reflects only the last build — use `totalFailedJobs` for the aggregate count.
- **BuildId mode**: `knownIssues` and `prCorrelation` won't be populated by the script. If you have the PR, read its relevant GitHub Build Analysis check report separately; otherwise say "Build Analysis and PR correlation not available in BuildId mode."

## How to Retry

- **AzDO builds**: Comment `/azp run {pipeline-name}` on the PR (e.g., `/azp run dotnet-sdk-public`)
- **All pipelines**: Comment `/azp run` to retry all failing pipelines
- **Helix work items**: Cannot be individually retried — must re-run the entire AzDO build

## Tone and Output Format

Be direct. Lead with the most important finding. Structure your response as:
1. **Summary verdict** (1-2 sentences) — Is CI green? Failures PR-related? Known issues?
2. **Failure summary table** — narrow columns only (Job, Verdict, Issue). Keep job names short (drop redundant prefixes like `runtime-dev-innerloop`). Do NOT put error text or work item lists in the table — those go in the detail section below.
3. **Failure details** — one bullet per failure with error description, affected work items, and evidence
4. **Recommended actions** (numbered) — retry, fix, investigate. Include `/azp run` commands.

**Use markdown links** for PRs, issues, builds, and jobs so they're clickable: `[#121195](url)`, `[Build 1305302](url)`, `[job name](azdo-job-url)`. The script output and MCP tools provide the URLs — thread them through to your response.

Example layout for step 2+3:

```
| # | Job | Verdict | Issue |
|---|-----|---------|-------|
| 1 | [browser-wasm linux Release WasmBuildTests](https://dev.azure.com/…) | Known flaky ✅ | [#121195](https://github.com/dotnet/runtime/issues/121195) |
| 2 | [linux-x64 Debug Mono Interpreter LibTests](https://dev.azure.com/…) | Known flaky ✅ | [#100800](https://github.com/dotnet/runtime/issues/100800) |
| 3 | [coreclr Pri0 Runtime Tests linux x64](https://dev.azure.com/…) | Known flaky ✅ | [#110173](https://github.com/dotnet/runtime/issues/110173) |

**Details:**
- **#1**: Playwright.TargetClosedException + dbus socket missing in WBT-NoWorkload
- **#2**: 8 work items (ComInterfaceGen, IntrinsicsInSPC, JSImportGen, …) — all exit code 139 (SIGSEGV), mono interpreter crashes
- **#3**: stackoverflowtester timeout in baseservices-exceptions — ASSERT: "Target stack has been corrupted"
```

Synthesize from: JSON summary (structured facts) + human-readable output (details/logs) + Step 0 context (PR type, author intent).
