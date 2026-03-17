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
    <!-- Product version -->
    <VersionPrefix>1.0.0</VersionPrefix>
    <PreReleaseVersionLabel>preview</PreReleaseVersionLabel>

    <!-- Arcade features (set to true to enable) -->
    <!-- <UsingToolXliff>false</UsingToolXliff> -->
  </PropertyGroup>

  <PropertyGroup>
    <!-- Dependencies managed by darc/maestro -->
    <!-- Package versions listed here match entries in Version.Details.xml -->
  </PropertyGroup>

  <PropertyGroup>
    <!-- Additional pinned dependencies -->
  </PropertyGroup>

</Project>
```

**Versioning properties:**
- `VersionPrefix`: 3-part SemVer prefix (MAJOR.MINOR.PATCH)
- `PreReleaseVersionLabel`: label like `alpha`, `beta`, `preview`, `rc`. Empty for release-only packages.
- `PreReleaseVersionIteration`: optional numeric iteration (e.g. `1` for `preview.1`)

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
    <add key="dotnet9" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet9/nuget/v3/index.json" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
  </packageSources>
  <disabledPackageSources>
    <clear />
  </disabledPackageSources>
</configuration>
```

**Notes:**
- Replace `dotnet9` with latest .NET version feed (e.g. `dotnet10`, `dotnet11`).
- Keep `nuget.org` if the repo has non-dotnet dependencies.
- Add `<packageSourceMapping>` if needed for security.
- If existing NuGet.config exists, **merge** the feeds rather than replacing.

## eng/Publishing.props

Required for V3 publishing:

```xml
<Project>
  <PropertyGroup>
    <PublishingVersion>3</PublishingVersion>
  </PropertyGroup>
</Project>
```
