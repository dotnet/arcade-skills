# Build Prerequisites

BinSkim scans compiled binaries, so you must build (and often pack) the repo first. Requirements depend on what the repo contains.

## Managed-Only (.NET)

Most dotnet repos need only the .NET SDK. The repo's `global.json` pins the SDK version and `build.cmd`/`build.sh` will auto-acquire it via the arcade bootstrap.

```powershell
# Windows
build.cmd -c Release
build.cmd -c Release -pack

# Linux/macOS
./build.sh -c Release
./build.sh -c Release -pack
```

## Native Code (C/C++)

Repos with native components (machinelearning, runtime, aspnetcore, diagnostics) need:

**Windows:**
- **MSVC compiler** (`cl.exe`) — from Visual Studio
- **CMake** — for project generation
- **Spectre-mitigated libraries** — required by most dotnet native projects (VS individual component: "MSVC vXXX Spectre-mitigated Libs")

**Linux:**
- **gcc or clang** — typically available via system package manager
- **CMake** — `apt install cmake` or equivalent
- No Spectre-mitigated library requirement on Linux

### Finding Visual Studio

```powershell
# Standard
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath

# Including preview/canary
& "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -prerelease -latest -property installationPath
```

### Setting Up the Environment

```powershell
# Initialize MSVC environment (adjust path for your VS version)
cmd /c "`"<VS-path>\VC\Auxiliary\Build\vcvarsall.bat`" amd64 && <build-command>"
```

### If Native Build Fails

You can still scan:
1. **Managed outputs** — build without native: `build.cmd -c Release` (native projects may error but managed will succeed)
2. **Pre-built native blobs from NuGet cache** — many repos consume pre-built native libraries via NuGet packages:
   ```powershell
   # Find native DLLs in NuGet cache for a specific package
   Get-ChildItem "$env:USERPROFILE\.nuget\packages\<package-name>" -Recurse -Filter "*.dll" |
     Where-Object { $_.DirectoryName -match 'native' }
   ```
3. **Isolated package restore** — get all package native blobs without building:
   ```powershell
   dotnet restore --packages .packages
   Get-ChildItem .packages -Recurse -Filter "*.dll" | Where-Object { $_.DirectoryName -match 'native' }
   ```

## Per-Repo Build Commands

| Repo | Build (Windows) | Build (Linux) | Pack |
|---|---|---|---|
| machinelearning | `build.cmd -c Release` | `./build.sh -c Release` | `-pack` flag |
| runtime | `build.cmd -subset libs -c Release` | `./build.sh -subset libs -c Release` | `-pack` flag |
| sdk | `build.cmd -c Release` | `./build.sh -c Release` | `-pack` flag |
| aspnetcore | `build.cmd -c Release` | `./build.sh -c Release` | `-pack` flag |
| roslyn | `build.cmd -c Release` | `./build.sh -c Release` | `-pack` flag |
| diagnostics | `build.cmd -c Release` | `./build.sh -c Release` | `-pack` flag |
| aspire | `build.cmd -c Release` | `./build.sh -c Release` | `-pack` flag |
| perfview | `build.cmd` (msbuild) | N/A (Windows-only) | N/A |
