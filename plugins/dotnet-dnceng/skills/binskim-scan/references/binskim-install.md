s# Installing BinSkim

BinSkim is distributed as a NuGet content package, **not** a dotnet global tool. It ships pre-built binaries for Windows (x64), Linux (x64, arm64), and macOS (x64).

## Quick Check

```powershell
# Windows
Test-Path "C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe"

# Linux/macOS
test -x ~/binskim-tool/extracted/tools/net9.0/linux-x64/BinSkim
```

If it exists, you're done.

## Installation Steps

```powershell
# Works on both Windows (PowerShell) and Linux (pwsh)

# 1. Find latest version
$versions = Invoke-RestMethod "https://api.nuget.org/v3-flatcontainer/microsoft.codeanalysis.binskim/index.json"
$latest = $versions.versions[-1]
Write-Host "Latest: $latest"

# 2. Download .nupkg
$url = "https://api.nuget.org/v3-flatcontainer/microsoft.codeanalysis.binskim/$latest/microsoft.codeanalysis.binskim.$latest.nupkg"

# Windows
$outDir = "C:\git\binskim-tool"
# Linux/macOS
# $outDir = "$HOME/binskim-tool"

New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Invoke-WebRequest -Uri $url -OutFile "$outDir/binskim.nupkg"

# 3. Extract (nupkg is a zip)
Expand-Archive -Path "$outDir/binskim.nupkg" -DestinationPath "$outDir/extracted" -Force

# 4. Verify — pick the right platform binary
$exe = Get-ChildItem "$outDir/extracted/tools" -Recurse -Filter "BinSkim*" |
    Where-Object { $_.Name -match '^BinSkim(\.exe)?$' } | Select-Object -First 1
Write-Host "BinSkim at: $($exe.FullName)"
```

### Platform-specific paths inside the package

```
tools/net9.0/win-x64/BinSkim.exe       # Windows
tools/net9.0/linux-x64/BinSkim         # Linux x64
tools/net9.0/linux-arm64/BinSkim       # Linux arm64
tools/net9.0/osx-x64/BinSkim           # macOS
```

On Linux/macOS, make the binary executable after extraction:
```bash
chmod +x ~/binskim-tool/extracted/tools/net9.0/linux-x64/BinSkim
```

## Upgrading

Delete `C:\git\binskim-tool\extracted\` and re-run the installation steps. The NuGet flat container API always returns the latest version list.

## Troubleshooting

- **"Cannot find BinSkim.exe"**: The path structure changed between major versions. Search recursively: `Get-ChildItem -Recurse -Filter BinSkim.exe`
- **"dotnet tool install" doesn't work**: BinSkim is NOT published as a dotnet tool. It's a NuGet content package with pre-built executables.
- **.NET runtime version mismatch**: BinSkim targets net9.0. If you only have net8.0, look for a `netcoreapp3.1` or `net8.0` folder in `tools/` — older versions ship multiple TFMs.
