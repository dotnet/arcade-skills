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

4. **eng/Versions.props** — set `VersionPrefix`, `PreReleaseVersionLabel`, and all dependency version properties. Migrate versions from any existing `Directory.Packages.props` or centralized version file.

5. **eng/Version.Details.xml** — create with Arcade SDK dependency entry at minimum. Add entries for all dependencies that will flow via maestro (see Step 6).

6. **NuGet.config** — add required dnceng feeds. If file exists, merge feeds. Keep existing feeds the repo needs (e.g. nuget.org for third-party packages).

7. **eng/Publishing.props** — create with `<PublishingVersion>3</PublishingVersion>`.

### Important rules:
- **Never delete** existing content from files — always merge
- If repo uses `Directory.Packages.props` (Central Package Management), migrate version properties to `eng/Versions.props` and update PackageReference elements to use `$(VersionPropertyName)` pattern
- Ensure all `.sh` files have executable permissions: `git add --chmod=+x *.sh`

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

## Step 8: Summary and Next Steps

After all files are created/modified, provide the user with:

1. **List of files created/modified** with a brief description of each change
2. **Dependency flow setup commands** — darc commands to run:
   ```bash
   # Install darc
   ./eng/common/darc-init.sh  # or .\eng\common\darc-init.ps1

   # Authenticate
   darc authenticate

   # Subscribe to Arcade updates
   darc add-subscription --channel ".NET Eng - Latest" \
     --source-repo https://github.com/dotnet/arcade \
     --target-repo https://github.com/OWNER/REPO \
     --target-branch main \
     --update-frequency everyDay \
     --standard-automerge

   # Set default channel for your repo's builds
   darc add-default-channel --branch refs/heads/main \
     --repo https://github.com/OWNER/REPO \
     --channel "<appropriate channel>"
   ```
3. **Azure DevOps pipeline setup** — instructions to create pipeline definitions in dnceng-public and/or dnceng/internal
4. **Build verification** — run `./eng/common/cibuild.sh --configuration Release --prepareMachine` to verify the setup works
5. **Remaining manual steps** — GitHub app installation (dotnet-maestro), service connections, etc.
