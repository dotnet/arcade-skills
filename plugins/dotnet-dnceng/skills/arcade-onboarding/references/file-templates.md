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

</Project>
```

If the repo already has a `Directory.Build.targets`, add the Arcade SDK import at the top.

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
    <!-- <PreReleaseVersionIteration>1</PreReleaseVersionIteration> -->
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
- `PreReleaseVersionIteration`: optional numeric iteration (e.g. `1` for `preview.1`)
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
      <Uri>https://github.com/dotnet/arcade</Uri>
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
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <disabledPackageSources>
    <clear />
  </disabledPackageSources>
</configuration>
```

**Notes:**
- Replace `dotnet10` with the feed matching your target .NET version (e.g. `dotnet9`, `dotnet11`). Check runtime and aspire for current feed names.
- For transport packages, add `dotnet10-transport` if needed: `https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet10-transport/nuget/v3/index.json`
- Keep `nuget.org` if the repo has non-dotnet third-party dependencies.
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
