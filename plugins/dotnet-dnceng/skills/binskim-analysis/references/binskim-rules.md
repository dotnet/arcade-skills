# BinSkim Rules by Platform

Quick-reference for all BinSkim rules, organized by binary format. Use this when investigating a specific rule ID (e.g., "what is BA2008?") or understanding which rules apply to which platforms.

## Windows PE Rules (BA2xxx)

These apply to `.dll` and `.exe` files built with MSVC or the Windows SDK.

| Rule | Name | Severity | Typical fix |
|------|------|----------|-------------|
| BA2001 | LoadImageAboveFourGigabyteAddress | Error | Link with `/LARGEADDRESSAWARE` |
| BA2002 | DoNotIncorporateVulnerableDependencies | Error | Update vulnerable static libs (e.g., OpenSSL) |
| BA2004 | EnableSecureSourceCodeHashing | Error | Compile with `/ZH:SHA_256` (MSVC 16.4+) |
| BA2005 | DoNotShipVulnerableBinaries | Error | Update binaries with known CVEs |
| BA2006 | BuildWithSecureTools | Error | Use a supported compiler version |
| BA2007 | EnableCriticalCompilerWarnings | Error | Enable `/W4` or at least `/W3` |
| BA2008 | EnableControlFlowGuard | Error | Compile with `/guard:cf`; link with `/guard:cf` |
| BA2009 | EnableAddressSpaceLayoutRandomization | Error | Don't set `/DYNAMICBASE:NO`; use default |
| BA2010 | DoNotMarkImportsSectionAsExecutable | Error | Remove `/SECTION` or `/MERGE` that makes imports executable |
| BA2011 | EnableStackProtection | Error | Don't use `/GS-`; keep default `/GS` |
| BA2012 | DoNotModifyStackProtectionCookie | Error | Remove custom `__security_cookie` symbol |
| BA2013 | InitializeStackProtection | Error | Use default CRT entry point or call `__security_init_cookie()` |
| BA2014 | DoNotDisableStackProtectionForFunctions | Error | Remove `__declspec(safebuffers)` |
| BA2015 | EnableHighEntropyVirtualAddresses | Error | Don't set `/HIGHENTROPYVA:NO` |
| BA2016 | MarkImageAsNXCompatible | Error | Don't set `/NXCOMPAT:NO` |
| BA2018 | EnableSafeSEH (x86 only) | Error | Pass `/SAFESEH` to linker (x86 builds only) |
| BA2019 | DoNotMarkWritableSectionsAsShared | Error | Remove shared+writable section attributes |
| BA2021 | DoNotMarkWritableSectionsAsExecutable | Error | Don't use writable+executable sections; disable incremental linking in release |
| BA2022 | SignSecurely | Error | Sign with SHA-256 or stronger; don't use SHA-1 |
| BA2024 | EnableSpectreMitigations | **Warning** | Rebuild with `/Qspectre` and Spectre-mitigated libs |
| BA2025 | EnableShadowStack (CET) | **Warning** | Pass `/CETCOMPAT` to linker |
| BA2026 | EnableMicrosoftCompilerSdlSwitch | **Warning** | Pass `/sdl` to cl.exe |
| BA2027 | EnableSourceLink | **Warning** | Enable SourceLink in project properties |
| BA2028 | EnableCastGuard | Error | Pass `/guard:ehcont` to cl.exe and `/GUARD:EHCONT` to linker. May be scoped to specific orgs per SDL policy. |
| BA2029 | EnableIntegrityCheck | Error | Pass `/INTEGRITYCHECK` to linker (required for drivers, PPL) |

## Linux ELF Rules (BA3xxx)

These apply to `.so` shared libraries and executables built with GCC or Clang on Linux.

