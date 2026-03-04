# Local Blender Build Helper

This repo now includes `dev-build.ps1` to make setup/build/debug easier on Windows.

## Quick start

From `D:\B\blender`:

```powershell
.\dev-build.ps1 -Action check
.\dev-build.ps1 -Action update
.\dev-build.ps1 -Action configure
.\dev-build.ps1 -Action build
```

## Common commands

```powershell
# Build with Visual Studio Build Tools 2022 + Ninja (default)
.\dev-build.ps1 -Action build

# Configure only (no compile)
.\dev-build.ps1 -Action configure

# Headless target
.\dev-build.ps1 -Action headless

# Scan latest log for build errors
.\dev-build.ps1 -Action scan-log

# Scan a specific log file
.\dev-build.ps1 -Action scan-log -LogPath .\build-logs\build-20260302-123456.log
```

## Notes

- Default toolset is `2022b` (Visual Studio 2022 Build Tools).
- Logs are written to `.\build-logs\`.
- You can switch toolset, for example:

```powershell
.\dev-build.ps1 -Action build -Toolset 2022
```
