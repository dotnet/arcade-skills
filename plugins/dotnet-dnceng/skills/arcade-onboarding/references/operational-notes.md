# Arcade Onboarding Operational Notes

These notes cover repository-analysis and rollout failures that are not adequately captured by stable public templates. Apply them conditionally; they are not defaults for every repository.

## Repository analysis

### Partial onboarding

Treat the repository as partially onboarded if any Arcade artifacts already exist. Determine which Arcade generation they came from before adding missing files. Preserve working imports, central package management, package source mapping, and CI entry points.

### Release configuration

Inspect solution configuration mappings when Release builds produce no packages. A project can be mapped from `Release|Any CPU` to `Debug|Any CPU` inside the solution even when the command line requests Release.

### Packaging

Confirm expected packages rather than inferring them from `PackageId`. Projects that should produce packages need the packaging properties required by their SDK and Arcade version, commonly an explicit `IsPackable`.

### Repository validation

Arcade repository validation may compare license content and generated assembly metadata against repository policy. If validation fails:

- inspect the current Arcade validation source and expected license template;
- check custom `AssemblyInfo` files and `GenerateAssemblyInfo`;
- preserve the repository's actual legal owner rather than replacing copyright text mechanically; and
- involve the repository owner when a legal or ownership value is unclear.

## Coherent Arcade dependencies

Use darc or another current Arcade-supported flow to select a coherent Arcade SDK, SHA, and `eng/common`. Avoid combining a copied `eng/common` from one commit with an unrelated Arcade SDK package.

For product-band SDK channels, Arcade may be produced from the VMR (`dotnet/dotnet`) rather than directly from `dotnet/arcade`. Resolve the dependency URI from current BAR/darc data. Do not assume one URI for every channel.

The Arcade SDK and .NET SDK often have a major-version compatibility relationship. If MSBuild tasks fail to load framework assemblies, verify that pairing before adding package workarounds.

For new repositories, check the current darc guidance for `eng/Version.Details.props`; do not assume the older pattern of placing every dependency version directly in `eng/Versions.props`.

## Package sources and CFS

Official builds may enforce Container Fencing Service package-source policy.

- Do not add direct `nuget.org` access to an official-build `NuGet.config` when the organization requires an approved mirror such as `dotnet-public`.
- Do not remove a repository's package source mapping without understanding why it exists.
- Official build setup can inject authenticated sources dynamically. Ensure source mapping accounts for that behavior.
- Do not suppress `NU1507` globally as a default. First confirm the warning is caused by approved dynamically injected sources and follow current repository or internal guidance.

CFS behavior and approved feeds are policy-controlled. Verify them using current internal documentation before finalizing an official pipeline.

## Signing rollout

For repositories that require real signing:

1. configure signing using current Arcade signing documentation;
2. inspect produced packages to identify first-party, third-party, and intentionally unsigned files;
3. keep signing rules and post-build validation exclusions consistent;
4. start with test signing to validate the pipeline shape; and
5. switch to real signing only after service connections and certificate mappings are approved.

New pipeline definitions may pause for first-use authorization of signing, publishing, or Maestro service connections. Report those approvals as manual work.

If a package contains a DLL the repository did not build, do not automatically assign a certificate. Establish its provenance and follow current signing policy.

## 1ES inventory metadata

`es-metadata.yml` is organization-owned inventory data. Ask for authoritative values.

A typical shape is:

```yaml
schemaVersion: 0.0.1
isProduction: true
accountableOwners:
  service: <SERVICE_TREE_ID>
routing:
  defaultAreaPath:
    org: <AZDO_ORG>
    path: <AZDO_AREA_PATH>
```

Do not infer `isProduction` solely from `IsShipping`. Shipping is a useful signal, but the accountable owner determines whether the component is production inventory.

Do not present placeholders as completed onboarding. If the user chooses to check in placeholders temporarily, leave an explicit blocker in the final report.

## NuGet.org release publishing

MicroBuild signing and CFS policy can prevent a signed official-build job from reaching NuGet.org. Some repositories solve this with a separate release pipeline that consumes already signed artifacts.

1ES release jobs may also require an SBOM associated with the published artifact. Artifacts emitted outside the template's declared outputs can miss that association.

Do not copy an old full release pipeline. Verify the current internal 1ES release-job and SBOM requirements, then compare with a currently working repository using the same organization and release process.

## WiX signing workaround

[dotnet/arcade#16611](https://github.com/dotnet/arcade/issues/16611) tracks a WiX tools-path issue observed during signing.

Before adding a workaround:

1. verify the issue is still open;
2. confirm the failure matches the missing WiX platform-directory symptom;
3. inspect the affected Arcade package layout; and
4. scope the workaround to the affected versions and signing builds.

Do not add the workaround to every onboarded repository preemptively. Remove it after consuming an Arcade version containing the upstream fix.

## Build entry points and logs

`cibuild.sh` and `cibuild.cmd` normally add CI behavior and the standard action flags. A custom `build.sh` or `build.cmd` invocation may need the CI flag when later pipeline steps publish binary logs.

If a pipeline reports a missing log artifact, compare the custom invocation with the checked-in `cibuild` wrapper before changing artifact publication.
