---
name: pr-target
description: >
  Identify the check-in branch for a .NET VMR or component change.
  Use when asked where to open a PR, which preview or servicing branch to target,
  or where an approved fix belongs. Do not use for merging PRs, CI failure
  investigation, or tracing dependency flow.
---

# Find the PR Target

Identify the repository and branch to create a PR against, based on the change
and **current branch state**, not the calendar or the developer's checkout.
Return verified branch links, merge restrictions, and porting requirements.

This is read-only advice: do not create branches or PRs, cherry-pick, push, merge,
change subscriptions, or prepare parking windows. Do not publish security details
or query public services for private changes or internal refs.

## 1. Discover the change; ask only for missing facts

Read the prompt, supplied change/PR, repository instructions, remotes, and a
scoped diff or commit summary. Do not assume the current branch is the target,
or that a fork's `origin` is the canonical repository.

Collect only the facts relevant to the route:

- **Intent:** vNext development, a particular preview, or servicing/hotfix.
- **Visibility:** is this a security change? Absence of security labels is not
  evidence that a change is non-security. Never ask for exploit details.
- **Scope:** component(s), product release/train, and affected SDK feature bands.
  Discover component scope from changed paths and repository build configuration
  when possible. A mixed runtime/SDK change can need different per-band subsets.
- **Preview:** does the change target the next preview to ship?
- **Servicing:** Tactics approval for which release window, including the year;
  whether it is an OOB; and, for an OOB, the explicitly approved destination.

Ask the minimal unresolved questions together using the host's question tool,
or ask them directly in the response if none is available. Merely stating
that a fact is missing is not a question. For an unresolved route, stop before
giving candidate target links or a conditional menu of branches. Ask for the
decisive fact instead. Do not ask the user to repeat discoverable facts.
Do not guess security status, approval, affected bands, or a window's year.
For unknown SDK bands, ask "Which SDK feature bands does this fix affect?" and
stop: do not enumerate potential targets for all existing bands.

Distinguish unknown inputs from prerequisites known to be absent. If the user
has no Tactics approval yet, report **wait** and request approval for a specific
window before recommending a servicing check-in. If the QB has not published
a frozen-intake replacement, report **wait** and request that publication.
Do not repeatedly ask for a fact the user or evidence has already established.

## 2. Establish current branch state

Follow [branch discovery](references/branch-discovery.md). Use read-only git,
GitHub, and authorized internal repository queries. For example:

```text
git status --short --branch
git remote -v
git diff --stat
git diff --cached --stat
git ls-remote --exit-code --heads <authorized-remote> <exact-ref>
```

For each relevant band, establish:

- The canonical public repository and, when needed, the internal VMR repository.
- Whether vNext servicing and next-preview branches exist.
- Which release/window General Servicing represents, using version metadata
  **and** the current release/QB mapping, not a branch suffix or date alone.
- Whether a Release Specific branch exists for the approved release.
- For a later approved window: its exact parking ref, including year and band,
  intake/integration state, and any QB-published replacement destination.

A failed or unauthorized query is **unknown**, not proof a branch is absent.
If missing access or conflicting/stale evidence changes the answer, report the
blocker and ask for the missing evidence. Do not fall back to a public target
for security. Do not infer open parking intake from the branch merely existing.

If offline advice is requested with supplied branch-state evidence, use that
snapshot and label the result **snapshot-based**, not live-verified. Missing
evidence still blocks a definitive target. In an offline exercise, links refer
to the supplied snapshot's repository URLs, not verified live endpoints.
Do not assert future branch names, creation dates, or ancestry as verified
facts. Distinguish intended downstream flow from verified inclusion.

## 3. Apply the routing rules

### vNext and previews

Let **development branch** mean public `main` before vNext servicing branches
exist, or the verified public vNext servicing branch after they exist (for
example, VMR `release/11.0.1xx`). Component branch names may differ.

| Branch state and intent | Non-security | Security |
|-------------------------|--------------|----------|
| Next preview branched **and** change targets it | Public preview branch in VMR or component repo | Corresponding internal preview branch in VMR or component repo |
| Preview not branched, **or** change does not target the next preview | Development branch | Wait for the internal preview branch for the intended preview; no public fallback |

