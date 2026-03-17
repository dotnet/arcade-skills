# Internal Mirror Setup

Guide for setting up the GitHub → Azure DevOps internal mirror required for official builds, signing, and publishing.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Mirror Setup Steps](#mirror-setup-steps)
- [Mirroring Configuration Format](#mirroring-configuration-format)
- [Pipeline Setup](#pipeline-setup)
- [Pipeline Naming Conventions](#pipeline-naming-conventions)
- [Verification](#verification)

## Overview

Official builds in the .NET ecosystem run at `dev.azure.com/dnceng/internal`. Public GitHub repos must be mirrored there. The mirror system automatically syncs commits from GitHub to the internal AzDO repo.

**Architecture:**
```
GitHub (dotnet/my-repo)
    ↓ mirror sync
Azure DevOps (dnceng/internal/dotnet-my-repo)
    ↓ triggers
Official Build Pipeline (signing, publishing, etc.)
```

**Two AzDO projects are used:**
- **`dnceng-public/public`** — Public CI, PR validation. Pipelines pull source directly from GitHub.
- **`dnceng/internal`** — Official builds, signing, publishing. Pipelines pull from mirrored internal repos only.

## Prerequisites

1. **Repository must be in the `dotnet` GitHub organization** (or another org with the dotnet-maestro GitHub app installed)
2. **Arcade SDK onboarding complete** — `eng/common/`, `global.json` with Arcade SDK, etc.
3. **Contact dnceng** to create the internal Azure DevOps repository if it doesn't exist

## Mirror Setup Steps

### Step 1: Request Internal Repository Creation

Contact @dnceng (via GitHub or dnceng@microsoft.com) to create a repository at:
```
https://dev.azure.com/dnceng/internal/_git/{org}-{repo}
```

**Naming convention:** Replace `/` with `-` in the GitHub repo path.
- `github.com/dotnet/maui-labs` → `dotnet-maui-labs`
- `github.com/dotnet/arcade` → `dotnet-arcade`
- `github.com/Microsoft/visualfsharp` → `Microsoft-visualfsharp`

For DevDiv repos, the pattern is `{org}-{repo}-Trusted`.

### Step 2: Add Mirroring Configuration

Create a PR to the `dotnet-mirroring` internal repo:
```
https://dev.azure.com/dnceng/internal/_git/dotnet-mirroring
```

Edit the `dnceng-subscriptions.jsonc` file (or `devdiv-subscriptions.jsonc` for DevDiv repos).

Add an entry for your repository (keep alphabetical order):

```jsonc
    "https://github.com/dotnet/maui-labs": {
      "fastForward": [
        "main",
        "release/.*"
      ]
    },
```

### Step 3: Verify Mirror

After the mirroring PR is merged, verify that:
1. The internal repo at `dev.azure.com/dnceng/internal/_git/dotnet-maui-labs` has content
2. New pushes to GitHub `main` appear in the internal mirror within minutes

## Mirroring Configuration Format

The subscriptions JSON supports these mirroring types:

### fastForward
Mirror branches exactly as-is from GitHub → AzDO. Most common and recommended.

```jsonc
"https://github.com/dotnet/my-repo": {
  "fastForward": [
    "main",           // Mirror main branch
    "release/.*"      // Mirror all release/* branches (regex)
  ]
}
```

### internalMerge
Create `internal/` prefixed branches that merge GitHub branches with internal-only changes. Used when internal builds need additional files not in the public repo.

```jsonc
"https://github.com/dotnet/my-repo": {
  "fastForward": [
    "main",
    "release/.*"
  ],
  "internalMerge": [
    "release/.*"    // Merge release/.* → internal/release/.*
  ]
}
```

### Branch patterns
- Literal branch names: `"main"`, `"release/8.0"`
- Regex patterns: `"release/.*"`, `"feature/.*"`
- Comments: `// Comment text` (JSONC format)
- Disabled branches: `// GitHubBranchNotFound "main"` (branch doesn't exist yet)

## Pipeline Setup

### Public CI Pipeline (dnceng-public/public)

Create a pipeline at `https://dnceng-public.visualstudio.com/public`:

**Folder structure:**
```
dotnet/maui-labs/maui-labs-ci
```

**Pipeline configuration:**
- Source: GitHub repository directly (uses "dotnet" service connection)
- YAML file: `azure-pipelines.yml` (or custom path)
- Triggers: PR and CI on main + release branches
- Agent pools: `NetCore-Public` or `NetCore-Svc-Public`

### Official Build Pipeline (dnceng/internal)

Create a pipeline at `https://dev.azure.com/dnceng/internal`:

**Folder structure:**
```
dotnet/maui-labs/maui-labs-official
```

**Pipeline configuration:**
- Source: Internal mirror repo (`dotnet-maui-labs`)
- YAML file: `azure-pipelines.yml` (or `eng/pipelines/official.yml`)
- Triggers: CI on main + release branches (no PR trigger)
- Agent pools: `NetCore1ESPool-Internal` or `NetCore1ESPool-Svc-Internal`
- Must extend 1ES Pipeline Template for compliance

### Pipeline Naming Convention

```
{org}/{repo}/{repo}-{scenario}
```

Scenarios:
- `ci` — Public CI / PR validation
- `official` — Official internal build (signing + publishing)
- `code-coverage` — Dedicated code coverage runs
- `slow-tests` — Long-running test suites

**Examples:**
```
dnceng-public/public:
  dotnet/maui-labs/maui-labs-ci

dnceng/internal:
  dotnet/maui-labs/maui-labs-official
```

## Verification

After mirror and pipelines are set up:

1. **Push a commit to GitHub main** → verify it appears in the internal mirror
2. **Create a PR on GitHub** → verify public CI pipeline triggers
3. **Push to internal mirror's main** → verify official build pipeline triggers
4. **Check build artifacts** → verify packages are published to Build Asset Registry
5. **Check publishing** → verify `Publish Using Darc` stage completes (if default channel is set)

## Common Issues

### "Repository self references endpoint"
YAML parse error in pipeline definition. Fix the YAML syntax, re-create the pipeline.

### "Resource not authorized"
Pipeline needs authorization for service endpoints. Change the default branch to your branch, save, then revert.

### Mirror not syncing
Check the `dotnet-mirroring` repo for configuration errors. Contact @dnceng if branches aren't syncing.

### Service connection for GitHub
Use the "dotnet" GitHub app service connection. Contact @dnceng if your repo doesn't appear in the connection.
