---
name: arcade-onboarding
description: "Onboard a .NET repository onto the dotnet/arcade build system. Handles creating or modifying global.json, Directory.Build.props/targets, eng/Versions.props, eng/Version.Details.xml, NuGet.config, eng/common/ scripts, Azure Pipelines YAML, eng/Publishing.props, eng/Signing.props, and es-metadata.yml. Supports NuGet.org publishing, GitHub-to-AzDO internal mirror setup, and darc/maestro dependency flow configuration. Triggers: 'arcade onboarding', 'onboard arcade', 'arcade SDK', 'dependency flow', 'darc setup', 'internal mirror', 'es-metadata', '1es inventory', or any request about adopting .NET Arcade infrastructure."
---

# Arcade Onboarding

Onboard a .NET repository onto the [dotnet/arcade](https://github.com/dotnet/arcade) build system, enabling shared tooling for versioning, signing, packaging, publishing, and CI/CD via Azure Pipelines with dependency flow through darc/maestro.

## Onboarding Workflow

1. **Analyze the repository** — scan for projects, output types, existing CI, NuGet dependencies
2. **Ask the user** about publishing preferences (NuGet.org yes/no, shipping scope) and 1ES metadata
3. **Create/modify infrastructure files** — global.json, Directory.Build.props/targets, eng/ files, NuGet.config, es-metadata.yml
4. **Copy eng/common/** — arcade shared build scripts
5. **Update dependencies via darc** — run `darc update-dependencies` to pull latest coherent Arcade SDK, eng/common, and global.json from the target channel
6. **Create Azure Pipelines YAML** — public CI and/or official build definitions
7. **Set up internal mirror** — configure GitHub → AzDO mirror for official builds
8. **Map dependencies to darc/maestro** — convert eligible NuGet references to flowable dependencies
9. **Summarize next steps** — darc setup, subscriptions, channel assignments

## Step 1: Analyze the Repository

Before making any changes, perform a thorough analysis:

### Scan for projects
```bash
find . -name "*.csproj" -o -name "*.fsproj" -o -name "*.vbproj" | head -50
find . -name "*.sln" | head -10
```

### Determine output types for each project
Read each csproj and check:
- `<OutputType>` — Exe, Library, WinExe
- `<IsPackable>` — whether it produces a NuGet package
- `<PackageId>` — custom package ID if set
- `<GeneratePackageOnBuild>` — auto-pack on build
- `<TargetFramework>` / `<TargetFrameworks>` — target platforms

### Classify projects
- **Shipping libraries** → `IsShipping=true`, produce NuGet packages
- **Internal/tooling libraries** → `IsShipping=false`
- **Applications/executables** → typically `IsShipping=false` unless distributed as global tools
- **Test projects** → `IsShipping=false`, excluded from packaging

### Scan existing CI
```bash
find . -name "*.yml" -o -name "*.yaml" | grep -E "(azure-pipelines|ci|build)" | head -20
cat .github/workflows/*.yml 2>/dev/null | head -100
```

Note existing build commands, matrix configurations, test steps for reference.

### Scan NuGet dependencies
```bash
grep -rh "PackageReference" --include="*.csproj" --include="*.fsproj" | sort -u
```

Check for existing version centralization:
```bash
cat Directory.Packages.props 2>/dev/null
cat eng/Versions.props 2>/dev/null
```

### Check existing arcade artifacts
```bash
ls global.json Directory.Build.props Directory.Build.targets eng/Versions.props eng/Version.Details.xml eng/common/ es-metadata.yml 2>/dev/null
```

If some arcade files exist, this is a **partial onboarding** — only create/modify what's missing.

### Check LICENSE file format

Arcade's `RepositoryValidation.proj` validates the `LICENSE` file line-by-line against the expected template (`tools/Licenses/MIT.txt` inside the Arcade SDK package). Lines with `*ignore-line*` are skipped (the copyright holder line). Any extra content — headers, preambles, project names — will cause a validation error.

```bash
cat LICENSE | head -5
```

**Common issue:** Files with a project name header (e.g. `Xamarin SDK`) before `The MIT License (MIT)` will fail. The LICENSE must start with `The MIT License (MIT)` on line 1.

**Expected format:**
```
The MIT License (MIT)

Copyright (c) <Your Copyright Holder>

All rights reserved.
...
```

### Check solution file configuration mappings

Inspect the `.sln` file for configuration mismatches. Visual Studio sometimes maps `Release|Any CPU` to `Debug|Any CPU` for specific projects, which causes them to build as Debug even when `-configuration Release` is passed. This means no packages are produced (Arcade outputs Release packages to `artifacts/packages/Release/Shipping/`).

```bash
grep -A2 "Release|Any CPU" *.sln
```

Look for lines like `{GUID}.Release|Any CPU.Build.0 = Debug|Any CPU` — these must be fixed to `Release|Any CPU`.

### Check AssemblyCopyright for signing compatibility

Arcade's `Sign.proj` (error SIGN004) inspects the `AssemblyCopyright` attribute in compiled DLLs to classify them as 1st-party or 3rd-party. If the copyright contains a non-Microsoft entity (e.g. `Xamarin Inc.`, `Google LLC`), the DLL is flagged as 3rd-party and signing with the Microsoft certificate fails.

```bash
# Check for manual AssemblyInfo files
find . -name "AssemblyInfo.cs" -not -path "./eng/*" -not -path "./.packages/*" -not -path "./artifacts/*"

# Check if projects disable auto-generated assembly info
grep -rn "GenerateAssemblyInfo.*false" --include="*.csproj"
```

**If `GenerateAssemblyInfo` is `false`:** The copyright from the manual `AssemblyInfo.cs` is used — update `AssemblyCopyright` to `© Microsoft Corporation. All rights reserved.` (or similar Microsoft copyright).

**If `GenerateAssemblyInfo` is `true` (default):** The `<Copyright>` MSBuild property in the csproj or `Directory.Build.props` is used — ensure it contains a Microsoft copyright.

## Step 2: User Configuration

Ask the user:

1. **NuGet.org publishing?** — Should any packages from this repo be published to NuGet.org?
   - If yes: which projects are shipping? (default: all library projects)
   - If no: set `<IsShipping>false</IsShipping>` globally

2. **1ES inventory metadata (es-metadata.yml)** — Based on the shipping answer:
   - If **IsShipping=true** → `isProduction: true` in `es-metadata.yml`. Then ask:
     - **Service Tree ID** — The GUID identifying this service in Microsoft's Service Tree. Ask: "What is the Service Tree ID (GUID) for this repo? You can find it at https://servicetree.msft.ms/ (Microsoft internal)". If the user doesn't know it, use a placeholder: `<SERVICE_TREE_ID>`.
     - **Default Area Path** — The Azure DevOps area path for routing issues. Ask: "What Azure DevOps org and area path should be used for routing? (e.g., org: devdiv, path: DevDiv\\.NET MAUI)". If the user doesn't know, use placeholders: `org: <AZDO_ORG>`, `path: <AZDO_AREA_PATH>`.
   - If **IsShipping=false** → `isProduction: false` in `es-metadata.yml`. Still ask for Service Tree ID and area path (or use placeholders).

3. **Version prefix** — What version should the repo use? (e.g. `1.0.0`, `8.0.0`)

4. **Pre-release label** — `preview`, `beta`, `alpha`, `rc`, or empty for release-only

5. **License** — MIT, Apache-2.0, or other

## Step 3: Create/Modify Infrastructure Files

Read [references/file-templates.md](references/file-templates.md) for complete templates.

### File creation order (dependencies flow top-down):

1. **global.json** — reference Arcade SDK with a seed version. The `tools.dotnet` version should match the .NET SDK major version the repo targets (e.g. `10.0.104` for .NET 10). The Arcade SDK version will be updated by `darc update-dependencies` in the next step — use any recent version as seed (e.g. from the VMR's `global.json`).

2. **Directory.Build.props** — import `Sdk.props` from Arcade SDK. If file exists, add the import at the top and merge properties. Set `<IsShipping>` based on user preference.

3. **Directory.Build.targets** — import `Sdk.targets` from Arcade SDK. If file exists, add the import at the top.

4. **eng/Versions.props** — set `VersionPrefix`, `PreReleaseVersionLabel`, `PreReleaseVersionIteration`, and all dependency version properties. Migrate versions from any existing `Directory.Packages.props` or centralized version file.

5. **eng/Version.Details.xml** — create with Arcade SDK dependency entry pointing to `https://github.com/dotnet/dotnet` (VMR). Use a seed version and SHA — `darc update-dependencies` (Step 5) will update these to the latest coherent versions. Add entries for all dependencies that will flow via maestro (see Step 8).

6. **NuGet.config** — add required dnceng feeds (`dotnet-public`, `dotnet-tools`, `dotnet-eng`, `dotnet10`). **Do not include nuget.org** — the `dotnet-public` feed mirrors it and CFS requires using only approved feeds. If file exists, merge feeds.

7. **eng/Publishing.props** — create with `<PublishingVersion>3</PublishingVersion>`.

8. **eng/Signing.props** — configure signing certificates for MicroBuild/ESRP. Map first-party DLLs to the .NET certificate, third-party DLLs to `3PartySHA2`, and file extensions like `.js` to `None`. See [references/file-templates.md](references/file-templates.md#engsigningprops).

9. **eng/SignCheckExclusionsFile.txt** — exclusions for post-build SignCheck validation. Must be consistent with `Signing.props` — e.g. if `.js` is `None` in `Signing.props`, add `*.js` here. See [references/file-templates.md](references/file-templates.md#engsigncheckexclusionsfiletxt).

10. **es-metadata.yml** — 1ES inventory-as-code metadata. Required for all repos in the 1ES ecosystem. Set `isProduction` based on shipping status, and populate Service Tree ID and area path from user input (or placeholders). See [references/file-templates.md](references/file-templates.md#es-metadatayml).

### Important rules:
- **Never delete** existing content from files — always merge
- If repo uses `Directory.Packages.props` (Central Package Management), **both approaches are valid**:
  - **Option A (aspire pattern)**: Keep CPM active. Dependency versions flow into `eng/Versions.props`, and `Directory.Packages.props` references those properties via `$(PropertyName)`. Enable `<CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>`.
  - **Option B**: Migrate all versions from `Directory.Packages.props` to `eng/Versions.props` and update PackageReference elements to use `$(VersionPropertyName)` pattern. Disable CPM.
  - **Prefer Option A** if CPM is already well-established.
- **NU1507 warning**: Always add `<NoWarn>$(NoWarn);NU1507</NoWarn>` in `Directory.Build.props`. Official builds inject internal feeds via `SetupNugetSources` that break `packageSourceMapping`. Do NOT rely on `packageSourceMapping` alone.
- Ensure all `.sh` files have executable permissions: `git add --chmod=+x *.sh`
- Use the computed `VersionPrefix` pattern: `<VersionPrefix>$(MajorVersion).$(MinorVersion).$(PatchVersion)</VersionPrefix>` (matches runtime and aspire)
- Always set `PreReleaseVersionIteration` (e.g. `1`) — produces `preview.1.{build}` versioning which gives clearer NuGet sort order than `preview.{build}` alone. Bump for each release cycle: `preview.1` → `preview.2` → `rc.1`.

## Step 4: Copy eng/common/

The `eng/common/` folder must be copied wholesale from the arcade repo. This contains shared build scripts, pipeline templates, and tooling.

Use the provided helper script to safely copy eng/common:

```bash
# From the skill's scripts directory (or copy the script to your repo first)
./scripts/copy_eng_common.sh [target_repo_root] [arcade_ref]

# Example: copy eng/common from arcade main branch to current directory
bash <(curl -s https://raw.githubusercontent.com/dotnet/arcade/main/eng/common/darc-init.sh) || true
```

Or manually with mktemp:
```bash
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT
git clone --depth 1 https://github.com/dotnet/arcade.git "$TEMP_DIR/arcade"
cp -r "$TEMP_DIR/arcade/eng/common" eng/common
find eng/common -name "*.sh" -exec chmod +x {} \;
git add --chmod=+x eng/common/**/*.sh
```

Key files in eng/common/:
- `build.sh` / `build.cmd` — entry points for builds (requires explicit flags like `--restore --build --ci`)
- `cibuild.sh` / `cibuild.cmd` — CI build wrappers (automatically pass `--restore --build --test --pack --publish --ci`)
- `dotnet-install.sh` / `dotnet-install.ps1` — SDK acquisition
- `templates/` — public CI pipeline templates
- `templates-official/` — official (internal) build pipeline templates
- `post-build/` — publishing and validation templates

**⚠️ build.sh vs cibuild.sh:** `cibuild.sh` is a thin wrapper that calls `build.sh` with `--ci` and all action flags. When using `build.sh` directly (e.g. for macOS jobs that skip test or need custom flags), **always pass `--ci`** — without it, no binary logs are created (`artifacts/log/` doesn't exist), and pipeline steps like "Publish Logs" will fail with `Not found PathtoPublish`.

## Step 5: Update Dependencies via Darc

After creating infrastructure files and copying `eng/common/`, run `darc update-dependencies` to pull the **latest coherent versions** from the appropriate .NET SDK channel. This updates `global.json`, `eng/Version.Details.xml`, and `eng/Versions.props` with versions that are known to work together.

### Why this step matters

Creating files manually with hardcoded versions is error-prone — the Arcade SDK version, SHA, and `eng/common/` scripts must all be coherent (from the same build). `darc update-dependencies` resolves this by pulling all related versions from a single channel build.

### Determine the target channel

Ask the user which .NET version they target, then pick the matching channel:

| .NET Version | Channel Name | Example |
|-------------|-------------|---------|
| .NET 10 | `.NET 10.0.1xx SDK` | Arcade SDK 10.x |
| .NET 9 | `.NET 9.0.1xx SDK` | Arcade SDK 9.x |
| .NET Eng Latest | `.NET Eng - Latest` | Bleeding edge (arcade repo directly) |

**⚠️ SDK compatibility:** Arcade SDK major version must match the .NET SDK major version. Arcade SDK 10.x requires .NET 10 SDK; Arcade SDK 11.x requires .NET 11 SDK (its MSBuild tasks reference System.Text.Json from that SDK). Using a mismatched SDK causes `FileNotFoundException` at build time. **For most repos, use Arcade SDK 10.x from the `.NET 10.0.1xx SDK` channel.**

```bash
# List available channels
darc get-channels | grep -i "10.0\|9.0\|eng.*latest"
```

### Seed the Version.Details.xml

Before running darc, `eng/Version.Details.xml` must have the Arcade SDK dependency pointing to `https://github.com/dotnet/dotnet` (the VMR). Use any recent seed version — darc will update it:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Dependencies>
  <ToolsetDependencies>
    <Dependency Name="Microsoft.DotNet.Arcade.Sdk" Version="10.0.0-beta.25001.1">
      <Uri>https://github.com/dotnet/dotnet</Uri>
      <Sha>0000000000000000000000000000000000000000</Sha>
    </Dependency>
  </ToolsetDependencies>
</Dependencies>
```

**Important:** The URI must be `https://github.com/dotnet/dotnet` (the VMR/dotnet-dotnet repo), **not** `https://github.com/dotnet/arcade`. The Arcade SDK is published from the VMR for .NET 9+ channels. Using `dotnet/arcade` only works for the `.NET Eng - Latest` channel.

### Run the update

```bash
darc update-dependencies --channel ".NET 10.0.1xx SDK" --verbose
```

This will:
1. Query the latest build from the specified channel
2. Update `eng/Version.Details.xml` with the correct version and SHA
3. Update `global.json` with the matching Arcade SDK version
4. Update `eng/Versions.props` if it has any version properties tracked by darc
5. Update `eng/common/` scripts to match the Arcade SDK version

### Verify the update

```bash
# Check that global.json was updated
cat global.json

# Check that Version.Details.xml has the correct SHA and version
cat eng/Version.Details.xml

# Verify the build still works
./eng/common/build.sh --restore --build --pack --configuration Release --prepareMachine
```

### Channel selection guidance

- **For most repos targeting a stable .NET release** → use `.NET {Major}.0.1xx SDK` (e.g. `.NET 10.0.1xx SDK`)
- **For repos that need the latest arcade features** → use `.NET Eng - Latest` (but the dependency URI should be `dotnet/arcade`)
- **For repos targeting a preview/RC** → use the matching SDK RC channel (e.g. `.NET 10.0.1xx SDK RC 2`)

## Step 6: Create Azure Pipelines YAML

Read [references/pipeline-templates.md](references/pipeline-templates.md) for complete templates.

**Decision tree:**
- **Public CI only** (open source, no signing/publishing) → create `azure-pipelines.yml` using public templates
- **Official builds** (signing, publishing, NuGet) → create official pipeline YAML using 1ES templates
- **Both** (typical for dotnet repos) → create both

Adapt the pipeline to match:
- The platforms detected in existing CI (Windows, Linux, macOS)
- The build commands used (typically `eng/common/cibuild.cmd` / `cibuild.sh`)
- Test configurations from existing YAML

### Critical official pipeline parameters

The jobs template accepts many parameters. These are the most important — getting them wrong causes hard-to-debug failures:

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `enableMicrobuild` | **Yes** for signing | `false` | Installs MicroBuild Signing Plugin. Without this, `DotNetSignType=Real` fails silently |
| `enablePublishBuildAssets` | **Yes** for post-build | `false` | Runs `publish-build-assets.yml` which creates BAR entries and the `ReleaseConfigs` artifact. Without this, the `Validate` stage fails with "Artifact ReleaseConfigs not found" |
| `enablePublishBuildArtifacts` | Yes | `false` | Publishes build outputs (packages, logs) as pipeline artifacts |
| `enablePublishTestResults` | Optional | `false` | Publishes test results to Azure DevOps |

**⚠️ Legacy parameter warning:** `enablePublishUsingPipelines` was used in Arcade SDK V2 but **no longer exists** in Arcade SDK 10+. Use `enablePublishBuildAssets` instead. Similarly, remove `/p:DotNetPublishUsingPipelines=true` from MSBuild arguments — it's obsolete.

### Signing variables

Official builds need the `_SignType` variable. Set it in the pipeline variables:

```yaml
variables:
- name: _SignType
  value: test    # Start with 'test', switch to 'Real' after pipeline is validated
```

Then reference it in build arguments:
```yaml
_OfficialBuildArgs: /p:DotNetSignType=$(_SignType)
  /p:TeamName=$(_TeamName)
  /p:OfficialBuildId=$(BUILD.BUILDNUMBER)
```

**Recommended signing rollout:**
1. **Start with `test`** — validates the full signing pipeline (MicroBuild plugin installation, `Sign.proj` execution, certificate mapping) without requiring ESRP service connection approval. This lets you confirm everything works end-to-end.
2. **Switch to `Real`** — once test signing passes, submit a follow-up PR changing `_SignType: test` → `_SignType: Real`. The first Real build will **pause waiting for service connection approval**:
   - `DevDiv-ESRP-PME-DNCENG` — ESRP code signing service
   - `MicroBuild Signing Task (DevDiv)` — MicroBuild signing plugin
   - `Darc: Maestro Production` — post-build publishing
   Ask in the **dnceng First Responders** Teams channel to approve these. This is a **one-time setup** per pipeline definition.

### 1ES SDL Auto-Baselining

If using 1ES official pipeline templates, ensure `.config/1espt/PipelineAutobaseliningConfig.yml` exists. If it doesn't, create it with empty pipelines:

```yaml
pipelines: {}
```

The 1ES automation will populate pipeline IDs and SDL tool baselines (credscan, binskim, eslint, etc.) after the first official build runs. **Do not edit this file manually after it's populated.** See [references/pipeline-templates.md](references/pipeline-templates.md#1es-sdl-auto-baselining) for details.

## Step 6b: Configure Signing

Signing is handled by MicroBuild/ESRP during official builds. There are **two separate mechanisms**:

1. **Build-time signing** (`eng/Signing.props`) — maps files to signing certificates. See [references/file-templates.md](references/file-templates.md#engsigningprops) for the template.

2. **Post-build validation** (`eng/SignCheckExclusionsFile.txt`) — excludes files from SignCheck verification. Must be consistent with `Signing.props`. See [references/file-templates.md](references/file-templates.md#engsigncheckexclusionsfiletxt).

3. **Pipeline configuration** — enable MicroBuild and set sign type in the official pipeline YAML:
   - `enableMicrobuild: true` in jobs template parameters (REQUIRED)
   - `_SignType: test` initially, then `Real` after validation
   - Pass `/p:DotNetSignType=$(_SignType)` to the build command

**Certificate types:** `UseDotNetCertificate` (first-party .NET), `3PartySHA2` (third-party), `NuGet` (.nupkg), `None` (static assets like .js).

**How to find third-party DLLs:** Build locally, then inspect nupkg contents:
```bash
for f in artifacts/packages/Release/Shipping/*.nupkg; do
  echo "=== $(basename $f) ==="; unzip -l "$f" | grep "\.dll$" | awk '{print $NF}'
done
```

**How MicroBuild signing works:** Arcade's `job.yml` installs `MicroBuildSigningPlugin@4` → build runs `Sign.proj` which reads `Signing.props` → signs DLLs in rounds (Round 0: DLLs, Round 1: re-packed nupkgs) → post-build `SignCheck` validates signatures using `SignCheckExclusionsFile.txt`.

## Step 7: Set Up Internal Mirror

Read [references/internal-mirror.md](references/internal-mirror.md) for the complete guide.

Official builds run at `dev.azure.com/dnceng/internal` and require a mirrored copy of the GitHub repo. Ask the user if they need official builds (signing, publishing). If yes:

### Determine mirror repo name

Convention: `{org}-{repo}` with `/` replaced by `-`.
- `github.com/dotnet/maui-labs` → `dotnet-maui-labs`

### Generate mirroring configuration

Create the JSON snippet for the `dnceng-subscriptions.jsonc` entry:

```jsonc
    "https://github.com/{OWNER}/{REPO}": {
      "fastForward": [
        "main",
        "release/.*"
      ]
    },
```

### Inform the user of manual steps

The mirror setup requires actions that cannot be automated:
1. **Contact @dnceng** to create the internal repo at `dev.azure.com/dnceng/internal/_git/{org}-{repo}`
2. **Submit a PR** to `dev.azure.com/dnceng/internal/_git/dotnet-mirroring` updating `dnceng-subscriptions.jsonc`
3. **Create pipeline definitions** at `dnceng-public/public` (CI) and `dnceng/internal` (official)
4. **Request signing approval** for the official build pipeline if packages need Authenticode signing

### Pipeline folder structure

```
dnceng-public/public:
  {org}/{repo}/{repo}-ci

dnceng/internal:
  {org}/{repo}/{repo}-official
```

## Step 8: Map Dependencies to Darc/Maestro

Read [references/dependency-flow.md](references/dependency-flow.md) for the complete guide.

### Process:

1. Collect all PackageReference items across all csproj files
2. For each package, determine if it's produced by a known dotnet/* repo (see common repo mapping in reference)
3. For flowable packages:
   - Add entry to `eng/Version.Details.xml` with source repo URI and SHA
   - Add version property to `eng/Versions.props`
   - Update csproj PackageReference to use `$(VersionPropertyName)` pattern
4. For non-flowable packages (third party):
   - Add version property to `eng/Versions.props`
   - Update csproj PackageReference to use `$(VersionPropertyName)` pattern

### Package name to version property convention:
Replace dots with nothing, append `Version`:
- `Microsoft.Extensions.Logging` → `<MicrosoftExtensionsLoggingVersion>`
- `System.Text.Json` → `<SystemTextJsonVersion>`

## Step 9: Darc Setup and Summary

After all files are created/modified:

### Check and install darc

```bash
which darc || ls ~/.dotnet/tools/darc 2>/dev/null
```

If not installed, ask the user and run: `./eng/common/darc-init.sh` (macOS/Linux) or `.\eng\common\darc-init.ps1` (Windows). Then verify authentication with `darc get-channels`.

### Generate setup script

Create `eng/setup-darc.sh` (or `.ps1`) with all darc commands pre-filled. The script should:
1. Check/install darc, verify authentication
2. Set default channel: `darc add-default-channel --branch refs/heads/main --repo $REPO --channel "<CHANNEL>"`
3. Subscribe to arcade/VMR updates: `darc add-subscription --channel "<SDK_CHANNEL>" --source-repo https://github.com/dotnet/dotnet --target-repo $REPO --target-branch main --update-frequency everyDay --standard-automerge`
4. Subscribe to each product dependency source repo (one block per source in Version.Details.xml)
5. Verify with `darc get-subscriptions --target-repo $REPO`

See [references/dependency-flow.md](references/dependency-flow.md) for the complete template and channel selection guidance.

Make the script executable: `chmod +x eng/setup-darc.sh`

Ask the user: "I've created `eng/setup-darc.sh`. Would you like me to run it now, or will you run it after merge?"

### Provide summary

1. **List of files created/modified** with a brief description of each change
2. **Azure DevOps pipeline setup** — instructions to create pipeline definitions in dnceng-public and/or dnceng/internal
3. **Build verification** — run `./eng/common/cibuild.sh --configuration Release --prepareMachine` to verify the setup works
4. **Remaining manual steps** — GitHub app installation (dotnet-maestro), service connections, etc.

## Validation

Cross-check generated files against known arcade-onboarded repos for correctness:

| File | Check against |
|------|---------------|
| global.json | [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/global.json) — `msbuild-sdks` shape |
| Directory.Build.props | [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/Directory.Build.props) — Arcade SDK import at top |
| eng/Versions.props | [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/eng/Versions.props) — MajorVersion/MinorVersion/PatchVersion pattern, StabilizePackageVersion |
| eng/Version.Details.xml | [dotnet/runtime](https://github.com/dotnet/runtime/blob/main/eng/Version.Details.xml) — ProductDependencies/ToolsetDependencies structure |
| NuGet.config | [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/NuGet.config) — feed URLs, packageSourceMapping |
| eng/Publishing.props | [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/eng/Publishing.props) — PublishingVersion=3 |
| es-metadata.yml | [dotnet/maui](https://github.com/dotnet/maui/blob/main/es-metadata.yml), [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/es-metadata.yml), [dotnet/runtime](https://github.com/dotnet/runtime/blob/main/es-metadata.yml) — schemaVersion, isProduction, service tree ID, area path |
| Official pipeline | [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/eng/pipelines/azure-pipelines.yml) — 1ES template, post-build |

**Key patterns validated against real repos:**
- `VersionPrefix` is computed from `$(MajorVersion).$(MinorVersion).$(PatchVersion)` (not hardcoded)
- `StabilizePackageVersion` property exists for release cutting
- CPM (Directory.Packages.props) is compatible with arcade (aspire uses it)
- Package source mapping prevents NU1507 with CPM + multiple feeds

## Build Verification

See [references/build-verification.md](references/build-verification.md) for detailed build verification steps, common build failures, and known issues with workarounds.

**Quick check:** After completing the steps above, verify the build works:
```bash
./eng/common/build.sh --restore --build --pack --configuration Release --prepareMachine
ls artifacts/packages/Release/Shipping/
```
