# Arcade Pipeline Templates

Reference for Azure DevOps YAML pipeline configurations when onboarding to Arcade.

## Table of Contents

- [Public CI Pipeline](#public-ci-pipeline)
- [Official Build Pipeline](#official-build-pipeline)
- [1ES Pipeline Template](#1es-pipeline-template)
- [Post-Build Publishing](#post-build-publishing)
- [Common Parameters](#common-parameters)
- [GitHub Actions CI](#github-actions-ci)

## Public CI Pipeline

For public PR validation CI at `dnceng-public/public`. This is a simpler pipeline that validates PRs.

```yaml
trigger:
  batch: true
  branches:
    include:
    - main
    - release/*

pr:
  branches:
    include:
    - main
    - release/*

variables:
  - name: _TeamName
    value: <TEAM_NAME>

stages:
- stage: build
  displayName: Build
  jobs:
  - template: /eng/common/templates/jobs/jobs.yml
    parameters:
      enablePublishBuildArtifacts: true
      enablePublishTestResults: true
      enableTelemetry: true
      jobs:
      - job: Windows
        pool:
          name: NetCore-Public
          demands: ImageOverride -equals windows.vs2022.amd64.open
        strategy:
          matrix:
            Release:
              _BuildConfig: Release
        steps:
        - script: eng\common\cibuild.cmd -configuration $(_BuildConfig) -prepareMachine
          displayName: Build and Test

      - job: Linux
        pool:
          name: NetCore-Public
          demands: ImageOverride -equals build.ubuntu.2204.amd64.open
        strategy:
          matrix:
            Release:
              _BuildConfig: Release
        steps:
        - script: eng/common/cibuild.sh --configuration $(_BuildConfig) --prepareMachine
          displayName: Build and Test
```

## Official Build Pipeline

For internal official builds at `dnceng/internal` with signing, publishing, and 1ES compliance.

```yaml
parameters:
- name: publishPackages
  displayName: 'Publish packages to feed'
  type: boolean
  default: true

variables:
  - name: _TeamName
    value: <TEAM_NAME>
  - name: _SignType
    value: Real
  - name: PostBuildSign
    value: false

trigger:
  batch: true
  branches:
    include:
    - main
    - release/*

pr: none

resources:
  repositories:
  - repository: 1ESPipelineTemplates
    type: git
    name: 1ESPipelineTemplates/1ESPipelineTemplates
    ref: refs/tags/release

extends:
  template: v1/1ES.Official.PipelineTemplate.yml@1ESPipelineTemplates
  parameters:
    pool:
      name: NetCore1ESPool-Internal
      image: windows.vs2022.amd64
      os: windows
    # Required for publishing to external feeds like nuget.org
    settings:
      networkIsolationPolicy: Permissive

    stages:
    - stage: build
      displayName: Build
      jobs:
      - template: /eng/common/templates-official/jobs/jobs.yml@self
        parameters:
          enableMicrobuild: true
          enablePublishBuildAssets: true
          enablePublishBuildArtifacts: true
          enablePublishTestResults: true
          enableTelemetry: true
          jobs:
          - job: Windows
            pool:
              name: NetCore1ESPool-Internal
              demands: ImageOverride -equals windows.vs2022.amd64
            strategy:
              matrix:
                Release:
                  _BuildConfig: Release
                  _OfficialBuildArgs: /p:DotNetSignType=$(_SignType)
                    /p:TeamName=$(_TeamName)
                    /p:OfficialBuildId=$(BUILD.BUILDNUMBER)
            steps:
            - script: eng\common\cibuild.cmd
                -configuration $(_BuildConfig)
                -prepareMachine
                $(_OfficialBuildArgs)
              displayName: Build and Test

    - template: /eng/common/templates-official/post-build/post-build.yml@self
      parameters:
        enableSourceLinkValidation: false
        enableSigningValidation: true
        enableNugetValidation: true
```

**Key differences from public CI:**
- Uses `templates-official/` (not `templates/`)
- `enableMicrobuild: true` — installs MicroBuild Signing Plugin for code signing
- `enablePublishBuildAssets: true` — creates BAR entries and `ReleaseConfigs` artifact for post-build stages
- `_SignType` variable controls signing behavior (`Real` for production, `test` for development)
- **Do NOT use** `enablePublishUsingPipelines` or `/p:DotNetPublishUsingPipelines` — these are obsolete V2 parameters

## 1ES Pipeline Template

For repos that must comply with 1ES (One Engineering System) requirements, the official pipeline must extend the 1ES template. Key structure:

```yaml
resources:
  repositories:
  - repository: 1ESPipelineTemplates
    type: git
    name: 1ESPipelineTemplates/1ESPipelineTemplates
    ref: refs/tags/release

extends:
  template: v1/1ES.Official.PipelineTemplate.yml@1ESPipelineTemplates
  parameters:
    pool:
      name: NetCore1ESPool-Internal
      image: windows.vs2022.amd64
      os: windows
    stages:
    - stage: build
      ...
```

Note: For official (internal) builds, use `templates-official/` variants. For public CI, use `templates/`.

## Post-Build Publishing

The post-build template handles validation and publishing. Add it after all build stages:

```yaml
- template: /eng/common/templates-official/post-build/post-build.yml@self
  parameters:
    enableSourceLinkValidation: false
    enableSigningValidation: true
    enableNugetValidation: true
    publishInstallersAndChecksums: false
```

**Parameters:**
| Name | Type | Default | Description |
|------|------|---------|-------------|
| enableSourceLinkValidation | bool | false | Run SourceLink validation |
| enableSigningValidation | bool | true | Run signing validation |
| enableNugetValidation | bool | true | Run NuGet validation |
| publishInstallersAndChecksums | bool | true | Publish installers to dotnetcli storage |
| validateDependsOn | array | [build] | Stage(s) validation depends on |
| publishDependsOn | array | [Validate] | Stage(s) publishing depends on |

## Common Parameters

### Build script arguments for official builds:

```
/p:DotNetSignType=$(_SignType)
/p:TeamName=$(_TeamName)
/p:OfficialBuildId=$(BUILD.BUILDNUMBER)
```

**⚠️ Obsolete parameters — do NOT use:**
- `/p:DotNetPublishUsingPipelines=true` — V2 parameter, no longer exists in Arcade SDK 10+
- `enablePublishUsingPipelines` — use `enablePublishBuildAssets` instead

### Pool references:

**Internal pools:**
- `NetCore1ESPool-Internal` — regular internal builds
- `NetCore1ESPool-Svc-Internal` — release/servicing builds

**Public pools:**
- `NetCore-Public` — regular public CI
- `NetCore-Svc-Public` — release branch public CI

### Image overrides:
- `windows.vs2022.amd64` — Windows with VS2022 (or `windows.vs2026preview.scout.amd64` for preview)
- `build.ubuntu.2204.amd64.open` — Ubuntu 22.04 (public)
- `1es-ubuntu-2204` — Ubuntu 22.04 (internal, 1ES)

**Note:** Pool names and image overrides evolve. Check existing dotnet repos (runtime, aspire) for current values.

## 1ES SDL Auto-Baselining

Official builds using 1ES Pipeline Templates include automated SDL (Security Development Lifecycle) analysis. The auto-baselining feature tracks security scan baselines so new findings are surfaced while previously triaged results are suppressed.

### Required file

Create `.config/1espt/PipelineAutobaseliningConfig.yml` with an empty pipelines section:

```yaml
# 1ES Pipeline Template auto-baselining configuration.
# Pipeline IDs will be populated automatically once pipelines are registered in Azure DevOps.
#
# See 1ES Pipeline Templates SDL analysis documentation for details.
pipelines: {}
```

### How it works

- **Do NOT edit this file manually** after pipelines are registered. The 1ES automation system populates it.
- Once the official pipeline runs, 1ES adds pipeline IDs and baseline dates for each SDL tool:
  - `credscan` — detects secrets/credentials in source code
  - `eslint` — JavaScript/TypeScript linting
  - `psscriptanalyzer` — PowerShell script analysis
  - `armory` — general security scanning
  - `binskim` — binary analysis (compiled outputs)
  - `spotbugs` — Java static analysis (if applicable)
- Each tool entry under `source` or `binary` has a `lastModifiedDate` tracking when the baseline was last updated.
- To manage exceptions or reset baselines, use the portal at https://aka.ms/1espt-autobaselining.

### Example (after automation populates it)

```yaml
## DO NOT MODIFY THIS FILE MANUALLY.
pipelines:
  123456:
    retail:
      source:
        credscan:
          lastModifiedDate: 2024-03-11
        eslint:
          lastModifiedDate: 2024-03-11
        psscriptanalyzer:
          lastModifiedDate: 2024-03-11
        armory:
          lastModifiedDate: 2024-03-11
      binary:
        credscan:
          lastModifiedDate: 2024-03-11
        binskim:
          lastModifiedDate: 2024-03-11
```

### SDL parameters in official pipeline

The official pipeline template can configure SDL analysis inline:

```yaml
extends:
  template: v1/1ES.Official.PipelineTemplate.yml@1ESPipelineTemplates
  parameters:
    sdl:
      binskim:
        scanOutputDirectoryOnly: true
      codeql:
        runSourceLanguagesInSourceAnalysis: true
      policheck:
        enabled: true
      spotBugs:
        enabled: false
        justification: 'Not applicable — no Java code'
```

If the repo already has a `.config/1espt/PipelineAutobaseliningConfig.yml`, keep it as-is — the automation will update it.

## GitHub Actions CI

If the repository uses GitHub Actions instead of Azure Pipelines for public CI, it can still onboard to Arcade for build infrastructure. The arcade build scripts (`eng/common/cibuild.sh` and `eng/common/cibuild.cmd`) can be called from GitHub Actions steps:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-dotnet@v4
      with:
        global-json-file: global.json
    - run: ./eng/common/cibuild.sh --configuration Release --prepareMachine
      name: Build and Test
```

Note: Official builds and publishing still require Azure Pipelines at dnceng/internal.

## NuGet.org Publishing with 1ES.PublishNuget@1

For publishing NuGet packages to NuGet.org from dnceng official builds, use the `1ES.PublishNuget@1` task. This is the approved pattern for 1ES Pipeline Templates — do NOT use `DotNetCoreCLI@2` or `NuGetCommand@2` as they don't support encrypted API keys.

### CRITICAL: Must be a separate pipeline

**NuGet.org publishing MUST be in a separate pipeline** from the main build pipeline. MicroBuild signing (enabled via `enableMicrobuild: true`) activates CFS (Container Fencing Service) network isolation for the entire pipeline run. CFS redirects DNS for external hosts to TEST-NET IPs (`192.0.2.x`), blocking outbound HTTPS to NuGet.org. This cannot be overridden with `networkIsolationPolicy: Permissive` within the same pipeline — the MicroBuild CFS rules take precedence.

The solution is a dedicated `release-publish-nuget.yml` pipeline that:
- Has NO MicroBuild/signing stages (so CFS is not activated)
- References the build pipeline via `resources.pipelines`
- Downloads signed packages from a completed build run
- Publishes to NuGet.org in a clean network environment

### Prerequisites

1. **Service connection** for NuGet.org created at `dev.azure.com/dnceng/internal` with NuGet.org API key
2. **Pipeline definition** created in dnceng/internal pointing at `eng/pipelines/release-publish-nuget.yml`
3. **Network isolation** set to `Permissive` at the 1ES template level (NOT `Permissive,CFSClean` — that also blocks NuGet.org)

### Template

Create `eng/pipelines/release-publish-nuget.yml` as a standalone pipeline:

```yaml
# Release Pipeline: Publish NuGet Packages to NuGet.org
# MUST be separate from build pipeline - MicroBuild CFS blocks NuGet.org
trigger: none  # Manual trigger only
pr: none

parameters:
- name: DryRun
  displayName: 'Dry Run (skip actual NuGet push)'
  type: boolean
  default: false

resources:
  repositories:
  - repository: 1ESPipelineTemplates
    type: git
    name: 1ESPipelineTemplates/1ESPipelineTemplates
    ref: refs/tags/release
  pipelines:
  - pipeline: source-build
    source: {repo}-official  # Name of the main build pipeline definition
    project: internal
    trigger: none

extends:
  template: v1/1ES.Official.PipelineTemplate.yml@1ESPipelineTemplates
  parameters:
    pool:
      name: NetCore1ESPool-Internal
      image: windows.vs2026preview.scout.amd64
      os: windows
    settings:
      networkIsolationPolicy: Permissive

    stages:
    # Stage 1: Download artifacts and re-publish with SBOM
    # 1ES PT injects SBOM generation for templateContext outputs
    - stage: PrepareArtifacts
      displayName: Prepare Artifacts with SBOM
      jobs:
      - job: PrepareJob
        displayName: Download and Re-publish Artifacts
        timeoutInMinutes: 30
        pool:
          name: NetCore1ESPool-Internal
          image: windows.vs2026preview.scout.amd64
          os: windows
        templateContext:
          outputs:
          - output: pipelineArtifact
            displayName: Publish PackageArtifacts with SBOM
            targetPath: $(Pipeline.Workspace)/packages/PackageArtifacts
            artifactName: PackageArtifacts
        steps:
        - checkout: none
        - download: source-build
          displayName: Download PackageArtifacts from Source Build
          artifact: PackageArtifacts
          patterns: '**/*.nupkg'
        - powershell: |
            $sourcePath = "$(Pipeline.Workspace)/source-build/PackageArtifacts"
            $targetPath = "$(Pipeline.Workspace)/packages/PackageArtifacts"
            New-Item -ItemType Directory -Force -Path $targetPath | Out-Null
            $packages = Get-ChildItem -Path $sourcePath -Filter "*.nupkg" -Recurse
            Write-Host "Found $($packages.Count) packages"
            foreach ($pkg in $packages) {
                Write-Host "  - $($pkg.Name)"
                Copy-Item $pkg.FullName -Destination $targetPath
            }
          displayName: Move Artifacts to Output Path

    # Stage 2: Publish to NuGet.org
    - stage: Release
      displayName: Publish to NuGet.org
      dependsOn: PrepareArtifacts
      jobs:
      - job: PublishNuGet
        displayName: Push Packages to NuGet.org
        timeoutInMinutes: 30
        pool:
          name: NetCore1ESPool-Internal
          image: windows.vs2026preview.scout.amd64
          os: windows
        templateContext:
          type: releaseJob
          isProduction: true
          inputs:
          - input: pipelineArtifact
            artifactName: PackageArtifacts
            targetPath: $(Pipeline.Workspace)/PackageArtifacts
        steps:
        - task: 1ES.PublishNuget@1
          displayName: Push Packages to NuGet.org
          condition: eq('${{ parameters.DryRun }}', 'false')
          inputs:
            useDotNetTask: false
            packagesToPush: $(Pipeline.Workspace)/PackageArtifacts/*.nupkg
            packageParentPath: $(Pipeline.Workspace)/PackageArtifacts
            nuGetFeedType: external
            publishFeedCredentials: '{service-connection-name}'
```

### Key settings

| Setting | Value | Why |
|---------|-------|-----|
| `useDotNetTask` | `false` | `DotNetCoreCLI@2` doesn't support encrypted API keys |
| `templateContext.type` | `releaseJob` | Required for network access in 1ES templates |
| `isProduction` | `true` | Enables production network access (NuGet.org) |
| `nuGetFeedType` | `external` | NuGet.org is external to Azure DevOps |
| `packageParentPath` | Path to parent dir | Used by 1ES for package validation |
| Separate pipeline | No MicroBuild | CFS from signing blocks NuGet.org |

### Reference

- [dotnet/aspire release-publish-nuget.yml](https://github.com/dotnet/aspire/blob/main/eng/pipelines/release-publish-nuget.yml) — production example
- 1ES NuGet Packages documentation (available on the internal 1ES docs site)