Verify the actual public/internal preview refs independently; never manufacture
one by adding or removing `internal/`. If the required internal preview is not
available, return **wait**, not a link to public `main`.

**Ports:** a non-security preview fix must also reach the development branch.
A direct development-branch change needs no such port. Security fixes port to
that development branch **after public release**, never before disclosure.

### Servicing (VMR, 10.0+)

Select bands before selecting destinations:

- **Runtime/shared-component fixes:** 1xx only; packages flow to higher bands.
- **SDK/band-specific fixes:** each affected band separately, not every band.
- **Mixed changes:** keep runtime/shared source edits out of non-1xx PRs; split
  the change into the appropriate per-band subsets.

For older releases, consult their component servicing policy; do not impose
10.0+ VMR band rules or invent a VMR destination.

Apply these exceptions before the ordinary matrix:

1. **OOB:** use only the explicitly approved OOB destination. No parking branch.
   If the destination is missing, ask; do not choose a likely branch.
2. **Parking integration:** follow the QB's published destination for that window.
   Do not submit to a frozen parking branch. If the destination is unpublished,
   report **wait** and request QB publication for that band and year/window.
   If it may be published but cannot be verified, ask for the published
   repository and branch. Branding may lag the transition.

Then evaluate **each selected band's state** independently:

| Approved release compared with branches | Non-security | Security |
|-----------------------------------------|--------------|----------|
| Release Specific exists for the approved release | Internal VMR Release Specific | Internal VMR Release Specific |
| No Release Specific; General Servicing represents the approved release | Public General Servicing in VMR or component repo | Internal VMR General Servicing |
| No Release Specific; General Servicing represents an earlier release | Public General Servicing PR, **leave unmerged** until the approved window opens | Internal VMR parking branch for the approved year/window and band |

Release Specific takes precedence even while General Servicing is still branded
for the same release. If General Servicing is later than the approved release,
or the relationship is unknown, do not treat it as an earlier release: ask the QB.

If the correct parking branch is absent, ask the QB to prepare it and return
**wait**. Do not create it or substitute General Servicing, a component validation
branch, a different year, or another window. NETMechanic integrates and deletes
parking branches when their windows open; developers do not resubmit those fixes.
Component validation PRs are not the final internal VMR check-in destination.

**Ports:** non-security fixes port to `main` as necessary; security fixes port
as necessary **on disclosure day**. Release-tag merges carry shipped fixes back
to General Servicing; they do not justify merging later-window public fixes early.

## 4. Verify and report

Recheck the chosen ref and any transition/intake restrictions just before
reporting. For each target, give:

- **Target:** repository, exact base branch, band, and a clickable branch link
  constructed from the verified repository URL. See branch discovery for formats.
- **Action:** create a PR, prepare an **unmerged** PR, wait, or clarification
  required. A target recommendation is not permission to merge. Do not say
  "merge normally" or otherwise grant merge authorization. Where there is no
  window-specific hold, normal review, validation, and merge policies still apply.
- **Why:** the approved/intended release, decisive branch state, and evidence
  source/ref and observation time (or explicit snapshot qualification).
- **Ports:** exact branch name and timing, not just "public branches." For
  servicing, name `main` as necessary (on disclosure day for security). For
  previews, name the verified development branch. For multiple bands, report
  all targets and any unresolved band separately.

Never return example names, `release/vNext`, or unverified URLs as actual targets.
If blocked, name the exact missing fact/access and ask the next question, or
give the next action for a prerequisite known to be absent. Never invent a
branch link. Branch links are enough; add a compare/create-PR link
only when both base and head are known and verified.

For example, when security status is unknown, explicitly ask "Is this change
security-related or non-security?" Saying classification is required is not
enough. Explain why the answer affects the target; leave targets unresolved.

## Policy references

- [Developer Check-in Decision Guide](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Change-Target-Guide.md)
- [Servicing workflows](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Servicing-Workflows.md)
- [Managing SDK bands](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Managing-SDK-Bands.md)

Consult current policy when available. If it conflicts with these rules or
observed branch state, surface the conflict and ask the QB rather than guessing.
