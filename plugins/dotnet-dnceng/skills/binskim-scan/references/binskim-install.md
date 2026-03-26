# Installing BinSkim

BinSkim is distributed as a NuGet content package, **not** a dotnet global tool.

## Quick Check

```powershell
# Check if already installed
Test-Path "C:\git\binskim-tool\extracted\tools\net9.0\win-x64\BinSkim.exe"
```

If it exists, you're done.

## Installation Steps

```powershell
# 1. Find latest version
$versions = Invoke-RestMethod "https://api.nuget.org/v3-flatcontainer/microsoft.codeanalysis.binskim/index.json"
$latest = $versions.versions[-1]
Write-Host "Latest: $latest"

# 2. Download .nupkg
$url = "https://api.nuget.org/v3-flatcontainer/microsoft.codeanalysis.binskim/$latest/microsoft.codeanalysis.binskim.$latest.nupkg"
$outDir = "C:\git\binskim-tool"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Invoke-WebRequest -Uri $url -OutFile "$outDir\binskim.nupkg"

# 3. Extract (nupkg is a zip)
Expand-Archive -Path "$outDir\binskim.nupkg" -DestinationPath "$outDir\extracted" -Force

# 4. Verify
$exe = Get-ChildItem "$outDir\extracted\tools" -Recurse -Filter "BinSkim.exe" | Select-Object -First 1
Write-Host "BinSkim at: $($exe.FullName)"
& $exe.FullName version
```

The executable is typically at `tools/net9.0/win-x64/BinSkim.exe` inside the extracted package.

## Upgrading

Delete `C:\git\binskim-tool\extracted\` and re-run the installation steps. The NuGet flat container API always returns the latest version list.

## Troubleshooting

- **"Cannot find BinSkim.exe"**: The path structure changed between major versions. Search recursively: `Get-ChildItem -Recurse -Filter BinSkim.exe`
- **"dotnet tool install" doesn't work**: BinSkim is NOT published as a dotnet tool. It's a NuGet content package with pre-built executables.
- **.NET runtime version mismatch**: BinSkim targets net9.0. If you only have net8.0, look for a `netcoreapp3.1` or `net8.0` folder in `tools/` — older versions ship multiple TFMs.
