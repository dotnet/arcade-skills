---
name: cross-repo-validation
description: "Coordinate product/test owners across repositories: build handoffs, candidate changes, launch authorization, complete-first-pass collection, and physical executions versus unique cases and overlapping coverage groups. Not for CI triage, codeflow, publishing or implementing test harnesses."
---

# Cross-Repository Validation

Record permission, exact inputs, actual execution and supported conclusions.
Build/test implementation stays in its own repository; no tool or plugin is
required. Answer questions directly with only relevant controls, not the whole
workflow. Actual execution still requires every applicable check below.

## Terms used in records

| Term | Meaning |
|------|---------|
| Candidate / harness | Exact product build / test scripts, data, tools and executable |
| Manifest | Inventory of files, source identity and content hashes |
| Operation | Overall validation task, with one ID across revisions |
| Generation / plan revision | Version of task inputs / instructions and selected tests |
| Authorization | User permission for specific actions and inputs; `HOLD` means do not launch |

**Immutable** records are never overwritten; changes get new versions/references.
A manifest, available resources or cleanup approval is not test authorization.

## Roles and inputs

The **product owner** owns source, builds and a coherent frozen candidate.
The **test owner** owns harness preparation, exact case/data/mode selection,
launch checks, execution, evidence, restoration and owned-process cleanup.
One agent may hold both roles; a handoff does not transfer these responsibilities.

Identify both owners. Quote the user's scope, permissions and stop conditions;
separate decisions from agent suggestions. Link operation/generation, versioned
plan, both manifests, authorization and evidence. Obtain repository-owned
build/launch, runtime-selection and safe-stop procedures, required access and
evidence locations. Missing inputs block launch; do not invent them.

Read [record templates and examples](references/records.md) when preparing a
handoff or result: they specify inventories, record fields and overlap examples.
Keep private records in repository/session artifacts, not this public plugin.

## Workflow

### 1. Establish identity and authorization

Distinguish *proposed*, *queued*, *running* and *finished* work. Keep one authoritative
current-state record pointing to the plan, candidate, harness and permission/HOLD.
Increase its revision number on every update.

1. Bind authorization, its source and scope to the exact operation, generation,
   plan, candidate and harness. A generic "GO" or cleanup approval is insufficient.
2. Input, scope or policy changes get new records and a generation/plan revision.
   A proposal alone changes neither current state nor authorization. When an
   authorized replacement is adopted, supersede old queued work; never silently
   retarget it. New inputs need their own authorization. Unclear replacement
   status blocks launch.
3. Before **each physical launch**, re-read current state: the full combination
   must remain current and authorized, with no later HOLD/stop/replacement.
   Recheck actual executable and runtime identity. Unreadable state or mismatched
   inputs means do not launch. Record checked revision and launch time.
4. Checking state then starting a process is **not atomic**: a HOLD can arrive
   between them (a race). Preventing this needs a real launch gate coordinating
   permission changes and process creation as one protected action. A document
   cannot enforce that; disclose the gap and obey later stops.

Preserve tool-provided assignment IDs only for real assignments; never invent
them from peer-session IDs. Operation IDs correlate records, not tool assignments.

### 2. Save the exact build and test setup

The product manifest captures commit **plus** tracked patches/untracked build
inputs, build commands/logs, OS/architecture, per-component configurations and
hashes of binaries, libraries, symbols and supporting files. Explain missing or
inapplicable items. A commit stamp alone does not cover uncommitted source.

Save an immutable copy or content-hashed bundle, not mutable build output.
An **overlay** replaces some files in an existing build: identify its base,
replaced/retained files, matching symbols and evidence of one coherent build.
Copying new binaries alone proves no coherence.

The harness manifest captures test source/edits, tools, settings, resolved cases,
data/modes and actual host/executable identity. A **selector** is a test name or
filter: save both selector and resolved files. The same selector choosing a
different host invalidates setup until reconciled.

