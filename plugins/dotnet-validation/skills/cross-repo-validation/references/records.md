# Validation records and examples

These are minimal, human-maintained record shapes, not an enforced schema or
runtime lock. Use a repository's existing artifact format if it carries the same
information. Replace illustrative references with actual accessible artifacts;
do not treat examples as authorization. Freeze referenced versions and record
their content hash once in the task's artifact index.

## Current state and plan

The current-state record points to the latest plan and permissions. Read it before
each launch; only the agreed owner updates it, preserving revision history. If it
is unavailable, block launches. Reading a record and starting a process are
separate actions: a later HOLD can arrive between them.

```yaml
protocol-version: 1
operation: compatibility-check
state-revision: 8
generation: 2
plan-ref: artifacts/plan-v2.yaml
candidate-ref: artifacts/candidate-v2.yaml
harness-ref: artifacts/harness-v1.yaml
work-state: queued
authorization:
  state: hold
  source-ref: artifacts/user-request-v2.txt
  scope: cleanup-only
```

A plan is immutable; changing its meaning creates a new revision. The referenced
authorization must cover the exact operation, generation, plan, candidate and
harness combination, not just the operation's name.

```yaml
protocol-version: 1
operation: compatibility-check
generation: 2
plan-revision: 2
product-owner: product repository owner
test-owner: consuming repository owner
request-ref: artifacts/user-request-v2.txt
candidate-ref: artifacts/candidate-v2.yaml
harness-ref: artifacts/harness-v1.yaml
selection-ref: artifacts/resolved-tuples-v1.csv
requested-operation: load the candidate and perform the selected round trips
success-criterion: each round trip preserves the asserted payload
symptom-criterion: payload mismatch after a completed round trip
collection-policy: complete-first-pass
running-work-on-supersession: stop-safely
stop-and-restore-ref: artifacts/stop-and-restore-v1.md
evidence-root: artifacts/collection-generation-2
```

`request-ref` preserves the user's words and permitted scope; it is not generated
approval. An authorized state additionally identifies that exact combination,
source of authorization, limits, and any expiration. New state must not broaden it.
A tool-provided assignment ID, if one exists, is separate optional metadata, not
an operation ID, generation, or peer-session ID.

A proposed candidate or plan does not change this current-state record. Only an
authorized replacement supersedes the old queued work; the proposal itself grants
no permission to run the replacement.

## Candidate manifest

The product owner records actual file identities, not placeholders like
"current HEAD". Keep the full hashed file inventory in a separate referenced
file. Record absent symbols or other inapplicable components with a reason.

```yaml
manifest-version: 1
candidate: product-candidate-v2
source:
  repository: product repository
  commit: recorded commit identity
  tracked-patch-ref: artifacts/product-tracked.patch
  untracked-inputs-ref: artifacts/product-untracked-inventory.json
  source-snapshot-digest: recorded SHA-256 of captured build inputs
build:
  command-ref: artifacts/product-build-command.txt
  log-ref: artifacts/product-build.log
  os: recorded operating system
  architecture: x64
  components:
    native-library: Release
    managed-library: Debug
artifact-bundle-ref: artifacts/frozen-product-v2
file-hashes-ref: artifacts/product-files-v2.sha256
symbols-ref: artifacts/product-symbols-v2.json
coherence-evidence-ref: artifacts/product-build-inputs-v2.json
runtime:
  distribution-ref: artifacts/frozen-runtime-v1
  content-identity-ref: artifacts/runtime-v1.sha256
  version: exact recorded version
  architecture: x64
  roll-forward: disabled
```

For a clean source tree, explicitly record clean status instead of patch
references. For an overlay (replacing some files in an existing build), reference
the base manifest, exact replacements and retained components, compatibility
constraints, and evidence that binaries/libraries/symbols form the intended
candidate. If coherence cannot be established, the candidate is not ready.

## Harness manifest

The test owner identifies the exact selected tests and executable before saving
this manifest. Preserve uncommitted source just as for the product if applicable.
Changes to scripts, data, tools, resolved selection or launch configuration create
a new version.

