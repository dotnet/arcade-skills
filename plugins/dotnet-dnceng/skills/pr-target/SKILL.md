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
and **current branch state**, not the developer's checkout. Return verified
branch links, merge restrictions, and porting requirements. This skill applies
the [VMR Change Target Guide](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Change-Target-Guide.md);
if current policy conflicts with these rules or observed branch state, surface
the conflict and ask the QB rather than guessing.

This is read-only advice: do not create branches or PRs, cherry-pick, push, merge,
change subscriptions, or prepare parking windows. Do not publish security details
or query public services for private changes or internal refs.

## Blocked routes

These rules apply everywhere below. When a decisive fact is unknown:

- **End the response with one `Question:` line per blocker**, ending with `?`,
  even when the fact must come from the QB (for example, "Question: Can you or
  the QB provide ...?"). Stating that information is missing or required, or
  telling the user to obtain it, is not a question. Use the host's question
  tool instead when available. Never ask for discoverable or established facts.
- Withhold the target and branch link. Do not list candidate branches, branch
  classes, or conditional routes; a high-level reason the answer matters is enough.
- A failed or unauthorized query is **unknown**, not absence. Never fall back to
  a public target for security or invent a branch link.

Distinguish unknowns from prerequisites known to be absent; for those, report
**wait** and the next action instead of asking. With no Tactics approval, your
entire response is exactly: "No target yet. Obtain Tactics approval for a
specific servicing release, including its window and year, then return for
target selection." Add nothing else: no snapshot, branch, band, parking, port,
or matrix details.

## 1. Discover the change

Read the prompt, supplied change/PR, repository instructions, remotes, and a
scoped diff or commit summary. Do not assume the current branch is the target,
or that a fork's `origin` is the canonical repository. Collect only the facts
relevant to the route:

- **Intent:** vNext development, a particular preview, or servicing/hotfix.
- **Visibility:** is this a security change? Absence of security labels is not
  evidence. Never ask for exploit details. If unknown, ask "Is this change
  security-related or non-security?" Until answered, report no band, branch, or
  branch-class findings, because visibility changes the whole routing model.
- **Scope:** component(s), product release/train, and affected SDK feature bands,
  discovered from changed paths and build configuration when possible. A mixed
  runtime/SDK change can need different per-band subsets. For unknown bands, ask
  "Which SDK feature bands does this fix affect?" without enumerating per-band targets.
- **Preview:** does the change target the next preview to ship?
- **Servicing:** which release Tactics approved (for example runtime `10.0.4`
  or SDK `10.0.105`) and its window, including the year (for example `2027/2B`);
  whether it is an OOB; and, for an OOB, the explicitly approved destination.

If an approved window omits the year, infer the nearest plausible occurrence
from today's date (or an offline snapshot's observation date) when the normal
planning horizon makes it clear, and state the inferred year.

## 2. Establish current branch state

Follow [branch discovery](references/branch-discovery.md) using read-only git,
GitHub, and authorized internal repository queries, for example:

```text
git status --short --branch
git remote -v
git diff --stat
git ls-remote --exit-code --heads <authorized-remote> <exact-ref>
```

For each relevant band, establish:

- The canonical public repository and, when needed, the internal VMR repository.
- Whether vNext servicing and next-preview branches exist.
- Whether a Release Specific branch exists for the approved release, and which
  release General Servicing represents, from existence and branding at observed
  refs (VMR: `eng/Versions.props`).
- For a later approved window: its exact parking ref (year and band), intake
  state, and any QB-published replacement destination.

Report a branch type absent only from a complete inventory. Do not infer open
parking intake from a ref existing. Do not equate an SDK version with a runtime
patch or calendar window by guesswork. If approval names only a window and its
release is unknown and branch evidence cannot settle the route, ask "Question: Can you or the QB provide the authoritative
release for window <year/window>?" Explain, without saying where the PR would go
in each case, that the release decides which branch state applies; later
releases can share General Servicing but must stay unmerged until their window
opens. Do not claim each possible release maps to a different branch.

For offline advice with supplied evidence, label the result **snapshot-based**,
use the snapshot's observation time (reproduce it exactly; never invent one or
compare it with the CLI's date), and use its repository URLs for links. Do not
assert future branch names, creation dates, or ancestry as verified, and
distinguish intended downstream flow from verified inclusion.

`global.json` identifies the bootstrap SDK, not the shipping release or window.

## 3. Apply the routing rules

### vNext and previews

Let **development branch** mean public `main` before vNext servicing branches
exist, or the verified public vNext servicing branch after they exist (for
example, VMR `release/11.0.1xx`). Component branch names may differ.

