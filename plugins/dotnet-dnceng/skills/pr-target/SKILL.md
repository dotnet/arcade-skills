---
name: pr-target
description: >
  Identify the check-in branch for a .NET VMR or component change.
  Use when asked where to open a PR, which preview or servicing branch to target,
  or where an approved fix belongs. Do not use for merging PRs, CI failure
  investigation, or tracing dependency flow.
---

# Find the PR Target

Identify the repository and branch for a change, with a verified link to use as
the PR base. This skill is being implemented alongside the
[Developer Check-in Decision Guide](https://github.com/dotnet/dotnet/blob/main/docs/VMR-Change-Target-Guide.md).

## Workflow

1. Infer the change type, release, approval, and affected components from the
   prompt and available change context. Ask only for facts that cannot be discovered.
2. Examine the current public and, when authorized, internal branch state.
3. Apply the preview or servicing routing rules and verify the destination.
4. Report the branch link, merge restrictions, and required ports. Do not create
   or merge a PR.
