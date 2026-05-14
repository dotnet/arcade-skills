# Arcade File Templates

Templates for all files that must be created or modified when onboarding a repository to Arcade.

## Table of Contents

- [global.json](#globaljson)
- [Directory.Build.props](#directorybuildprops)
- [Directory.Build.targets](#directorybuildtargets)
- [eng/Versions.props](#engversionsprops)
- [eng/Version.Details.xml](#engversiondetailsxml)
- [NuGet.config](#nugetconfig)
- [eng/Publishing.props](#engpublishingprops)
- [eng/Signing.props](#engsigningprops)
- [eng/SignCheckExclusionsFile.txt](#engsigncheckexclusionsfiletxt)
- [es-metadata.yml](#es-metadatayml)

## global.json

The `global.json` must reference the Arcade SDK and optionally the Helix SDK. Use the latest stable Arcade SDK version from the `.NET Eng - Latest` channel.

```json
{
  "tools": {
    "dotnet": "9.0.100"
  },
  "msbuild-sdks": {
    "Microsoft.DotNet.Arcade.Sdk": "<ARCADE_SDK_VERSION>"
  }
}
```

If using Helix for testing, also add:
```json
{
  "msbuild-sdks": {
    "Microsoft.DotNet.Arcade.Sdk": "<ARCADE_SDK_VERSION>",
    "Microsoft.DotNet.Helix.Sdk": "<HELIX_SDK_VERSION>"
  }
}
```

If the repository needs a specific SDK version with rollForward:
```json
{
  "sdk": {
    "version": "9.0.100",
    "rollForward": "latestFeature"
  },
  "tools": {
    "dotnet": "9.0.100"
  },
  "msbuild-sdks": {
    "Microsoft.DotNet.Arcade.Sdk": "<ARCADE_SDK_VERSION>"
  }
}
```

## Directory.Build.props

Minimal template — adjust `<PackageLicenseExpression>`, `<PackageProjectUrl>`, `<RepositoryUrl>` and `<IsShipping>` per repo.

```xml
<Project>

  <Import Project="Sdk.props" Sdk="Microsoft.DotNet.Arcade.Sdk" />

  <PropertyGroup>
    <Copyright>$(CopyrightNetFoundation)</Copyright>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>
    <PackageProjectUrl>https://github.com/OWNER/REPO</PackageProjectUrl>
    <RepositoryUrl>https://github.com/OWNER/REPO</RepositoryUrl>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <DebugType>embedded</DebugType>
    <DebugSymbols>true</DebugSymbols>
    <LangVersion>latest</LangVersion>
    <!-- Set to true for packages that ship publicly on NuGet.org -->
    <IsShipping>true</IsShipping>
  </PropertyGroup>

</Project>
```

**Key notes:**
- `<IsShipping>true</IsShipping>` for packages that ship publicly; `false` for internal/tooling packages.
- Use `$(CopyrightNetFoundation)` for .NET Foundation repos, or set a custom copyright.
- If the repo existed before and already has a `Directory.Build.props`, merge the Arcade import at the top and add only the missing properties.

## Directory.Build.targets

Minimal template:

```xml
<Project>

  <Import Project="Sdk.targets" Sdk="Microsoft.DotNet.Arcade.Sdk" />

  <!-- Workaround for dotnet/arcade#16611: WiX 5 tools path missing platform subdirectories.
       Remove once the upstream fix is available. -->
  <Target Name="CreateWixToolsPathWorkaround"
          BeforeTargets="Build"
          Condition="Exists('$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)')">
    <MakeDir Directories="$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\x64"
             Condition="!Exists('$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\x64')" />
    <MakeDir Directories="$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\arm64"
             Condition="!Exists('$(RepoRoot).packages\microsoft.wixtoolset.sdk\$(MicrosoftWixToolsetSdkVersion)\tools\net472\arm64')" />
  </Target>

</Project>
```

If the repo already has a `Directory.Build.targets`, add the Arcade SDK import at the top.

**WiX workaround:** The `CreateWixToolsPathWorkaround` target is only needed with Arcade SDK 10+. It creates missing `tools/net472/x64` and `arm64` subdirectories that `Sign.proj` expects but the WiX 5 package doesn't ship. Note: `$(RepoRoot)` includes a trailing backslash, so `$(RepoRoot).packages` correctly resolves to the repo-local `.packages` folder. See [dotnet/arcade#16611](https://github.com/dotnet/arcade/issues/16611). Remove once the upstream fix is available.

## eng/Versions.props

Controls versioning and lists all NuGet dependency versions. The naming convention for version properties is `<PackageNameWithDotsRemoved>Version` or `<PackageNameWithDotsKept>PackageVersion`.

```xml
<Project>

  <PropertyGroup>
    <!-- Product version (both runtime and aspire use the computed pattern) -->
    <MajorVersion>1</MajorVersion>
    <MinorVersion>0</MinorVersion>
    <PatchVersion>0</PatchVersion>
    <VersionPrefix>$(MajorVersion).$(MinorVersion).$(PatchVersion)</VersionPrefix>
    <PreReleaseVersionLabel>preview</PreReleaseVersionLabel>
    <PreReleaseVersionIteration>1</PreReleaseVersionIteration>
    <!-- Set to true when stabilizing a release (removes prerelease label) -->
    <StabilizePackageVersion>false</StabilizePackageVersion>

    <!-- Arcade features (set to true to enable) -->
    <!-- <UsingToolXliff>false</UsingToolXliff> -->
  </PropertyGroup>

  <PropertyGroup>
    <!-- Dependencies managed by darc/maestro -->
    <!-- Package versions listed here match entries in Version.Details.xml -->
  </PropertyGroup>

  <PropertyGroup>
    <!-- Additional pinned dependencies (not flowing via maestro) -->
  </PropertyGroup>

</Project>
```

**Versioning properties:**
- `MajorVersion`, `MinorVersion`, `PatchVersion`: individual components, `VersionPrefix` computed from them. This is the pattern used by runtime, aspire, and other arcade repos.
- `PreReleaseVersionLabel`: label like `alpha`, `beta`, `preview`, `rc`. Empty for release-only packages.
- `PreReleaseVersionIteration`: numeric iteration that controls the prerelease version segment. When set to `1`, packages version as `{VersionPrefix}-{Label}.1.{build_number}` (e.g. `1.0.0-preview.1.26080.3`). Bump this for each preview release cycle: `preview.1`, `preview.2`, etc. Without it, versions are `{VersionPrefix}-{Label}.{build_number}` (e.g. `1.0.0-preview.26080.3`). **Recommended:** always set this property — it gives clearer version ordering and is the pattern used by dotnet/maui, dotnet/aspire, and dotnet/runtime.
- `StabilizePackageVersion`: set to `true` when cutting a release to drop the prerelease label

**Version property naming convention:**
For a package `Microsoft.Extensions.Logging`, the version property is:
`<MicrosoftExtensionsLoggingVersion>9.0.0</MicrosoftExtensionsLoggingVersion>`

This property is then referenced in csproj files:
```xml
<PackageReference Include="Microsoft.Extensions.Logging" Version="$(MicrosoftExtensionsLoggingVersion)" />
```

## eng/Version.Details.xml

Tracks all dependencies with source repo and SHA for darc/maestro dependency flow.

```xml
<?xml version="1.0" encoding="utf-8"?>
<Dependencies>
  <ProductDependencies>
    <!-- Product dependencies: packages that become part of the shipped product -->
    <!-- Example:
    <Dependency Name="Microsoft.Extensions.Logging" Version="9.0.0">
      <Uri>https://github.com/dotnet/runtime</Uri>
      <Sha>COMMIT_SHA_HERE</Sha>
    </Dependency>
    -->
  </ProductDependencies>
  <ToolsetDependencies>
    <!-- Toolset dependencies: packages used to build but not shipped -->
    <Dependency Name="Microsoft.DotNet.Arcade.Sdk" Version="ARCADE_SDK_VERSION">
      <Uri>https://github.com/dotnet/dotnet</Uri>
      <Sha>ARCADE_SHA_HERE</Sha>
    </Dependency>
  </ToolsetDependencies>
</Dependencies>
```

**Dependency types:**
- `ProductDependencies`: Packages that become part of the shipped product output.
- `ToolsetDependencies`: Packages used to build the product (compilers, SDKs, build tools).

**Each `<Dependency>` element:**
- `Name`: Package name (must match the version property name pattern in Versions.props)
- `Version`: Current version consumed
- `Pinned="true"`: Prevents automatic updates by maestro
- `<Uri>`: Source repository URL
- `<Sha>`: Git commit SHA that produced this version

**Important — Arcade SDK URI:**
- For .NET 9+ channels (`.NET 10.0.1xx SDK`, etc.) → use `https://github.com/dotnet/dotnet` (VMR)
- For `.NET Eng - Latest` channel → use `https://github.com/dotnet/arcade`

The Arcade SDK is built from the VMR for release channels. Using the wrong URI means `darc update-dependencies` won't find matching builds.

## NuGet.config

Must include the Arcade/dnceng feeds. Clear existing sources to ensure deterministic restore.

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <solution>
    <add key="disableSourceControlIntegration" value="true" />
  </solution>
  <packageSources>
    <clear />
    <add key="dotnet-public" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-public/nuget/v3/index.json" />
    <add key="dotnet-tools" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-tools/nuget/v3/index.json" />
    <add key="dotnet-eng" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-eng/nuget/v3/index.json" />
    <add key="dotnet10" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet10/nuget/v3/index.json" />
  </packageSources>
  <disabledPackageSources>
    <clear />
  </disabledPackageSources>
</configuration>
```

**⚠️ Do NOT include nuget.org:** Official builds at dnceng/internal use CFS (Container Fencing Service) which enforces Microsoft package feed security policies. Having `nuget.org` as a direct feed source triggers `NuGet Security Analysis` errors: *"NuGet package configuration file does not comply with Microsoft package feed security policies"*. The `dotnet-public` feed already mirrors all public NuGet.org packages — use it instead. See https://aka.ms/cfs/nuget for details.

**Notes:**
- Replace `dotnet10` with the feed matching your target .NET version (e.g. `dotnet9`, `dotnet11`). Check runtime and aspire for current feed names.
- For transport packages, add `dotnet10-transport` if needed: `https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet10-transport/nuget/v3/index.json`
- **Do not add nuget.org** — the `dotnet-public` feed mirrors all public NuGet.org packages and is required for CFS compliance in official builds.
- If existing NuGet.config exists, **merge** the feeds rather than replacing.

### Package Source Mapping — CAUTION

⚠️ **Do NOT add `<packageSourceMapping>` for repos with official builds.** During official builds, `eng/common/SetupNugetSources.ps1` dynamically injects internal authenticated feeds (e.g. `darc-int-dotnet-arcade`) that are not listed in NuGet.config. These feeds won't be covered by the mapping, causing **NU1507 warnings** on every project.

**Instead:** Suppress NU1507 in `Directory.Build.props`:
```xml
<NoWarn>$(NoWarn);NU1507</NoWarn>
```

Package source mapping only works for repos that exclusively use public CI (no official builds at dnceng/internal).

## eng/Publishing.props

Required for V3 publishing. Minimal template:

```xml
<Project>
  <PropertyGroup>
    <PublishingVersion>3</PublishingVersion>
  </PropertyGroup>
</Project>
```

For repos that produce shipping assets (.NET release), add:

```xml
<Project>
  <PropertyGroup>
    <PublishingVersion>3</PublishingVersion>
    <!-- Set to true for .NET release-tracked repos (like runtime, aspire) -->
    <!-- <ProducesDotNetReleaseShippingAssets>true</ProducesDotNetReleaseShippingAssets> -->
    <!-- Set to false if symbol packages are generated separately or not needed -->
    <!-- <AutoGenerateSymbolPackages>false</AutoGenerateSymbolPackages> -->
  </PropertyGroup>
</Project>
```

## eng/Signing.props

Controls MicroBuild/ESRP code signing during official builds. Maps assemblies and file types to signing certificates.

```xml
<Project>
  <!--
    Signing configuration for ESRP/MicroBuild package signing.
    Maps assemblies and file types to their signing certificates.

    Certificate types:
    - UseDotNetCertificate: Default Microsoft .NET certificate for first-party assemblies
    - 3PartySHA2: For redistributed third-party assemblies
    - NuGet: For NuGet package signing (.nupkg files)
    - None: For files that should not be signed
  -->
  <PropertyGroup>
    <UseDotNetCertificate>true</UseDotNetCertificate>
  </PropertyGroup>

  <!-- Third-party assemblies that ship inside our NuGet packages -->
  <ItemGroup Label="Third Party Assemblies">
    <!-- Add one entry per third-party DLL bundled in your packages.
         To find these, build locally and inspect nupkg contents:
         unzip -l artifacts/packages/Release/Shipping/*.nupkg | grep "\.dll$" -->
    <!-- <FileSignInfo Include="ThirdParty.dll" CertificateName="3PartySHA2" /> -->
  </ItemGroup>

  <!-- File extension signing rules -->
  <ItemGroup>
    <!-- NuGet packages are signed with NuGet certificate -->
    <FileExtensionSignInfo Update=".nupkg" CertificateName="NuGet" />
    <!-- JS files don't need code signing — they are static web assets -->
    <FileExtensionSignInfo Update=".js" CertificateName="None" />
  </ItemGroup>
</Project>
```

**How to populate third-party assemblies:**
1. Build locally: `./eng/common/build.sh --restore --build --pack --configuration Release`
2. List DLLs in each nupkg: `for f in artifacts/packages/Release/Shipping/*.nupkg; do echo "=== $(basename $f) ==="; unzip -l "$f" | grep "\.dll$" | awk '{print $NF}'; done`
3. Cross-reference with your repo's projects — any DLL not from your source is third-party
4. Add a `<FileSignInfo Include="Name.dll" CertificateName="3PartySHA2" />` for each

## eng/SignCheckExclusionsFile.txt

Exclusions for post-build SignCheck validation. This is **separate** from `Signing.props` — it controls what the post-build `Signing Validation` stage skips when verifying signatures.

```
;; Exclusions for SignCheck. Corresponds to info in Signing.props.
;; Format: https://github.com/dotnet/arcade/blob/397316e195639450b6c76bfeb9823b40bee72d6d/src/SignCheck/Microsoft.SignCheck/Verification/Exclusion.cs#L23-L35
*.js;; We do not sign JavaScript files.
```

**Format:** Each line is a glob pattern followed by `;;` and a comment. Common exclusions:
- `*.js` — JavaScript files (Blazor static web assets, embedded scripts)

**Important:** This file must be consistent with `Signing.props`. If you set `CertificateName="None"` for `.js` in `Signing.props`, you must also exclude `*.js` in `SignCheckExclusionsFile.txt`. Otherwise the post-build validation will flag those files as unsigned.

**Reference:** Pattern from [dotnet/Scaffolding](https://github.com/dotnet/Scaffolding/blob/main/eng/SignCheckExclusionsFile.txt).

## es-metadata.yml

1ES Inventory-as-Code metadata file. Required for all repos in the 1ES ecosystem. This file maps the repository to a Service Tree entry for compliance, telemetry, and issue routing.

**Documentation:** [1ES Inventory as Code](https://eng.ms/docs/coreai/devdiv/one-engineering-system-1es/1es-docs/product-catalog/inventory-as-code/about) (Microsoft internal)

### Template

```yaml
schemaVersion: 0.0.1
isProduction: <IS_PRODUCTION>
accountableOwners:
  service: <SERVICE_TREE_ID>
routing:
  defaultAreaPath:
    org: <AZDO_ORG>
    path: <AZDO_AREA_PATH>
```

### Field descriptions

| Field | Description | Example |
|-------|-------------|---------|
| `schemaVersion` | Always `0.0.1` (current schema version) | `0.0.1` |
| `isProduction` | Whether this is a production service/component. Map from `IsShipping`: if `IsShipping=true` → `isProduction: true` | `true` |
| `accountableOwners.service` | Service Tree UUID. Find at https://servicetree.msft.ms/ (Microsoft internal) | `9d770e15-6208-4284-b347-b2762803623b` |
| `routing.defaultAreaPath.org` | Azure DevOps organization for bug routing (`devdiv` or `dnceng`) | `devdiv` |
| `routing.defaultAreaPath.path` | Azure DevOps area path for bug routing | `DevDiv\.NET MAUI` |

### IsShipping → isProduction mapping

- `IsShipping=true` (packages published to NuGet.org) → `isProduction: true`
- `IsShipping=false` (internal/dev-only) → `isProduction: false`

### Reference examples

**dotnet/maui** (production, devdiv):
```yaml
schemaVersion: 0.0.1
isProduction: true
accountableOwners:
  service: 9d770e15-6208-4284-b347-b2762803623b
routing:
  defaultAreaPath:
    org: devdiv
    path: DevDiv\.NET MAUI
```

**dotnet/aspire** (production, devdiv):
```yaml
schemaVersion: 0.0.1
isProduction: true
accountableOwners:
  service: 6e21af9f-054b-4ed9-a856-e34c73d843d1
routing:
  defaultAreaPath:
    org: devdiv
    path: DevDiv\ASP.NET Core
```

**dotnet/runtime** (production, devdiv):
```yaml
schemaVersion: 0.0.1
isProduction: true
accountableOwners:
  service: 1dc8dedc-8f5f-4b94-b182-ec3bdfb207b0
routing:
  defaultAreaPath:
    org: devdiv
    path: DevDiv\NET Runtime
```

**dotnet/arcade** (production, dnceng):
```yaml
schemaVersion: 0.0.1
isProduction: true
accountableOwners:
  service: b3bbd815-183a-4142-8056-3a676d687f71
routing:
  defaultAreaPath:
    org: dnceng
    path: internal\Dotnet-Core-Engineering
```

### Placeholder handling

If the user doesn't know their Service Tree ID or area path, generate the file with placeholders and add a TODO comment:

```yaml
# TODO: Replace placeholders with actual values
# Service Tree: https://servicetree.msft.ms/ (Microsoft internal)
# 1ES docs: https://eng.ms/docs/coreai/devdiv/one-engineering-system-1es/1es-docs/product-catalog/inventory-as-code/about (Microsoft internal)
schemaVersion: 0.0.1
isProduction: true
accountableOwners:
  service: <SERVICE_TREE_ID>
routing:
  defaultAreaPath:
    org: <AZDO_ORG>
    path: <AZDO_AREA_PATH>
```
