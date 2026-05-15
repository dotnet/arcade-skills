# Build Verification & Known Issues

## Build Verification

**IMPORTANT:** Always verify the Arcade build works locally before committing or pushing. This catches issues like missing workloads, duplicate assembly attributes, stale obj folders, and WiX toolset problems early.

### Steps

1. **Clean stale artifacts** — critical if the repo was previously built without Arcade or with a different configuration:
   ```bash
   git clean -xdf artifacts/
   # Also clean obj/bin in project dirs if they exist outside artifacts/
   find . -type d \( -name "obj" -o -name "bin" \) -not -path "./eng/*" -not -path "./.dotnet/*" -print0 | xargs -0 rm -rf
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
   You should see `.nupkg` files for all projects with `<IsPackable>true</IsPackable>`.

   **⚠️ IsPackable must be explicit:** Even if a project has `<PackageId>` set, Arcade requires `<IsPackable>true</IsPackable>` to generate packages. Having `PackageId` alone is **not sufficient**.

### Common build failures

| Error | Cause | Fix |
|-------|-------|-----|
| `NETSDK1147: workloads must be installed` | Multi-targeted projects need platform workloads | Run `.dotnet/dotnet workload restore` |
| `CS0579: Duplicate attribute` | Stale `obj/` folders from prior builds | `git clean -xdf artifacts/` and clean obj dirs |
| `Toolset version has not been restored` | Arcade SDK not yet downloaded | Run with `--restore` flag |
| `The project file was not found` | Relative path to `--projects` | Use absolute path |
| WiX/signing errors | Arcade SDK 10+ WiX bug | Add MakeDir workaround (see Known Issues) |
| `manifest.spdx.json not found` | SBOM missing in NuGet publish stage | Add PrepareArtifacts job (see Known Issues) |
| `License file content doesn't match` | LICENSE file has extra headers or wrong format | Remove extra content; must match Arcade's MIT template (see Step 1) |
| `SIGN004: Signing 3rd party library` | `AssemblyCopyright` contains non-Microsoft entity (e.g. `Xamarin Inc.`) | Update to Microsoft copyright (see Step 1) |
| No packages in `artifacts/packages/Release/Shipping/` | Missing `IsPackable=true`, or .sln maps Release→Debug | Add `<IsPackable>true</IsPackable>` to csproj; fix .sln config mapping (see Step 1) |
| `Not found PathtoPublish: artifacts/log` | macOS job using `build.sh` without `--ci` flag | Add `--ci` to `build.sh` invocation (see Step 4) |
| `NuGet Security Analysis found ... do not comply` | `nuget.org` listed as direct feed in NuGet.config | Remove `nuget.org`; use `dotnet-public` feed instead (mirrors nuget.org). See https://aka.ms/cfs/nuget |

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

**SBOM requirement (critical):** The `releaseJob` type triggers an SBOM validator that expects `_manifest/spdx_2.2/manifest.spdx.json` alongside the packages. Since `PackageArtifacts` is published by Arcade (not through 1ES `templateContext.outputs`), no SBOM is generated. **You must add a `PrepareArtifacts` job** that downloads the artifact and re-publishes it through `templateContext.outputs` — this generates the SBOM. The `PublishNuGet` job then consumes the SBOM-annotated artifact. Without this, the build fails with `manifest.spdx.json not found`.

Reference implementation: [dotnet/aspire release-publish-nuget.yml](https://github.com/dotnet/aspire/blob/main/eng/pipelines/release-publish-nuget.yml). See [pipeline-templates.md](pipeline-templates.md#nugetorg-publishing-with-1espublishnuget1) for the full template.
