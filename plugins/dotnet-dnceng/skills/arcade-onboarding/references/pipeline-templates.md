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
