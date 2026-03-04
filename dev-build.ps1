[CmdletBinding()]
param(
    [ValidateSet("check", "update", "configure", "build", "headless", "test", "scan-log")]
    [string]$Action = "check",
    [ValidateSet("2019", "2019b", "2022", "2022b", "2022pre", "2026", "2026b", "2026i")]
    [string]$Toolset = "2022b",
    [string]$BuildFlavor = "developer",
    [switch]$NoNinja,
    [string]$LogDir = ".\build-logs",
    [string]$LogPath
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSCommandPath
Set-Location $RepoRoot

function Refresh-Path {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-MakeArgs {
    param(
        [switch]$NoBuild,
        [switch]$Headless,
        [switch]$RunTests
    )
    $args = [System.Collections.Generic.List[string]]::new()
    $args.Add($Toolset)

    if ($Headless) {
        $args.Add("headless")
    }
    elseif ($BuildFlavor) {
        $args.Add($BuildFlavor)
    }

    if (-not $NoNinja.IsPresent) {
        $args.Add("ninja")
    }
    if ($NoBuild.IsPresent) {
        $args.Add("nobuild")
    }
    if ($RunTests.IsPresent) {
        $args.Add("test")
    }

    return ($args -join " ")
}

function New-LogFile {
    param([string]$Prefix)
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    return Join-Path $LogDir "$Prefix-$stamp.log"
}

function Invoke-CmdWithLog {
    param(
        [string]$CommandLine,
        [string]$OutLogPath
    )

    Write-Host ">> cmd /d /c $CommandLine"
    & cmd /d /c $CommandLine 2>&1 | Tee-Object -FilePath $OutLogPath
    $exit = $LASTEXITCODE
    if ($exit -ne 0) {
        throw "Command failed with exit code $exit. See log: $OutLogPath"
    }
    Write-Host "Log: $OutLogPath"
}

function Test-Executable {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return $null }
    return $cmd.Source
}

function Test-Prereqs {
    Refresh-Path
    $ok = $true

    Write-Host "Checking required tools..."
    $tools = @("git", "cmake", "ctest", "python", "svn", "ninja")
    foreach ($tool in $tools) {
        $resolved = Test-Executable -Name $tool
        if ($resolved) {
            Write-Host ("[OK ] {0} -> {1}" -f $tool, $resolved)
        }
        else {
            Write-Host ("[BAD] {0} not found in PATH" -f $tool)
            $ok = $false
        }
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Host "[BAD] vswhere.exe not found"
        $ok = $false
    }
    else {
        $installPath = & $vswhere -latest `
            -products Microsoft.VisualStudio.Product.BuildTools `
            -version "[17.0,17.99)" `
            -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property installationPath
        if ([string]::IsNullOrWhiteSpace($installPath)) {
            Write-Host "[BAD] VS 2022 Build Tools with VC toolset not found"
            $ok = $false
        }
        else {
            Write-Host "[OK ] VS Build Tools -> $installPath"
        }
    }

    $libPath = Join-Path $RepoRoot "lib\windows_x64"
    if (Test-Path $libPath) {
        Write-Host "[OK ] Precompiled lib folder exists -> $libPath"
    }
    else {
        Write-Host "[WARN] Precompiled lib folder missing -> $libPath"
        Write-Host "       Run: .\dev-build.ps1 -Action update"
    }

    if (-not $ok) {
        throw "Prerequisite check failed."
    }
}

function Scan-Log {
    param([string]$TargetPath)
    if (-not $TargetPath) {
        $latest = Get-ChildItem -Path $LogDir -File -Filter *.log -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $latest) {
            throw "No logs found in $LogDir."
        }
        $TargetPath = $latest.FullName
    }
    if (-not (Test-Path $TargetPath)) {
        throw "Log file not found: $TargetPath"
    }

    Write-Host "Scanning: $TargetPath"
    $pattern = "(error C\d+:|fatal error C\d+:|: error [A-Za-z0-9_]+:|CMake Error|FAILED:|ninja: build stopped|LINK : fatal error)"
    $matches = Select-String -Path $TargetPath -Pattern $pattern -CaseSensitive:$false

    if (-not $matches) {
        Write-Host "No common build failure markers found in this log."
        return
    }

    $matches | Select-Object -First 50 | ForEach-Object {
        "{0}:{1}" -f $_.LineNumber, $_.Line.Trim()
    }
}

switch ($Action) {
    "check" {
        Test-Prereqs
        Write-Host "Environment looks ready."
    }
    "update" {
        Test-Prereqs
        $log = if ($LogPath) { $LogPath } else { New-LogFile -Prefix "update" }
        $args = Get-MakeArgs
        Invoke-CmdWithLog -CommandLine ("echo y| make.bat {0} update" -f $args) -OutLogPath $log
    }
    "configure" {
        Test-Prereqs
        $log = if ($LogPath) { $LogPath } else { New-LogFile -Prefix "configure" }
        $args = Get-MakeArgs -NoBuild
        Invoke-CmdWithLog -CommandLine ("make.bat {0}" -f $args) -OutLogPath $log
    }
    "build" {
        Test-Prereqs
        $log = if ($LogPath) { $LogPath } else { New-LogFile -Prefix "build" }
        $args = Get-MakeArgs
        Invoke-CmdWithLog -CommandLine ("make.bat {0}" -f $args) -OutLogPath $log
    }
    "headless" {
        Test-Prereqs
        $log = if ($LogPath) { $LogPath } else { New-LogFile -Prefix "headless" }
        $args = Get-MakeArgs -Headless
        Invoke-CmdWithLog -CommandLine ("make.bat {0}" -f $args) -OutLogPath $log
    }
    "test" {
        Test-Prereqs
        $log = if ($LogPath) { $LogPath } else { New-LogFile -Prefix "test" }
        $args = Get-MakeArgs -RunTests
        Invoke-CmdWithLog -CommandLine ("make.bat {0}" -f $args) -OutLogPath $log
    }
    "scan-log" {
        Scan-Log -TargetPath $LogPath
    }
}
