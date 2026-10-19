---
name: cross-repo-validation
description: "Coordinate product and test owners across repositories with recorded permissions, exact build and test identities, concise handoffs and linked evidence. Use for local build handoffs to another repo's tests, candidate changes, complete-first-pass collection, and counting physical executions versus unique cases and overlapping coverage groups. Not for CI triage, codeflow, publishing or implementing test harnesses."
---

# Cross-Repository Validation

Record what was permitted, what actually ran, and what the evidence proves.
Both owners use this protocol, even if one agent holds both roles. Build and test
implementation stays in its own repository; no particular tool or plugin is required.

For a question, answer the requested decision first and explain only the relevant
controls. Include the records needed for that request, not every record below.
For example, a build handoff checklist needs provenance and matching files, not
the full scheduling lifecycle. For actual execution, all applicable launch,
evidence and cleanup checks below remain mandatory.

## Terms used in records

| Term | Meaning |
|------|---------|
| Candidate | The exact product build being tested |
| Harness | The test scripts, data, tools and executable used to run the tests |
| Manifest | An inventory identifying those files, their sources and content hashes; link detailed logs rather than copying them into messages |
| Operation | The overall validation task, with one ID across its revisions |
| Generation / plan revision | A numbered version of the task's inputs / its instructions and selected tests |
| Authorization | Permission from the user for specific actions and inputs; `HOLD` means do not launch, regardless of readiness or cleanup approval |

An **immutable** record is a saved version that is never overwritten. Changes get
a new version and reference. A manifest is not permission to execute its contents.

## Roles and inputs

| Role | Owns | Must not assume |
|------|------|-----------------|
| Product owner | Source, build, matching product files, saved candidate and manifest | Handoff authorizes tests or selects harness cases |
| Test owner | Harness, test selection, launch checks, execution, evidence, restoring configuration and cleaning up owned processes | Availability, cleanup or agent suggestions grant launch permission |

Every shared handoff identifies the owners and links the candidate and harness
manifests, authorization, and supporting evidence. Repository-owned scripts
remain with those owners; the protocol records their inputs and results.

Before execution, identify both owners and obtain:

- The user's actual request: permitted actions, repositories, cases, candidate,
  resources, cleanup and stop conditions. Quote it; separate decisions from suggestions.
- Operation ID, generation, saved plan version, candidate manifest and
  harness manifest references accessible to both owners.
- Repository-owned procedures: build/launch commands, runtime selection mechanism,
  evidence locations, required access, and safe stop/restoration procedures.
  Resolve missing inputs before launch; do not invent commands or permissions.

Use [record templates and examples](references/records.md) in repository/session
artifact storage, not message bodies. Never publish private records or widen access.

## Workflow

### 1. Establish identity and authorization

Record the task and input versions, owners, permitted tests and manifests. Agree
whether to stop after a failure and how to handle running work when plans change.
Distinguish *proposed*, *queued*, *running* and *finished* work.

Keep one agreed current-state record pointing to the latest plan, candidate and
harness, with the current permission or HOLD. Increase its revision number on
every update so launch checks can identify exactly what they read.

1. Bind authorization to the exact operation, generation, plan, candidate, and
   harness references. Record its source and scope. A generic "GO", resource
   availability, or approval to clean up is not authorization to launch.
2. Proposed changes get new records and a generation or plan revision, but a
   proposal alone changes neither the current plan nor its authorization.
   Never silently run queued work with different inputs. When an authorized
   replacement is adopted, update current state and mark old queued work
   **superseded** (replaced). The new operation/generation/plan/candidate/harness
   combination needs its own authorization. If replacement status is unclear,
   hold launches until it is resolved.
3. Immediately before **each physical launch**, re-read authoritative current state
   and check that this full combination remains current and authorized, with no
   later HOLD, stop or replacement. Recheck the actual test executable and chosen
   runtime. If state cannot be read or identities differ, do not launch.
4. Record checked revision and launch time. Reading state and starting a process
   are separate actions: permission can change between them (a **race**).
   Preventing this requires an actual launch gate that coordinates authorization
   changes with process creation as one protected action (**atomic**). A document
   check alone cannot provide that guarantee; disclose the gap and obey later stops.

Preserve tool-provided assignment IDs only for real assignments; never invent them
for peers. These tool identifiers are separate from session IDs and the operation
ID used to link the task's records.

### 2. Save the exact build and test setup

The product owner records the commit **plus** any uncommitted tracked edits and
untracked build inputs, preserving a patch or source snapshot. Record build
commands and logs, operating system, architecture, each component's configuration,
and hashes of binaries, libraries, symbols and supporting files. Explain
inapplicable items; a commit stamp alone does not cover uncommitted source.

Save an immutable copy or a bundle identified by its content hash, with a fixed
manifest. A build output folder that later builds overwrite is not a frozen
handoff. For an **overlay** (replacing only some files in an existing build),
identify the base, replaced and retained files, matching symbols and evidence
that all components form the intended build. Copying new binaries alone does
not establish coherence.

The test owner saves the test source and edits, tools, settings, exact selected
cases, input data and test modes, and **actual test host/executable identity**.
A selector is a name or filter used to choose tests. Record both it and the files
it resolves to: an unchanged selector can choose a different executable later.
Such a change invalidates setup until reconciled.

