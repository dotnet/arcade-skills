---
name: arcade-onboarding
description: "Onboard an existing .NET repository to dotnet/arcade without replacing repository-specific behavior. Use for adopting the Arcade SDK, eng/common, official builds, signing, publishing, es-metadata, or darc dependency flow as one onboarding effort. Do not use for diagnosing CI in an already-onboarded repository or for tracing an existing dependency flow."
---

# Arcade Onboarding

Turn an existing .NET repository into a working Arcade-based repository while preserving its build, packaging, and CI behavior.

Arcade changes quickly. Use upstream documentation for current guidance, and inspect the repository's checked-in `eng/common` to understand the parameter surface and repository-specific behavior being upgraded. This skill supplies the orchestration, repository analysis, and operational checks that are easy to miss; it does not duplicate current pipeline or MSBuild templates.

## Outcome

Produce:

- a repository-specific onboarding plan;
- the minimum Arcade files and edits needed for that repository;
- a locally verified build path;
- a list of manual infrastructure work that cannot be completed in the repository; and
- no unresolved placeholders presented as a completed setup.

## Guardrails

- Inspect before editing. A partially onboarded repository should be completed, not regenerated.
- Merge with existing files. Do not replace `global.json`, `Directory.Build.*`, `NuGet.config`, central package management, or CI wholesale.
- Ask before making changes that enable shipping, official publishing, signing, internal mirrors, or dependency subscriptions. A planning response may still explain those options.
- Fetch current documentation before generating config. Do not reuse pool names, image names, feed names, channel names, service connections, or template parameters from memory.
- Prefer the repository's existing conventions over examples from another repository.
- Keep public CI and official/release concerns separate unless the current Arcade guidance explicitly combines them.
- Surface access or authorization work as manual follow-up; do not pretend it was configured.

## Workflow

### 1. Inventory the repository

Read:

- all solution and project files;
- `global.json`, `Directory.Build.props`, `Directory.Build.targets`, and `Directory.Packages.props`;
- `NuGet.config`, `eng/Versions.props`, `eng/Version.Details.xml`, and `eng/Version.Details.props`;
- existing `eng/common` files;
- public and official pipeline YAML;
- packaging, signing, publishing, and release configuration; and
- `LICENSE`, `es-metadata.yml`, and repository ownership metadata.

For each project, record:

- output type and target frameworks;
- whether it is packable;
- package ID and current version source;
- shipping, non-shipping, test, sample, or tool classification;
- platform workload requirements; and
- dependencies that may participate in .NET dependency flow.

Also record existing build and test commands. Arcade onboarding must preserve those behaviors.

### 2. Resolve decisions before editing

Ask only for information that cannot be derived from the repository:

1. Which .NET product band or branch should the repository follow?
2. Which packages are public shipping assets?
3. Is public CI sufficient, or are official builds, signing, or publishing required?
4. Should eligible .NET dependencies flow through Maestro/darc?
5. If 1ES inventory metadata is required, what Service Tree ID and routing area are authoritative?

If the user does not know a required production value, either leave that part incomplete with an explicit blocker or ask them to obtain it. Do not silently invent IDs or channels.

### 3. Load current canonical guidance

Read [canonical-sources.md](references/canonical-sources.md), then fetch only the sources relevant to this repository.

At minimum:

- use Arcade's onboarding and SDK documentation for file shapes;
- use the current dependency description and darc documentation for dependency metadata and CLI syntax;
- use current Azure DevOps guidance and the repository's checked-in `eng/common` templates for pipelines; and
- use current signing and publishing documentation for official builds.

If an upstream source conflicts with this skill, follow upstream and note the discrepancy.

### 4. Make the smallest coherent change

Apply onboarding in layers.

#### Build layer

- Add or update the Arcade SDK entry in `global.json` using the current documented shape.
- Merge Arcade imports into existing `Directory.Build.props` and `Directory.Build.targets`.
- Preserve central package management if the repository already uses it.
- Bootstrap `eng/common` from Arcade, then use darc to align it with the selected Arcade build when dependency flow is available.
- Create or adapt dependency metadata using the current recommended `Version.Details` pattern.

Do not pin a sample SDK, channel, SHA, or feed from this skill. Resolve current coherent values from darc or the selected product repository.

#### Repository adaptation layer

- Preserve existing build entry points, test selection, workload restore, and packaging behavior.
- Set shipping behavior per project when a repository contains mixed outputs.
- Keep samples and tests out of shipping packages unless the repository intentionally ships them.
- Preserve `Directory.Packages.props`; connect it to Arcade-managed dependency properties using the current documented pattern.

#### CI layer

- Adapt the repository's existing platform matrix rather than copying a generic matrix.
- Generate public CI only when that is all the repository needs.
- Add official templates only for repositories that need signing, publishing, or other internal stages.
- Resolve current pool images and template parameters from live guidance and checked-in `eng/common`, not from old repository examples.

#### Official-build layer

Only when requested:

- configure signing and post-build validation;
- add valid 1ES inventory metadata;
- document internal mirror and pipeline-definition work;
- separate release publishing when current network-isolation requirements require it; and
- identify service connections that need owner approval.

Read [operational-notes.md](references/operational-notes.md) before implementing this layer.

#### Dependency-flow layer

Only when requested:

- identify dependencies produced by participating .NET repositories;
- use the current dependency metadata format;
- resolve the correct source repository and channel from current darc/Maestro data;
- use current darc authentication and subscription syntax; and
- distinguish product dependencies from toolset dependencies.

Never emit a subscription command containing placeholder repositories, branches, or channels and describe it as ready to run.

### 5. Check operational traps

Read [operational-notes.md](references/operational-notes.md) and apply only the checks relevant to the repository.

In particular, verify:

- Release configurations do not map projects to Debug;
- packable projects explicitly produce the expected packages;
- custom license or assembly metadata satisfies Arcade validation and signing;
- direct package sources comply with the environment's supply-chain policy;
- signing exclusions match the signing configuration;
- custom `build.sh` calls include CI behavior when the pipeline publishes logs; and
- any workaround still applies to the selected Arcade version before adding it.

### 6. Validate in increasing scope

1. Validate generated JSON, XML, YAML, and shell syntax.
2. Restore with the repository's intended package sources.
3. Run the smallest existing build that exercises the Arcade imports.
4. Run the repository's existing tests.
5. Pack Release outputs and inspect shipping/non-shipping artifacts.
6. Run signing or post-build validation only when credentials and infrastructure are available.
7. Review the final diff for replaced repository behavior or unresolved placeholders.

A typical local build entry point is:

```bash
./eng/common/build.sh --restore --build --test --pack --ci --configuration Release
```

Adapt flags and project selection to the repository. Do not run destructive cleanup commands without user approval.

### 7. Report completion honestly

Summarize:

- files changed and why;
- build, test, and package results;
- decisions made by the user;
- values resolved from current authoritative sources;
- remaining manual work for mirrors, pipeline definitions, permissions, signing, publishing, or subscriptions; and
- any temporary workaround with its tracking issue.

Distinguish repository changes that are complete from infrastructure work that still requires a human owner.

## Bundled resources

- [canonical-sources.md](references/canonical-sources.md): where to obtain current file formats, commands, and pipeline guidance.
- [operational-notes.md](references/operational-notes.md): agent-specific checks and undocumented failure patterns.
- `scripts/copy_eng_common.sh`: guarded bootstrap helper for copying `eng/common` from a branch or tag.
