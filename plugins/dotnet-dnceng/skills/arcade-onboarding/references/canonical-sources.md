# Canonical Arcade Sources

Fetch the relevant source immediately before editing an onboarded repository. These links own file shapes, command syntax, and infrastructure values that change over time.

## Core onboarding

| Topic | Canonical source |
|---|---|
| Documentation entry point | [dotnet/arcade Documentation](https://github.com/dotnet/arcade/blob/main/Documentation/README.md) |
| Onboarding sequence | [Onboarding.md](https://github.com/dotnet/arcade/blob/main/Documentation/Onboarding.md) |
| Arcade SDK and repository layout | [ArcadeSdk.md](https://github.com/dotnet/arcade/blob/main/Documentation/ArcadeSdk.md) |
| Dependency metadata | [DependencyDescriptionFormat.md](https://github.com/dotnet/arcade/blob/main/Documentation/DependencyDescriptionFormat.md) |
| Versioning | [Versioning.md](https://github.com/dotnet/arcade/blob/main/Documentation/Versioning.md) |

## Dependency flow

| Topic | Canonical source |
|---|---|
| Dependency-flow onboarding | [DependencyFlowOnboarding.md](https://github.com/dotnet/arcade/blob/main/Documentation/DependencyFlowOnboarding.md) |
| Channels and subscriptions | [BranchesChannelsAndSubscriptions.md](https://github.com/dotnet/arcade/blob/main/Documentation/BranchesChannelsAndSubscriptions.md) |
| Current darc CLI | [arcade-services Darc.md](https://github.com/dotnet/arcade-services/blob/main/docs/Darc.md) |

The darc documentation owns authentication, option names, and the recommended `Version.Details` property layout. Do not copy subscription flags from old pull requests or repository scripts without checking the current CLI reference.

## Azure DevOps and official builds

| Topic | Canonical source |
|---|---|
| Azure DevOps onboarding | [AzureDevOpsOnboarding.md](https://github.com/dotnet/arcade/blob/main/Documentation/AzureDevOps/AzureDevOpsOnboarding.md) |
| Naming and project guidance | [AzureDevOpsGuidance.md](https://github.com/dotnet/arcade/blob/main/Documentation/AzureDevOps/AzureDevOpsGuidance.md) |
| Arcade template schema | [TemplateSchema.md](https://github.com/dotnet/arcade/blob/main/Documentation/AzureDevOps/TemplateSchema.md) |
| Internal mirrors | [internal-mirror.md](https://github.com/dotnet/arcade/blob/main/Documentation/AzureDevOps/internal-mirror.md) |
| Current Arcade templates | [eng/common](https://github.com/dotnet/arcade/tree/main/eng/common) |
| Current 1ES pool images | [1ES pool list](https://helix.dot.net/#1esPools) |

For a repository already containing `eng/common`, inspect that checked-in version before using upstream `main`; its accepted parameters must match the Arcade SDK consumed by the repository.

## Signing and publishing

| Topic | Canonical source |
|---|---|
| Signing configuration | [Signing.md](https://github.com/dotnet/arcade/blob/main/Documentation/Signing.md) |
| Publishing | [Publishing.md](https://github.com/dotnet/arcade/blob/main/Documentation/Publishing.md) |

Publishing version defaults vary by Arcade generation. Do not create `eng/Publishing.props` solely because an old example contains it.

## Examples are evidence, not specifications

Use active repositories to understand how current guidance is applied:

- [dotnet/runtime](https://github.com/dotnet/runtime)
- [dotnet/arcade](https://github.com/dotnet/arcade)

Before copying an example:

1. confirm it targets the same product band and Arcade generation;
2. inspect the history or comments for repository-specific exceptions;
3. verify template parameters against the target repository's `eng/common`; and
4. replace example-specific repositories, feeds, pools, paths, and service connections.

## Internal-only sources

Some 1ES, CFS, Service Tree, and release-job documentation is Microsoft-internal. Ask the user or repository owner for access rather than reproducing private documentation in generated public files.

When no public source exists, use [operational-notes.md](operational-notes.md) as a checklist, then validate the result against the target organization's current internal guidance.
