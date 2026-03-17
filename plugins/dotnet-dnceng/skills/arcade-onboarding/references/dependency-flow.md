# Dependency Flow with Darc and Maestro

Guide for setting up dependency flow using darc/maestro to replace pinned NuGet references with automatically-flowing versions.

## Table of Contents

- [Overview](#overview)
- [Identifying Flowable Dependencies](#identifying-flowable-dependencies)
- [Common Dotnet Source Repos](#common-dotnet-source-repos)
- [Setting Up Version.Details.xml](#setting-up-versiondetailsxml)
- [Mapping Dependencies to Versions.props](#mapping-dependencies-to-versionsprops)
- [Darc Subscriptions](#darc-subscriptions)
- [Channels Reference](#channels-reference)
- [NuGet.org Publishing](#nugetorg-publishing)

## Overview

Maestro is the .NET dependency management service. Darc is its CLI client. Together they:
1. Track which repo/SHA produced each dependency
2. Automatically create PRs to update dependency versions when upstream repos produce new builds
3. Route packages to the correct feeds based on channel assignments

A **subscription** defines: source repo + channel → target repo + branch, with merge policies.

## Identifying Flowable Dependencies

When analyzing a repository's existing NuGet dependencies, look for packages produced by dotnet/* repos. These can be converted from pinned NuGet references to darc-managed dependencies.

**Criteria for converting a dependency:**
1. Package is produced by a known dotnet/* repository
2. Package is available on a darc channel (not just NuGet.org)
3. Repository wants to track latest builds (not pinned to a stable release)

**Dependencies that should NOT be converted:**
1. Third-party packages not produced by dotnet repos (e.g. Newtonsoft.Json, Moq)
2. Packages the repo intentionally pins to a specific stable version
3. Packages from repos not participating in the arcade ecosystem

## Common Dotnet Source Repos

| Package prefix/pattern | Source repository | Channel |
|----------------------|-------------------|---------|
| Microsoft.NETCore.*, System.* | https://github.com/dotnet/runtime | .NET X Dev |
| Microsoft.AspNetCore.* | https://github.com/dotnet/aspnetcore | .NET X Dev |
| Microsoft.Extensions.* | https://github.com/dotnet/runtime | .NET X Dev |
| Microsoft.CodeAnalysis.* | https://github.com/dotnet/roslyn | .NET X Dev |
| Microsoft.DotNet.Arcade.Sdk | https://github.com/dotnet/arcade | .NET Eng - Latest |
| Microsoft.DotNet.Helix.Sdk | https://github.com/dotnet/arcade | .NET Eng - Latest |
| Microsoft.EntityFrameworkCore.* | https://github.com/dotnet/efcore | .NET X Dev |
| Microsoft.NET.Sdk | https://github.com/dotnet/sdk | .NET X Dev |

Replace `X` with the major .NET version (e.g. 9, 10).

## Setting Up Version.Details.xml

For each dependency that should flow via maestro, add an entry:

```xml
<Dependencies>
  <ProductDependencies>
    <!-- Runtime dependencies -->
    <Dependency Name="Microsoft.Extensions.Logging" Version="9.0.0">
      <Uri>https://github.com/dotnet/runtime</Uri>
      <Sha>abc123def456</Sha>
    </Dependency>
  </ProductDependencies>
  <ToolsetDependencies>
    <!-- Build toolset -->
    <Dependency Name="Microsoft.DotNet.Arcade.Sdk" Version="11.0.0-beta.26166.3">
      <Uri>https://github.com/dotnet/arcade</Uri>
      <Sha>bcbb938d7e69bdc06ee2ebb9fd8b13725aa43a2d</Sha>
    </Dependency>
  </ToolsetDependencies>
</Dependencies>
```

**To find the current SHA for a package:**
```bash
darc get-latest-build --repo https://github.com/dotnet/runtime --channel ".NET 9 Dev"
```

Or look up the package on the source repo's latest main branch commit.

## Mapping Dependencies to Versions.props

Each `<Dependency Name="X">` in Version.Details.xml must have a corresponding version property in `eng/Versions.props`.

The property name is derived from the package name by:
1. Removing dots and special characters
2. Appending `Version` or `PackageVersion`

**Examples:**
| Package Name | Version Property |
|-------------|-----------------|
| Microsoft.Extensions.Logging | `<MicrosoftExtensionsLoggingVersion>` |
| System.Text.Json | `<SystemTextJsonVersion>` |
| Microsoft.DotNet.Arcade.Sdk | (expressed in global.json msbuild-sdks) |
| Microsoft.DotNet.Helix.Sdk | (expressed in global.json msbuild-sdks) |

Then in csproj files:
```xml
<PackageReference Include="Microsoft.Extensions.Logging" Version="$(MicrosoftExtensionsLoggingVersion)" />
```

## Darc Subscriptions

### Creating an Arcade subscription (essential for all onboarded repos):

```bash
darc add-subscription \
  --channel ".NET Eng - Latest" \
  --source-repo https://github.com/dotnet/arcade \
  --target-repo https://github.com/OWNER/REPO \
  --target-branch main \
  --update-frequency everyDay \
  --standard-automerge
```

### Creating a subscription for runtime dependencies:

```bash
darc add-subscription \
  --channel ".NET 9 Dev" \
  --source-repo https://github.com/dotnet/runtime \
  --target-repo https://github.com/OWNER/REPO \
  --target-branch main \
  --update-frequency everyDay \
  --standard-automerge
```

### Setting up default channels for your repo's builds:

```bash
darc add-default-channel \
  --branch refs/heads/main \
  --repo https://github.com/OWNER/REPO \
  --channel ".NET 9 Dev"
```

### Useful darc commands:
```bash
darc get-channels                    # List available channels
darc get-subscriptions               # List all subscriptions
darc get-default-channels            # List default channel assignments
darc get-latest-build --repo <url>   # Get latest build info
darc authenticate                    # Set up authentication token
```

## Channels Reference

| Channel | Purpose |
|---------|---------|
| .NET Eng - Latest | Latest arcade/engineering tooling |
| .NET 9 Dev | .NET 9 development builds |
| .NET 10 Dev | .NET 10 development builds |
| .NET 9 Release | .NET 9 release builds |
| General Testing | For testing publishing |

## NuGet.org Publishing

To publish packages to NuGet.org, the repo must:

1. **Set `<IsShipping>true</IsShipping>`** in Directory.Build.props or per-project for packages that should publish.

2. **Set up a default channel** that routes to NuGet.org. This is configured via the channel's target feeds in Maestro. Typically, release channels publish to NuGet.org.

3. **For opting OUT of NuGet.org publishing**, set `<IsShipping>false</IsShipping>` on projects that should not publish packages externally. Internal/tooling packages should use this.

4. **Shipping vs Non-Shipping:**
   - `IsShipping=true`: Package is published to NuGet.org (or official feed) on release.
   - `IsShipping=false`: Package is only published to internal/dev feeds, never to NuGet.org.

5. **Per-project override** in individual .csproj:
   ```xml
   <PropertyGroup>
     <IsShipping>false</IsShipping>  <!-- This project's package won't go to NuGet.org -->
   </PropertyGroup>
   ```

6. **Publishing flow:** Build → Azure DevOps artifacts → Post-build validation → Maestro promotion → Target feed (based on channel).
