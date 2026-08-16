<#
.SYNOPSIS
    Installs the "cca" command onto your user PATH.

.DESCRIPTION
    Creates a small cca.cmd shim in a per-user install folder that always calls this
    repo's cca.ps1 directly (via its full path, resolved from wherever this
    install.ps1 itself lives), so editing cca.ps1 takes effect immediately without
    reinstalling. Adds that install folder to your User PATH environment variable if
    it isn't already there.

    A bare .ps1 file can't be run by typing its name alone - Windows PATHEXT doesn't
    include .PS1 by design, so an arbitrary script can't be run just by typing a word
    that happens to match a filename. The .cmd shim works around that: .CMD *is* in
    PATHEXT, so typing "cca" from PowerShell, cmd.exe, or the Win+R box all resolve to
    it, which then launches PowerShell against cca.ps1 with -ExecutionPolicy Bypass
    (bypassing execution policy for that one launch only - this does not change any
    system-wide policy).

.PARAMETER InstallDir
    Where to put the cca.cmd shim. Defaults to "$env:LOCALAPPDATA\cca".

.EXAMPLE
    .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'cca')
)

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'cca.ps1'
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "cca.ps1 not found next to install.ps1 (expected at '$scriptPath')."
}

if (-not (Test-Path -LiteralPath $InstallDir)) {
    [System.IO.Directory]::CreateDirectory($InstallDir) | Out-Null
}

$shimPath = Join-Path $InstallDir 'cca.cmd'
$shimContent = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" %*`r`n"
Set-Content -LiteralPath $shimPath -Value $shimContent -Encoding ASCII -NoNewline
Write-Host "Wrote shim: $shimPath"
Write-Host "  -> always calls: $scriptPath"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathEntries = @(($userPath -split ';') | Where-Object { $_ })
if ($pathEntries -notcontains $InstallDir) {
    $newUserPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    Write-Host "Added '$InstallDir' to your User PATH."
}
else {
    Write-Host "'$InstallDir' is already on your User PATH."
}

# Make it usable immediately in this session too, without waiting for a new terminal.
if (($env:Path -split ';') -notcontains $InstallDir) {
    $env:Path = "$env:Path;$InstallDir"
}

Write-Host ""
Write-Host "Done. Try: cca -Path .\Scan -WhatIf"
Write-Host "(Already-open terminals other than this one need to be restarted to see the PATH change.)"