Specify exact runtime and dependency versions, architecture, component settings,
environment overrides and whether automatic version substitution (roll-forward)
is allowed. Verify the loaded libraries/packages, runtime and test executable
from execution evidence, not just requested settings or PATH.
Exchange manifest references, not repeated inventories/hashes. Reuse a verified
candidate while it remains applicable.

### 3. Choose when to stop; keep diagnosis separate

A **collection policy** says whether the initial test pass stops after a failure:

| Policy | Required behavior |
|--------|-------------------|
| `complete-first-pass` | Collect every authorized case/data/mode once, including independent cases after failures. Mark unreachable cases individually; safety and user stops still take precedence. |
| `fail-fast` | Stop at the agreed failure boundary and report the remainder as not reached/not run, never passed. |

Never silently change policy or add tests to fill gaps. Keep assertions, original
logs and historical runs. Distinguish the planned validation pass (**acceptance**)
from extra runs investigating a failure (`diagnostic`) or fixing invalid setup
(`setup-correction`). Link each extra run to its original and obtain any additional
authorization. Corrections do not erase invalid runs; retries for green do not
establish first-pass success.

### 4. Execute, stop, and restore

For each actual launch, capture commands, working directory, environment,
start/end times, exit status, raw logs and selected tests. Record **reached
subchecks**: the individual steps confirmed to have run, such as load, roundtrip
and compare. Tool success alone proves neither target execution nor outcome.

A HOLD/stop revokes queued launches immediately. For already-running work, follow
the agreed replacement policy within the user's authorization: either stop
safely or finish only explicitly permitted in-flight collection. A user stop or
safety boundary takes precedence over collection completeness. If the policy is
missing, stop safely and block further launches rather than assuming permission
to finish. Preserve partial evidence.

Track owned process IDs/children; never kill unrelated processes. Snapshot
configuration before mutation, restore owned changes without overwriting
concurrent edits, and verify restoration. Report cleanup/restoration failures as
blockers. Cleanup does not release a HOLD or authorize a new generation.

### 5. Classify outcomes and coverage

Keep execution state separate from the requested verdict:

| Outcome | Meaning |
|---------|---------|
| `setup-invalid` | Wrong/missing candidate, runtime, host, harness, pinning or prerequisites; no valid product conclusion |
| `product-failure-before-operation` | Verified setup, but product fails before the requested operation; requested symptom remains not reached |
| `symptom-reproduced` | Requested operation reached and evidence satisfies the defined symptom criterion |
| `symptom-not-reproduced` | Requested operation and required subchecks reached under verified setup; symptom criterion absent within this scope |
| `not-reached` / `not-run` | A subcheck was unreachable / no physical execution started; neither is a pass |
| `blocked` / `interrupted` | Permission, infrastructure, stop, or supersession prevented completion; retain any already observed outcomes |

For compatibility tests, define what counts as success as well as the failure
symptom; `symptom-not-reproduced` is not automatically a pass.
Report separately: tool return, actual target execution, observed configuration,
reached subchecks, and verified outcome. Unknown evidence stays unknown.

Count actual launches (**physical executions**) separately from distinct test
cases and distinct combinations of case, data, mode and configuration. Records
call such a combination a **tuple**. A coverage group is a named set of those
combinations; one combination may belong to several groups without being run
several times.

| Count | What to state explicitly |
|-------|--------------------------|
| Physical executions | Total launches and separate acceptance, diagnostic and setup-correction counts |
| Unique coverage | Number of distinct case IDs and distinct case/data/mode/configuration combinations |
| Coverage groups | Total memberships (sum of group sizes), intersections, and the deduplicated union |

State every requested total; do not leave readers to calculate it from the
breakdown. Group memberships are not unique coverage, and repeating a diagnostic
launch does not add a new test combination.

### 6. Publish once; message only to change an action

Write one final report (**terminal summary**) linking the plan, manifests, results,
raw logs, coverage, gaps and cleanup evidence. State what decision or action, if
any, remains. Send its reference once; revise only when evidence or the required
next action changes. Never resend unchanged final reports or hashes.

Message only when the recipient's next action changes: permission, replacement or
stop, an actionable blocker, requested evidence, an important correction or
completion. State the event, task/version, evidence reference and next action:

```text
event: completion
operation: compatibility-check
generation: 2
plan: artifacts/plan-v2.yaml
result: artifacts/result-v1.md
next-action: product owner reviews the recorded failure before proposing changes
```

Avoid acknowledgement loops, repeated HOLD/readiness and duplicate progress.
Reference durable records. Report inaccessible artifacts as blockers rather than
copying private inventories into messages.

## Validation checklist

- Executions match authorized inputs and recorded pre-launch checks; superseded
  queued work did not start.
- Actual host/runtime/configuration and reached subchecks support the verdict.
- Every requested test combination has an outcome or an explicit coverage gap; totals
  reconcile overlaps and distinguish physical execution from unique coverage.
- Original assertions/evidence survive; diagnostics are labeled.
- Restoration and owned-process cleanup are verified or blocked.
- One terminal summary is discoverable without replaying conversations.
