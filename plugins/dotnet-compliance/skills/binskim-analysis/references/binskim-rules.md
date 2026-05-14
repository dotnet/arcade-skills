# BinSkim Rules by Platform

Quick-reference for all BinSkim rules, organized by binary format. Use this when investigating a specific rule ID (e.g., "what is BA2008?") or understanding which rules apply to which platforms.

## Windows PE Rules (BA2xxx)

These apply to `.dll` and `.exe` files built with MSVC or the Windows SDK.

| Rule | Name | Typical fix |
|------|------|-------------|
| BA2001 | LoadImageAboveFourGigabyteAddress | Link with `/LARGEADDRESSAWARE` |
| BA2002 | DoNotIncorporateVulnerableDependencies | Update vulnerable static libs (e.g., OpenSSL) |
| BA2004 | EnableSecureSourceCodeHashing | Compile with `/ZH:SHA_256` (MSVC 16.4+) |
| BA2005 | DoNotShipVulnerableBinaries | Update binaries with known CVEs |
| BA2006 | BuildWithSecureTools | Use a supported compiler version |
| BA2007 | EnableCriticalCompilerWarnings | Enable `/W4` or at least `/W3` |
| BA2008 | EnableControlFlowGuard | Compile with `/guard:cf`; link with `/guard:cf` |
| BA2009 | EnableAddressSpaceLayoutRandomization | Don't set `/DYNAMICBASE:NO`; use default |
| BA2010 | DoNotMarkImportsSectionAsExecutable | Remove `/SECTION` or `/MERGE` that makes imports executable |
| BA2011 | EnableStackProtection | Don't use `/GS-`; keep default `/GS` |
| BA2012 | DoNotModifyStackProtectionCookie | Remove custom `__security_cookie` symbol |
| BA2013 | InitializeStackProtection | Use default CRT entry point or call `__security_init_cookie()` |
| BA2014 | DoNotDisableStackProtectionForFunctions | Remove `__declspec(safebuffers)` |
| BA2015 | EnableHighEntropyVirtualAddresses | Don't set `/HIGHENTROPYVA:NO` |
| BA2016 | MarkImageAsNXCompatible | Don't set `/NXCOMPAT:NO` |
| BA2018 | EnableSafeSEH (x86 only) | Pass `/SAFESEH` to linker (x86 builds only) |
| BA2019 | DoNotMarkWritableSectionsAsShared | Remove shared+writable section attributes |
| BA2021 | DoNotMarkWritableSectionsAsExecutable | Don't use writable+executable sections; disable incremental linking in release |
| BA2022 | SignSecurely | Sign with SHA-256 or stronger; don't use SHA-1. **Note:** BinSkim 4.x fires `Error_DidNotVerify` with `CRYPT_E_FILE_ERROR` on **unsigned** binaries (not just SHA-1 signed). This produces thousands of raw findings. Guardian filters all of these — `CRYPT_E_FILE_ERROR` means "unsigned" not "improperly signed". |
| BA2024 | EnableSpectreMitigations | Rebuild with `/Qspectre` and Spectre-mitigated libs |
| BA2025 | EnableShadowStack (CET) | Pass `/CETCOMPAT` to linker |
| BA2026 | EnableMicrosoftCompilerSdlSwitch | Pass `/sdl` to cl.exe |
| BA2027 | EnableSourceLink | Enable SourceLink in project properties |
| BA2028 | EnableCastGuard | Pass `/guard:ehcont` to cl.exe and `/GUARD:EHCONT` to linker |
| BA2029 | EnableIntegrityCheck | Pass `/INTEGRITYCHECK` to linker (required for drivers, PPL) |

## Linux ELF Rules (BA3xxx)

These apply to `.so` shared libraries and executables built with GCC or Clang on Linux.

| Rule | Name | Typical fix |
|------|------|-------------|
| BA3001 | EnablePositionIndependentExecutable | Compile with `-fpie`; link with `-pie` |
| BA3002 | DoNotMarkStackAsExecutable | Compile/link with `-z noexecstack` |
| BA3003 | EnableStackProtector | Compile with `--fstack-protector-strong` or `-all` |
| BA3004 | GenerateRequiredSymbolFormat | Use `-gdwarf-5` for debug symbols |
| BA3005 | EnableStackClashProtection | Compile with `-fstack-clash-protection` |
| BA3006 | EnableNonExecutableStack | Compile with `-z noexecstack` |
| BA3010 | EnableReadOnlyRelocations | Link with `-Wl,-z,relro` |
| BA3011 | EnableBindNow | Link with `-Wl,-z,now` |
| BA3030 | UseGccCheckedFunctions (GCC only) | Compile with `-D_FORTIFY_SOURCE=2 -O2` |
| BA3031 | EnableClangSafeStack (Clang only) | Compile/link with `-fsanitize=safe-stack` |

## macOS Mach-O Rules (BA5xxx)

These apply to `.dylib` and executables built for macOS/iOS.

**Mach-O scanning works on any OS.** BinSkim identifies Mach-O files by magic bytes, not file extension or host OS. You can scan `.dylib` files on Windows or Linux — just ensure BinSkim's glob patterns match them (e.g., use `**` or `*.dylib`). If BinSkim appears to "skip" Mach-O files, it's because the glob pattern (e.g., `*.dll`) doesn't match `.dylib`.

| Rule | Name | Typical fix |
|------|------|-------------|
| BA5001 | EnablePositionIndependentExecutable | Compile with `-fpie` |
| BA5002 | DoNotAllowExecutableStack | Don't use `--allow_stack_execute` |
| BA3003 | EnableStackProtector | Compile with `-fstack-protector-strong` or `-fstack-protector-all` |
| BA3005 | EnableStackClashProtection | Compile with `-fstack-clash-protection` |

## Key notes

- **Not all Error-level rules are SDL-required.** Guardian filters findings based on internal SDL policy requirement mappings before reporting to the central portal. Some Error-level rules (e.g., BA2028 CastGuard) may be scoped to specific orgs and filtered out for others.
- **Which rules are required depends on your service tree registration** (`es-metadata.yml`). Different orgs have different SDL policy scopes. Always check your own portal.
- **Managed-only assemblies** (pure C#/VB) are generally **not subject** to most BA2xxx rules. BinSkim auto-skips IL-only and mixed-mode binaries as NotApplicable. BA2008 specifically **only applies to native PE binaries**.
- **BA2008 findings are almost always on third-party native binaries** consumed via NuGet (e.g., Intel MKL/oneDAL/TBB, WiX winterop.dll). These can't be fixed in your repo — the upstream vendor must recompile with `/guard:cf`.
- **BA2022 (SignSecurely) can produce thousands of raw findings** on satellite resource DLLs. These are typically all filtered by Guardian.
- **`<ControlFlowGuard>Guard</ControlFlowGuard>` only works for C++ (`.vcxproj`)** — the C# compiler has no `/guard:cf` support. This MSBuild property does nothing for managed code.
- **BA2024 (Spectre) is Warning, not Error** — fires frequently on third-party native dependencies.
- **BA4002** (ReportElfOrMachoCompilerData) is informational only — no pass/fail.
- **BA6004/BA6006** are optimization hints, not security rules.

## SDL requirement status

Which BinSkim rules are SDL-required depends on the SDL policy ([10203](https://liquid.microsoft.com/Web/Object/Read/MS.Security/Requirements/Microsoft.Security.SystemsADM.10203#Zguidance)) and how Guardian filters findings. Consult [Warning Central](https://liquid.microsoft.com/Web/Views/View/1020414) and your Guardian portal for the authoritative list for your Service Tree org.