| Branch state and intent | Non-security | Security |
|-------------------------|--------------|----------|
| Next preview branched **and** change targets it | Public preview branch in VMR or component repo | Corresponding internal preview branch in VMR or component repo |
| Preview not branched, **or** change does not target the next preview | Development branch | Wait for the internal preview branch for the intended preview; no public fallback |

Verify public and internal preview refs independently; never manufacture one by
adding or removing `internal/`. If the required internal preview is unavailable,
return **wait**, not a link to public `main`.

**Ports:** a non-security preview fix must also reach the development branch.
Security fixes port there **after public release**, never before disclosure.

### Servicing .NET 6 and .NET 8 components

Do not apply the 10.0+ VMR band matrix. Each component repository has its own
**internal** General Servicing branch; both security and non-security fixes go
there, never to a public branch; say so even when the exact branch is unknown.
Use the branch only when verified state shows it represents the approved
release. Otherwise **wait** and ask "Question: Can you or the QB provide the
internal <repository> servicing branch for <approved release>?" Do not
substitute another repository's or release's branch. Other pre-10.0 releases are out of support: report that and
ask the QB before suggesting any target.

### Servicing (VMR, 10.0+)

Select bands before selecting destinations:

- **Runtime/shared-component fixes:** 1xx only; packages flow to higher bands.
- **SDK/band-specific fixes:** each affected band separately, not every band.
- **Mixed changes:** keep runtime/shared source edits out of non-1xx PRs; split
  the change into per-band subsets. For non-1xx source and toolset limits, see
  [feature band tooling constraints](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Feature-Band-Tooling-Constraints.md).

Apply these exceptions before the ordinary matrix:

1. **OOB:** use only the explicitly approved OOB destination; no parking branch.
   If the destination is missing, ask; do not choose a likely branch.
2. **Parking integration:** follow the QB's published destination for that
   window; never submit to a frozen parking branch. If unpublished, report
   **wait** and ask "Question: Can the QB publish the replacement destination
   for <band> <year/window>?" Branding may lag the transition.

Then evaluate **each selected band's state** independently:

| Approved release compared with branches | Non-security | Security |
|-----------------------------------------|--------------|----------|
| Release Specific exists for the approved release | Internal VMR Release Specific | Internal VMR Release Specific |
| No Release Specific; General Servicing represents the approved release | Public General Servicing in VMR or component repo | Internal VMR General Servicing |
| No Release Specific; General Servicing represents an earlier release | Public General Servicing PR, **leave unmerged** until the approved window opens | Internal VMR parking branch for the approved year/window and band |

Release Specific takes precedence, even when General Servicing has the same or
later branding. Without Release Specific, if General Servicing is later than the
approved release, or the relationship is unknown, ask "Question: Can the QB
provide the destination for <band> <approved release>?"

If the correct parking branch is absent, ask the QB to prepare it and return
**wait**. Do not create it or substitute General Servicing, a component
validation branch, or another year/window. NETMechanic integrates and deletes
parking branches when their windows open; developers do not resubmit. When
recommending security parking, state all three decisive facts: no Release
Specific branch for the approved release, General Servicing branded for an
earlier named release, and the exact parking branch with intake open (or a
QB-published handoff).

**Ports:** non-security fixes port to `main` as necessary; security fixes port
to `main` as necessary **on disclosure day**. Release-tag merges carry shipped fixes back
to General Servicing; they do not justify merging later-window public fixes early.

## 4. Verify and report

Recheck the chosen ref and any intake restrictions just before reporting. For
each target, give:

- **Target:** repository, exact base branch, band, and a clickable branch link
  built from the verified repository URL (formats in branch discovery).
- **Action:** create a PR, prepare an **unmerged** PR, wait, or clarification
  required. A target is not merge authorization; never say "merge normally".
  Normal review, validation, and merge policies still apply.
- **Why:** the approved/intended release, decisive branch state, and evidence
  ref and observation time (or snapshot qualification).
- **Ports:** exact branch and timing, as defined above. For multiple bands,
  report each target and any unresolved band separately.

Never return example names, `release/vNext`, or unverified URLs as targets. Add a
compare/create-PR link only when both base and head are verified. When internal
state is unavailable, ask: "Can you provide the authorized branch state,
including Release Specific existence and branding and General Servicing branding
for the approved release?" Add parking intake and handoff when they decide routing.

Before responding, check:

- Every blocker has a `Question:` line ending with `?`.
- Any quoted snapshot observation time matches the evidence character for character.
- Downstream flow and release inclusion are stated as expected policy, not as verified.
- Statements about absence cover only what the evidence inventories (refs, not releases).

## Policy references

- [VMR Change Target Guide](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Change-Target-Guide.md)
- [Servicing workflows](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Servicing-Workflows.md)
- [Managing SDK bands](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Managing-SDK-Bands.md)
- [Feature band tooling constraints](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Feature-Band-Tooling-Constraints.md)