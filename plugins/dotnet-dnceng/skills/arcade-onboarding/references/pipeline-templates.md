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
variables:
  - name: _TeamName
    value: <TEAM_NAME>
  - group: SDL_Settings

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

    stages:
    - stage: build
      displayName: Build
      jobs:
      - template: /eng/common/templates-official/jobs/jobs.yml@self
        parameters:
          enablePublishUsingPipelines: true
          enablePublishBuildArtifacts: true
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
                    /p:DotNetPublishUsingPipelines=true
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
/p:DotNetPublishUsingPipelines=true
/p:OfficialBuildId=$(BUILD.BUILDNUMBER)
```

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
# See: https://eng.ms/docs/cloud-ai-platform/devdiv/one-engineering-system-1es/1es-docs/1es-pipeline-templates/features/sdlanalysis/overview
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