Pin exact runtime/dependency versions, architecture, component settings,
environment overrides and **roll-forward** (automatic version substitution).
Verify actually loaded modules/packages, runtime and host from execution evidence,
not requested settings or PATH. Exchange manifest references, not inventories.
Reuse a verified candidate while applicable.

### 3. Choose when to stop; keep diagnosis separate

A **collection policy** determines whether the first pass stops after failure:

| Policy | Required behavior |
|--------|-------------------|
| `complete-first-pass` | Run every authorized case/data/mode once, continuing independent cases after failures; mark unreachable cases individually. Safety/user stops still win. |
| `fail-fast` | Stop at the agreed failure boundary; report the remainder as not reached/not run, never passed. |

Never silently change policy or add scope. Preserve assertions, logs and historical
runs. Label the planned pass **acceptance**, investigations `diagnostic`, and
invalid-setup corrections `setup-correction`. Link extra runs to originals and
obtain any additional authorization. Corrections do not erase invalid runs;
retries for green do not establish first-pass success.

### 4. Execute, stop, and restore

Record exact commands, working directory/environment, start/end times, exit status,
raw logs and selected tests. **Reached subchecks** are steps confirmed to have
executed, such as load/roundtrip/compare. Tool success proves neither target
execution nor outcome.

HOLD/stop revokes queued launches immediately. Apply the agreed running-work
policy: stop safely or finish only explicitly permitted in-flight collection.
User/safety stops override completeness. Without a policy, stop safely and block
new launches. Preserve partial evidence.

Track owned process IDs/children; never kill unrelated processes. Snapshot
configuration, restore owned changes without overwriting concurrent edits, and
verify restoration and cleanup. Failures are blockers. Cleanup releases no HOLD
and authorizes no new generation.

### 5. Classify outcomes and coverage

Separate execution state from the requested verdict:

| Outcome | Meaning |
|---------|---------|
| `setup-invalid` | Wrong/missing candidate, runtime, host, harness or prerequisites; no product conclusion |
| `product-failure-before-operation` | Verified setup; product fails before the requested operation, so its symptom remains not reached |
| `symptom-reproduced` | Requested operation reached; evidence meets the symptom criterion |
| `symptom-not-reproduced` | Valid setup and required subchecks reached; symptom absent within this scope |
| `not-reached` / `not-run` | Step unreachable / no launch; neither is a pass |
| `blocked` / `interrupted` | Permission, infrastructure, stop or replacement prevents completion; retain observed outcomes |

Define success as well as the failure symptom; absence of a symptom alone is not
a pass. Report tool return, actual target execution, observed configuration,
reached subchecks and verified outcome separately. Unknown stays unknown.

Count **physical executions** (launches) separately from unique cases and
**tuples** (case/data/mode/configuration combinations). Coverage groups are named
sets of tuples; membership in several groups does not imply several executions.
Explicitly report every requested total:

- Physical launches: total and acceptance/diagnostic/setup-correction breakdown.
- Unique coverage: distinct case IDs and distinct tuples.
- Groups: total memberships (sum of sizes), intersections and deduplicated union.

Do not leave totals to reader arithmetic. Diagnostic reruns add executions, not
unique coverage. Use the overlap example in the records reference when needed.

### 6. Publish once; message only to change an action

Write one final report (**terminal summary**) linking plan, manifests, results,
commands/raw logs, coverage/gaps and restoration/cleanup evidence. State any
remaining decision. Send its reference once; revise only for changed evidence or
next action. Never resend unchanged final reports/hashes.

Message only to change the recipient's next action: permission, replacement/stop,
actionable blocker, requested evidence, material correction or completion.

```text
event: completion
operation: compatibility-check
generation: 2
plan: artifacts/plan-v2.yaml
result: artifacts/result-v1.md
next-action: product owner reviews the recorded failure before proposing changes
```

Avoid acknowledgement loops, repeated HOLD/readiness and duplicate progress.
Reference durable records; inaccessible artifacts are blockers, not permission
to copy private inventories or widen access. Before reporting, verify each
requested tuple has evidence or an explicit gap, counts reconcile, and cleanup
is verified or blocked.