```yaml
manifest-version: 1
harness: consumer-harness-v1
source-identity-ref: artifacts/harness-source-v1.json
tools-ref: artifacts/harness-tools-v1.json
selector: compatibility-roundtrips
resolved-tuples-ref: artifacts/resolved-tuples-v1.csv
host:
  executable-ref: artifacts/frozen-harness-v1/test-host
  content-identity-ref: artifacts/host-v1.sha256
launch:
  command-template-ref: artifacts/launch-command-v1.txt
  working-directory-ref: artifacts/working-directory-v1.txt
  environment-and-pinning-ref: artifacts/environment-v1.json
  observed-identity-check: execution evidence records loaded host, runtime and product modules
restoration:
  original-config-ref: artifacts/config-before-v1
  owned-process-ledger-ref: artifacts/processes-generation-2.json
  procedure-ref: artifacts/stop-and-restore-v1.md
```

A selector (test name or filter) that now points to a different executable is
**not** the same harness even when its text is unchanged. Identify the selected
files again, revise the manifest and authorization, and record the old execution
as setup-invalid if it ran with the wrong host.

## Execution record and terminal summary

Use one record per actual launch, including runs to correct setup or investigate
a failure. `tuple-ref` identifies the specific case/data/mode/configuration
combination; `reached-subchecks` lists steps confirmed to have executed.

```yaml
operation: compatibility-check
generation: 2
plan-ref: artifacts/plan-v2.yaml
candidate-ref: artifacts/candidate-v2.yaml
harness-ref: artifacts/harness-v1.yaml
execution: execution-4
purpose: diagnostic
original-execution-ref: artifacts/execution-2.yaml
prelaunch-state-revision: 9
authorization-ref: artifacts/diagnostic-authorization.txt
started-at: recorded UTC timestamp
ended-at: recorded UTC timestamp
tuple-ref: artifacts/resolved-tuples-v1.csv#roundtrip-binary
command-and-environment-ref: artifacts/execution-4-command.json
tool-return: success
target-executed: true
observed-host-runtime-and-modules-ref: artifacts/execution-4-modules.json
reached-subchecks: [load, roundtrip, compare]
outcome: symptom-reproduced
raw-log-ref: artifacts/execution-4.log
restoration-and-cleanup-ref: artifacts/execution-4-cleanup.json
```

Do not claim success when the tool returns successfully but the target never
starts. Unknown observed configuration cannot establish a valid product verdict.
A final report (terminal summary) should fit this outline:

```text
Operation/generation and immutable plan/candidate/harness references
Verdict and scope: requested operation/subchecks reached, evidence or uncertainty
Per-tuple outcomes and execution index, including blocked/not-run remainder
Counts: physical launches by purpose; unique cases/data/mode/config tuples
Coverage groups: membership totals, intersections, unique union, omissions
Configuration restoration and owned-process cleanup: verified or blocker + evidence
Exact commands, raw logs, observed configuration and original-run references
Next action, only if a decision or blocker remains
```

For example, group A contains test combinations `{x, y}` and group B contains `{y, z}`.
There are four group memberships but three unique tuples. If each tuple ran once
for acceptance and `y` ran once more diagnostically, report **four physical
executions: three acceptance and one diagnostic; three unique tuples**.
Do not report four acceptance cases or a missing fourth tuple. Unique case IDs
may be fewer again when one case has multiple data/mode/configuration tuples.

## Event examples

Use a short event plus artifact references and the required next action. This
protocol does not require a particular session or messaging tool.

| Situation | Event and recipient action |
|-----------|----------------------------|
| Product candidate frozen | Handoff references candidate manifest; test owner resolves harness and checks authorization before queueing, not automatic launch |
| Cleanup approved, tests on HOLD | No launch event; record cleanup outcome once if requested, leave authorization on HOLD |
| New HOLD after a launch check | Supersession/stop event; revoke queued work, apply safe in-flight stop policy, record partial execution and restoration |
| Independent failure during complete first pass | Record failure and continue authorized independent cases; request a decision only for a real safety/access blocker |
| Selector resolves to another host | Setup blocker/material correction with observed identities; no acceptance conclusion until reconciled and authorized |
| Terminal evidence already delivered | No new message unless evidence or required next action materially changes |

Completion envelope:

```text
event: completion
operation: compatibility-check
generation: 2
plan: artifacts/plan-v2.yaml
result: artifacts/result-v1.md
next-action: product owner reviews the recorded mismatch
```
