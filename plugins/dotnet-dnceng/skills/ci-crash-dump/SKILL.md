---
name: ci-crash-dump
description: >
  Download and debug crash dumps from CI test failures in dotnet repositories.
  Use when a CI test crashed (not just failed), when the user wants to debug a crash dump
  from a PR or build, or when asked "debug dump", "download dump", "crash dump from CI",
  "test crashed", "analyze crash in PR", or "why did the test crash".
  DO NOT USE FOR: test failures that are not crashes (use ci-analysis),
  build failures, performance analysis, or analyzing dumps you already have locally.
---

# CI Crash Dump Analysis

Dotnet repositories run tests on a distributed test infrastructure called Helix. When a test
process crashes, Helix captures a dump file and publishes it as an artifact. This skill
covers finding those artifacts, downloading them, and analyzing the dump.

## When to Use

- A CI test crashed (not just failed with assertion errors)
- User wants to debug a dump from a PR or build

## When Not to Use

- Test failed but didn't crash (normal assertion failure) — use `ci-analysis`
- User already has a dump file locally
- Build failures (no test execution occurred)

## Step 1: Identify the Crashed Work Item

Use the ci-analysis script to find failing Helix jobs from a PR number or build ID:
```
./scripts/Get-CIStatus.ps1 -PRNumber <PR> -Repository "dotnet/runtime" -ShowLogs
./scripts/Get-CIStatus.ps1 -BuildId <BuildId> -ShowLogs
```

A crash shows as "Work item X in job Y has failed" (entire work item). Individual test name
failures indicate assertion failures, not crashes.

## Step 2: Query the Work Item for Crash Evidence

Query the Helix API for work item details:
```
GET https://helix.dot.net/api/2019-06-17/jobs/{jobId}/workitems/{workItemName}
```

The response includes `ExitCode` and a `Files` array (each with `FileName` and `Uri`).

**Crash vs. normal failure:** Crashes have a negative or large `ExitCode` and `.dmp` files
in the `Files` array. Normal failures have `ExitCode: 1` and no dump files.

Common crash exit codes:

| Exit code | Meaning | Platform |
|-----------|---------|----------|
| `-1073740771` (`0xC000041D`) | Process abort | Windows |
| `-1073741819` (`0xC0000005`) | Access violation | Windows |
| `-532462766` (`0xE0434352`) | CLR unhandled exception | Windows |
| `134` (128+6) | SIGABRT | Linux/macOS |
| `139` (128+11) | SIGSEGV | Linux/macOS |

## Step 3: Download Artifacts

Download all files from the `Files` array. Each entry has a `Uri` to a blob.

Alternatively, [runfo](https://github.com/jaredpar/runfo) downloads the full payload
including runtime binaries: `runfo get-helix-payload -j <jobId> -w <workItem> -o <dir>`.

> **Internal Helix jobs** (identified by the org `dnceng` rather than `dnceng-public` in URLs,
> or when the Helix API returns 401/403) require authentication that the agent does not have.
> Report the job ID and work item name to the user and ask them to download manually.

Extract any ZIP files in the downloaded payload.

## Step 4: Debug the Dump

The dump needs matching runtime binaries (DAC, SOS) from the payload at
`shared/Microsoft.NETCore.App/<version>/`.

Determine the dump's platform from the CI job name (e.g., "windows-x64", "linux-arm64").

### OS compatibility

`dotnet-dump` can analyze managed state cross-platform. Native debuggers require a matching OS.

| Dump OS | Agent on Windows | Agent on Linux | Agent on macOS |
|---------|-----------------|----------------|----------------|
| Windows | ✅ `dotnet-dump`, `cdb` | ⚠️ `dotnet-dump` managed-only | ⚠️ `dotnet-dump` managed-only |
| Linux | ⚠️ `dotnet-dump` managed-only (needs Cross DAC binaries — `CoreCLRCrossDacArtifacts` artifact from the same AzDO build, copied into the runtime dir) | ✅ `dotnet-dump`, `lldb` | ⚠️ `dotnet-dump` managed-only |
| macOS | ❌ Report dump location only | ❌ Report dump location only | ✅ `lldb` |

If the agent cannot fully analyze the dump (OS mismatch), report the crash type, exit code,
dump file path, and runtime binaries path, and suggest the user debug manually.

### Managed crashes

Use `dotnet-dump analyze`. The critical Helix-specific setup:
- `setclrpath` — point to the runtime binaries from the payload
- `setsymbolserver -directory` — same path, for symbols

Start with `pe` (print exception) and `clrstack -all`. See [SOS command reference](https://learn.microsoft.com/dotnet/core/diagnostics/sos-debugging-extension) for further commands.

### Native crashes on Windows

Use `cdb.exe` (command-line debugger from Debugging Tools for Windows, install via
`winget install --id Microsoft.WinDbg`, located at
`C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe`).

Key commands: `!analyze -v` (automatic crash analysis), `kP` / `~*kP` (native stacks).
For mixed native+managed: `.loadby sos coreclr`, then `!setclrpath`, `!pe`, `!clrstack`.

### Native crashes on Linux/macOS

Use `lldb`. Point it at the dump, the dotnet host binary from the payload, and use
`setclrpath` / `setsymbolserver` as with dotnet-dump. Key commands: `bt all`, `pe`, `clrstack -all`.

Setup: [LLDB for .NET](https://github.com/dotnet/diagnostics/blob/main/documentation/lldb/linux-instructions.md).

### NativeAOT crashes

SOS does not work with NativeAOT. Use `cdb` or `lldb` directly.

## Common Pitfalls

- **Helix artifacts expire after ~30 days.** Download promptly.
- **`dotnet-dump` only handles managed state.** For native crashes, use `cdb`/`lldb` on matching OS.
- **32-bit dumps on 64-bit OS:** Use 32-bit dotnet SDK to install dotnet-dump.
- **Mobile/WASM dumps** are not covered — report the dump location and hand off.
- **Internal jobs** (`dnceng` org) require auth the agent doesn't have — report and hand off.

## Further Reading

- [dotnet-dump](https://learn.microsoft.com/dotnet/core/diagnostics/dotnet-dump)
- [SOS debugging extension](https://learn.microsoft.com/dotnet/core/diagnostics/sos-debugging-extension)
- [Debugging .NET core dumps](https://github.com/dotnet/diagnostics/blob/main/documentation/debugging-coredump.md)
