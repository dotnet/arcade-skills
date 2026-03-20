---
name: arcade-onboarding
description: "Onboard a .NET repository onto the dotnet/arcade build system. Use when a user wants to adopt Arcade SDK for building, versioning, signing, packaging, and publishing .NET projects. Handles creating or modifying global.json, Directory.Build.props/targets, eng/Versions.props, eng/Version.Details.xml, NuGet.config, eng/common/ scripts, Azure Pipelines YAML, and eng/Publishing.props. Supports configuring NuGet.org publishing (shipping vs non-shipping), setting up GitHub-to-AzDO internal mirror for official builds, identifying NuGet dependencies that can be replaced with darc/maestro dependency flow, and setting up subscriptions for automatic dependency updates. Triggers: 'arcade onboarding', 'onboard arcade', 'arcade SDK', 'dotnet arcade', 'arcade build system', 'dependency flow', 'darc onboarding', 'maestro setup', 'arcade publishing', 'internal mirror', 'dnceng mirror', or any request about adopting the .NET Arcade infrastructure."
---

# Arcade Onboarding

Onboard a .NET repository onto the [dotnet/arcade](https://github.com/dotnet/arcade) build system, enabling shared tooling for versioning, signing, packaging, publishing, and CI/CD via Azure Pipelines with dependency flow through darc/maestro.

## Onboarding Workflow

1. **Analyze the repository** — scan for projects, output types, existing CI, NuGet dependencies
2. **Ask the user** about publishing preferences (NuGet.org yes/no, shipping scope)
3. **Create/modify infrastructure files** — global.json, Directory.Build.props/targets, eng/ files, NuGet.config
4. **Copy eng/common/** — arcade shared build scripts
5. **Create Azure Pipelines YAML** — public CI and/or official build definitions
6. **Set up internal mirror** — configure GitHub → AzDO mirror for official builds
7. **Map dependencies to darc/maestro** — convert eligible NuGet references to flowable dependencies
8. **Summarize next steps** — darc setup, subscriptions, channel assignments

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
ls global.json Directory.Build.props Directory.Build.targets eng/Versions.props eng/Version.Details.xml eng/common/ 2>/dev/null
```

If some arcade files exist, this is a **partial onboarding** — only create/modify what's missing.

## Step 2: User Configuration

Ask the user:

1. **NuGet.org publishing?** — Should any packages from this repo be published to NuGet.org?
   - If yes: which projects are shipping? (default: all library projects)
   - If no: set `<IsShipping>false</IsShipping>` globally

2. **Version prefix** — What version should the repo use? (e.g. `1.0.0`, `8.0.0`)

3. **Pre-release label** — `preview`, `beta`, `alpha`, `rc`, or empty for release-only

4. **License** — MIT, Apache-2.0, or other

## Step 3: Create/Modify Infrastructure Files

Read [references/file-templates.md](references/file-templates.md) for complete templates.

### File creation order (dependencies flow top-down):

1. **global.json** — reference Arcade SDK. Use latest version from [arcade releases](https://github.com/dotnet/arcade/releases) or from arcade-validation's global.json. If file exists, merge `msbuild-sdks` section.

2. **Directory.Build.props** — import `Sdk.props` from Arcade SDK. If file exists, add the import at the top and merge properties. Set `<IsShipping>` based on user preference.

3. **Directory.Build.targets** — import `Sdk.targets` from Arcade SDK. If file exists, add the import at the top.

4. **eng/Versions.props** — set `VersionPrefix`, `PreReleaseVersionLabel`, `PreReleaseVersionIteration`, and all dependency version properties. Migrate versions from any existing `Directory.Packages.props` or centralized version file.

5. **eng/Version.Details.xml** — create with Arcade SDK dependency entry at minimum. Add entries for all dependencies that will flow via maestro (see Step 6).

6. **NuGet.config** — add required dnceng feeds. If file exists, merge feeds. Keep existing feeds the repo needs (e.g. nuget.org for third-party packages).

7. **eng/Publishing.props** — create with `<PublishingVersion>3</PublishingVersion>`.

8. **eng/Signing.props** — configure signing certificates for MicroBuild/ESRP. Map first-party DLLs to the .NET certificate, third-party DLLs to `3PartySHA2`, and file extensions like `.js` to `None`. See [references/file-templates.md](references/file-templates.md#engsigningprops).

9. **eng/SignCheckExclusionsFile.txt** — exclusions for post-build SignCheck validation. Must be consistent with `Signing.props` — e.g. if `.js` is `None` in `Signing.props`, add `*.js` here. See [references/file-templates.md](references/file-templates.md#engsigncheckexclusionsfiletxt).

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

```bash
# Clone arcade to get eng/common
git clone --depth 1 https://github.com/dotnet/arcade.git /tmp/arcade-clone
cp -r /tmp/arcade-clone/eng/common eng/common

# Ensure shell scripts are executable
find eng/common -name "*.sh" -exec chmod +x {} \;
git add --chmod=+x eng/common/**/*.sh

rm -rf /tmp/arcade-clone
```

Key files in eng/common/:
- `build.sh` / `build.cmd` — entry points for builds
- `cibuild.sh` / `cibuild.cmd` — CI build wrappers
- `dotnet-install.sh` / `dotnet-install.ps1` — SDK acquisition
- `templates/` — public CI pipeline templates
- `templates-official/` — official (internal) build pipeline templates
- `post-build/` — publishing and validation templates

## Step 5: Create Azure Pipelines YAML

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
  value: Real    # Use 'test' for testing, 'Real' for production signing
```

Then reference it in build arguments:
```yaml
_OfficialBuildArgs: /p:DotNetSignType=$(_SignType)
  /p:TeamName=$(_TeamName)
  /p:OfficialBuildId=$(BUILD.BUILDNUMBER)
```

### 1ES SDL Auto-Baselining

If using 1ES official pipeline templates, ensure `.config/1espt/PipelineAutobaseliningConfig.yml` exists. If it doesn't, create it with empty pipelines:

```yaml
pipelines: {}
```

The 1ES automation will populate pipeline IDs and SDL tool baselines (credscan, binskim, eslint, etc.) after the first official build runs. **Do not edit this file manually after it's populated.** See [references/pipeline-templates.md](references/pipeline-templates.md#1es-sdl-auto-baselining) for details.

## Step 5b: Configure Signing

Signing is handled by MicroBuild/ESRP during official builds. There are **two separate mechanisms** that must be configured:

### 1. Build-time signing (`eng/Signing.props`)

Controls which files get signed during the build and which certificate to use. Create `eng/Signing.props`:

```xml
<Project>
  <PropertyGroup>
    <UseDotNetCertificate>true</UseDotNetCertificate>
  </PropertyGroup>

  <!-- Third-party assemblies that ship inside NuGet packages -->
  <ItemGroup Label="Third Party Assemblies">
    <!-- List every third-party DLL bundled in your packages -->
    <FileSignInfo Include="ThirdParty.dll" CertificateName="3PartySHA2" />
  </ItemGroup>

  <!-- File extension signing rules -->
  <ItemGroup>
    <FileExtensionSignInfo Update=".nupkg" CertificateName="NuGet" />
    <!-- JS files are static assets, not Windows executables — skip signing -->
    <FileExtensionSignInfo Update=".js" CertificateName="None" />
  </ItemGroup>
</Project>
```

**Certificate types:**
| Certificate | Use for |
|-------------|---------|
| `UseDotNetCertificate` (property) | First-party .NET assemblies (your DLLs) — set to `true` |
| `3PartySHA2` | Redistributed third-party assemblies bundled in your packages |
| `NuGet` | NuGet package files (`.nupkg`) |
| `None` | Files that should not be signed (`.js`, `.css`, static assets) |

**How to find third-party DLLs:** After building locally, inspect the NuGet packages:
```bash
# List all DLLs in each nupkg
for f in artifacts/packages/Release/Shipping/*.nupkg; do
  echo "=== $(basename $f) ==="
  unzip -l "$f" | grep "\.dll$" | awk '{print $NF}'
done
```
Any DLL not produced by your repo's projects is a third-party DLL that needs `3PartySHA2`.

### 2. Post-build validation (`eng/SignCheckExclusionsFile.txt`)

The post-build `Signing Validation` stage runs **SignCheck** which independently validates all files in NuGet packages. This uses a **separate exclusion mechanism** from `Signing.props`. If your packages contain `.js` files (e.g. Blazor static web assets), they will fail validation unless excluded.

Create `eng/SignCheckExclusionsFile.txt`:
```
;; Exclusions for SignCheck. Corresponds to info in Signing.props.
;; Format: https://github.com/dotnet/arcade/blob/397316e195639450b6c76bfeb9823b40bee72d6d/src/SignCheck/Microsoft.SignCheck/Verification/Exclusion.cs#L23-L35
*.js;; We do not sign JavaScript files.
```

**Exclusion format:** Each line is a glob pattern, optionally followed by `;;` and a comment.

**Key insight:** `Signing.props` and `SignCheckExclusionsFile.txt` serve different purposes:
- `Signing.props` → tells MicroBuild **what to sign and with which cert** during the build
- `SignCheckExclusionsFile.txt` → tells **post-build SignCheck validation** what to skip when verifying

Both must be consistent — if you exclude `.js` from signing in `Signing.props`, also exclude it in `SignCheckExclusionsFile.txt`.

### 3. Pipeline configuration for signing

In the official pipeline YAML, enable MicroBuild and set the sign type:

```yaml
variables:
- name: _SignType
  value: Real    # 'Real' for production, 'test' for dev/testing

stages:
- stage: build
  jobs:
  - template: /eng/common/templates-official/jobs/jobs.yml@self
    parameters:
      enableMicrobuild: true          # REQUIRED for signing
      enablePublishBuildAssets: true   # REQUIRED for post-build
      enablePublishBuildArtifacts: true
      jobs:
      - job: Windows
        steps:
        - script: eng\common\cibuild.cmd
            -configuration $(_BuildConfig)
            -prepareMachine
            /p:DotNetSignType=$(_SignType)
            /p:TeamName=$(_TeamName)
            /p:OfficialBuildId=$(BUILD.BUILDNUMBER)
```

### How MicroBuild signing works (architecture)

1. **MicroBuild Plugin installed** — Arcade's `job.yml` installs `MicroBuildSigningPlugin@4` as a pre-build step (conditional on `enableMicrobuild: true` + non-public + non-PR)
2. **Build runs** — `cibuild.cmd` calls MSBuild which calls `Sign.proj`
3. **Sign.proj invokes SignToolTask** — reads `Signing.props` for certificate mappings, extracts DLLs from NuGet packages
4. **Signing happens in rounds** — Round 0: individual DLLs, Round 1: NuGet packages (re-packed after DLL signing)
5. **Post-build validation** — `SignCheck` (in the `Validate` stage) independently verifies all files are properly signed, using `SignCheckExclusionsFile.txt` for exclusions

## Step 6: Set Up Internal Mirror

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

## Step 7: Map Dependencies to Darc/Maestro

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

## Step 8: Darc Setup and Summary

After all files are created/modified:

### Check and install darc

```bash
# Check if darc is installed
which darc || ls ~/.dotnet/tools/darc 2>/dev/null
```

If not installed, ask the user: "darc CLI is not installed. Should I install it now?"

If yes:
```bash
./eng/common/darc-init.sh   # macOS/Linux
# or: .\eng\common\darc-init.ps1   # Windows
```

Then check authentication:
```bash
darc get-channels 2>&1 | head -5
```

If authentication fails, prompt the user to run `darc authenticate` which opens a browser to get a BAR token.

### Generate setup script

Create `eng/setup-darc.sh` (or `.ps1`) in the repo with all the darc commands pre-filled for this specific repo. The script should:
1. Check if darc is installed, install if missing
2. Verify authentication
3. Set the default channel
4. Create all subscriptions (arcade, plus one per source repo in Version.Details.xml)
5. Print a summary of what was configured

Use this template — replace OWNER, REPO, channel names, and subscription entries based on the analysis from Steps 1 and 7:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/OWNER/REPO"
TARGET_BRANCH="main"

echo "=== Arcade Dependency Flow Setup ==="
echo ""

# 1. Check darc
if ! command -v darc &>/dev/null && [ ! -f ~/.dotnet/tools/darc ]; then
  echo "Installing darc CLI..."
  ./eng/common/darc-init.sh
  export PATH="$HOME/.dotnet/tools:$PATH"
fi

# 2. Verify authentication
if ! darc get-channels &>/dev/null 2>&1; then
  echo "darc is not authenticated. Running 'darc authenticate'..."
  echo "You will need a BAR token from https://maestro.dot.net/"
  darc authenticate
fi

# 3. Set default channel
echo ""
echo "Setting default channel..."
darc add-default-channel \
  --branch "refs/heads/$TARGET_BRANCH" \
  --repo "$REPO" \
  --channel "<CHANNEL_NAME>"

# 4. Subscribe to arcade updates (required for all onboarded repos)
echo ""
echo "Creating arcade subscription..."
darc add-subscription \
  --channel ".NET Eng - Latest" \
  --source-repo https://github.com/dotnet/arcade \
  --target-repo "$REPO" \
  --target-branch "$TARGET_BRANCH" \
  --update-frequency everyDay \
  --standard-automerge

# 5. Subscribe to product dependency sources
# <ADD ONE darc add-subscription BLOCK PER SOURCE REPO>

# 6. Verify
echo ""
echo "=== Subscriptions ==="
darc get-subscriptions --target-repo "$REPO"
echo ""
echo "=== Default Channels ==="
darc get-default-channels --source-repo "$REPO"
echo ""
echo "Done! Dependency flow is configured."
```

Make the script executable: `chmod +x eng/setup-darc.sh`

### Ask to run

After generating the script, ask the user: "I've created `eng/setup-darc.sh` with all darc commands for this repo. Would you like me to run it now, or will you run it after merge?"

If they choose to run now, execute: `./eng/setup-darc.sh`

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
| Official pipeline | [dotnet/aspire](https://github.com/dotnet/aspire/blob/main/eng/pipelines/azure-pipelines.yml) — 1ES template, post-build |

**Key patterns validated against real repos:**
- `VersionPrefix` is computed from `$(MajorVersion).$(MinorVersion).$(PatchVersion)` (not hardcoded)
- `StabilizePackageVersion` property exists for release cutting
- CPM (Directory.Packages.props) is compatible with arcade (aspire uses it)
- Package source mapping prevents NU1507 with CPM + multiple feeds

## Build Verification

**IMPORTANT:** Always verify the Arcade build works locally before committing or pushing. This catches issues like missing workloads, duplicate assembly attributes, stale obj folders, and WiX toolset problems early.

### Steps

1. **Clean stale artifacts** — critical if the repo was previously built without Arcade or with a different configuration:
   ```bash
   git clean -xdf artifacts/
   # Also clean obj/bin in project dirs if they exist outside artifacts/
   find . -type d \( -name "obj" -o -name "bin" \) -not -path "./eng/*" -not -path "./.dotnet/*" | xargs rm -rf
   ```

2. **Install required workloads** — if projects target platform-specific TFMs (e.g. `net10.0-android`, `net10.0-ios`):
   ```bash
   .dotnet/dotnet workload restore
   ```
   Note: The `.dotnet/` SDK is installed automatically by the build script on first run.

3. **Run the Arcade build** with restore + build + pack:
   ```bash
   ./eng/common/build.sh --restore --build --pack \
     --configuration Release --prepareMachine \
     --projects /absolute/path/to/Solution.slnf
   ```
   On Windows:
   ```cmd
   eng\common\build.cmd -restore -build -pack ^
     -configuration Release -prepareMachine ^
     -projects C:\full\path\to\Solution.slnf
   ```

   **Key notes:**
   - You MUST pass `--restore --build` explicitly — without these flags, `build.sh` does nothing
   - The `--projects` path MUST be absolute — Arcade's `Build.proj` resolves it from a different working directory, so relative paths fail
   - If the repo has a solution filter (`.slnf`) that excludes sample/playground projects, prefer it to avoid workload issues
   - Add `-bl` to produce a binary log (`artifacts/log/Release/Build.binlog`) for debugging

4. **Verify outputs:**
   ```bash
   ls artifacts/packages/Release/Shipping/
   ```
   You should see `.nupkg` files for all projects with `<IsPackable>true</IsPackable>` or `<IsShipping>true</IsShipping>`.

### Common build failures

| Error | Cause | Fix |
|-------|-------|-----|
| `NETSDK1147: workloads must be installed` | Multi-targeted projects need platform workloads | Run `.dotnet/dotnet workload restore` |
| `CS0579: Duplicate attribute` | Stale `obj/` folders from prior builds | `git clean -xdf artifacts/` and clean obj dirs |
| `Toolset version has not been restored` | Arcade SDK not yet downloaded | Run with `--restore` flag |
| `The project file was not found` | Relative path to `--projects` | Use absolute path |
| WiX/signing errors | Arcade SDK 10+ WiX bug | Add MakeDir workaround (see Known Issues) |

## Known Issues & Workarounds

### WiX 5 toolset unconditionally required (dotnet/arcade#16611)

**Affects:** Arcade SDK 10.0.0-beta and later (any repo not producing MSI/WiX installers)

**Problem:** `Sign.proj` and `Tools.proj` unconditionally reference both WiX 3 (`Microsoft.Signed.Wix`) and WiX 5 (`Microsoft.WixToolset.Sdk`) packages. `SignToolTask` validates that both `Wix3ToolsPath` and `WixToolsPath` directories exist, erroring if they're missing — even for repos that produce no MSI/wixpack artifacts. Additionally, `Sign.proj` constructs `WixToolsPath` as `tools/net472/$(Platform)` (e.g. `tools/net472/x64`), but the WiX 5 SDK package has **no platform subdirectory** under `tools/net472/`.

**Workaround:** Add a target in `Directory.Build.targets` that creates the missing platform subdirectories during the build phase (before `Sign.proj` runs):

```xml
<!-- Workaround for dotnet/arcade#16611 -->
<Target Name="CreateWixToolsPathWorkaround"
        BeforeTargets="Build"
        Condition="Exists('$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)')">
  <MakeDir Directories="$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\x64"
           Condition="!Exists('$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\x64')" />
  <MakeDir Directories="$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\arm64"
           Condition="!Exists('$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\arm64')" />
</Target>
```

**Why `PackageDownload` doesn't work:** Downloads to the NuGet global cache, but `Sign.proj` looks in the repo-local `.packages/` folder (note: `$(RepoRoot)` includes a trailing backslash, so `$(RepoRoot).packages` correctly resolves to `<repo>\.packages`). And the `tools/net472/x64` subdirectory doesn't exist in the package regardless.

**Verified:** dnceng/internal build [2930786](https://dev.azure.com/dnceng/internal/_build/results?buildId=2930786) (dotnet/maui-labs). Remove once upstream is fixed.

**Tracking:** https://github.com/dotnet/arcade/issues/16611

### Service connections require first-time authorization

**Affects:** Any newly onboarded repo running official builds for the first time.

**Problem:** Several service connections need first-time authorization per pipeline definition. Azure DevOps **pauses the build and waits for manual approval** — appearing as if the build is "hanging". The connections that need approval are:

1. **`Darc: Maestro Production`** — used by post-build `Validate` and `publish_using_darc` stages
2. **`DevDiv-ESRP-PME-DNCENG`** — ESRP code signing service (when `enableMicrobuild: true`)
3. **`MicroBuild Signing Task (DevDiv)`** — MicroBuild signing plugin (when `enableMicrobuild: true`)

**How to resolve:** Ask in the dnceng **First Responders** Teams channel to approve the pending service connection authorizations. This is a **one-time setup** per pipeline definition — expect multiple approval rounds on the first few builds as different stages trigger different service connections.

### Real signing requires enableMicrobuild

**Affects:** Any repo using `DotNetSignType=Real` (or `real`) for code signing.

**Problem:** `enableMicrobuild` defaults to `false` in Arcade's `job.yml` template. Without it, the MicroBuild Signing Plugin is never installed. `SignToolTask` submits signing requests but nothing processes them → files remain unsigned → verification fails with "PE file is not signed properly".

**Fix:** Add `enableMicrobuild: true` to the jobs template parameters:

```yaml
- template: /eng/common/templates-official/jobs/jobs.yml@self
  parameters:
    enableMicrobuild: true
    enablePublishBuildAssets: true
    # ...
```

Also ensure `eng/Signing.props` maps third-party DLLs to `3PartySHA2` certificate and first-party DLLs use the default .NET certificate (`UseDotNetCertificate: true`).

### NuGet.org publishing with 1ES Pipeline Templates

**Pattern:** For publishing NuGet packages to NuGet.org from dnceng official builds, use the `1ES.PublishNuget@1` task (not `DotNetCoreCLI@2` or `NuGetCommand@2`).

Key requirements:
- `settings.networkIsolationPolicy: Permissive` at the 1ES template level (do NOT use `Permissive,CFSClean` — it blocks NuGet.org)
- `templateContext.type: releaseJob` with `isProduction: true` on the publish job
- `useDotNetTask: false` (DotNetCoreCLI@2 doesn't support encrypted API keys)
- `nuGetFeedType: external` with a `publishFeedCredentials` service connection (naming convention: `NuGet.org - dotnet/{repo}`)

Reference implementation: [dotnet/aspire release-publish-nuget.yml](https://github.com/dotnet/aspire/blob/main/eng/pipelines/release-publish-nuget.yml). See [references/pipeline-templates.md](references/pipeline-templates.md#nugetorg-publishing-with-1espublishnuget1) for the full template.