| Rule | Name | Severity | Typical fix |
|------|------|----------|-------------|
| BA3001 | EnablePositionIndependentExecutable | Error | Compile with `-fpie`; link with `-pie` |
| BA3002 | DoNotMarkStackAsExecutable | Error | Compile/link with `-z noexecstack` |
| BA3003 | EnableStackProtector | Error | Compile with `--fstack-protector-strong` or `-all` |
| BA3004 | GenerateRequiredSymbolFormat | Error | Use `-gdwarf-5` for debug symbols |
| BA3005 | EnableStackClashProtection | Error | Compile with `-fstack-clash-protection` |
| BA3006 | EnableNonExecutableStack | Error | Compile with `-z noexecstack` |
| BA3010 | EnableReadOnlyRelocations | Error | Link with `-Wl,-z,relro` |
| BA3011 | EnableBindNow | Error | Link with `-Wl,-z,now` |
| BA3030 | UseGccCheckedFunctions (GCC only) | Error | Compile with `-D_FORTIFY_SOURCE=2 -O2` |
| BA3031 | EnableClangSafeStack (Clang only) | Error | Compile/link with `-fsanitize=safe-stack` |

## macOS Mach-O Rules (BA5xxx)

These apply to `.dylib` and executables built for macOS/iOS.

| Rule | Name | Severity | Typical fix |
|------|------|----------|-------------|
| BA5001 | EnablePositionIndependentExecutable | Error | Compile with `-fpie` |
| BA5002 | DoNotAllowExecutableStack | Error | Don't use `--allow_stack_execute` |

## Key notes

- **Not all Error-level rules are SDL-required.** Guardian filters findings based on internal SDL policy requirement mappings before reporting to the central portal. Some Error-level rules (e.g., BA2028 CastGuard) may be scoped to specific orgs and filtered out for others.
- **Which rules are required depends on your service tree registration** (`es-metadata.yml`). Different orgs have different SDL policy scopes. Always check your own portal.
- **Managed-only assemblies** (pure C#/VB) are generally **not subject** to most BA2xxx rules. BinSkim auto-skips IL-only and mixed-mode binaries as NotApplicable. BA2008 specifically **only applies to native PE binaries**.
- **BA2008 findings are almost always on third-party native binaries** consumed via NuGet (e.g., Intel MKL/oneDAL/TBB, WiX winterop.dll). These can't be fixed in your repo — the upstream vendor must recompile with `/guard:cf`.
- **BA2022 (SignSecurely) can produce thousands of raw findings** on satellite resource DLLs. These are typically all filtered by Guardian.
- **`<ControlFlowGuard>Guard</ControlFlowGuard>` only works for C++ (`.vcxproj`)** — the C# compiler has no `/guard:cf` support. This MSBuild property does nothing for managed code.
- **BA2024 (Spectre) is Warning, not Error** — fires frequently on third-party native dependencies.
- **Cross-platform repos** shipping both Windows and Linux binaries need to pass **both** BA2xxx and BA3xxx rules.
- **BA4002** (ReportElfOrMachoCompilerData) is informational only — no pass/fail.
- **BA6004/BA6006** are optimization hints, not security rules.

## Observed portal requirements by service tree org

Which BinSkim rules actually appear in the portal depends on the `es-metadata.yml` service tree registration (`routing.defaultAreaPath.org` field). Based on empirical observation:

| Rule | Description | devdiv org (most dotnet/*) | nettel org (microsoft/perfview) |
|------|-------------|----------------------------|---------------------------------|
| BA2004 | EnableSecureSourceCodeHashing | filtered | required |
| BA2008 | EnableControlFlowGuard | required | ? |
| BA2009 | EnableAddressSpaceLayoutRandomization | required | ? |
| BA2021 | DoNotMarkWritableSectionsAsExecutable | required | ? |
| BA2027 | EnableSourceLink | filtered | required |
| BA2022 | SignSecurely | filtered | ? |
| BA2024 | EnableSpectreMitigations | filtered | ? |
| BA2025 | EnableShadowStack (CET) | filtered | ? |
| BA2026 | EnableMicrosoftCompilerSdlSwitch | filtered | ? |
| BA2028 | EnableCastGuard | filtered | ? |

> This table is **observational** — derived from comparing raw `binskim.sarif` vs `Results.sarif` across repos. "filtered" means confirmed absent from portal despite raw findings existing. "?" means untested. Always verify against your own portal.
