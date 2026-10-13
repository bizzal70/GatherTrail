<#
.SYNOPSIS
  Links this project into a WoW client's Interface\AddOns folder as "GatherTrail"
  using a directory junction, so edits here are live in game after /reload.

.EXAMPLE
  .\tools\Link-Addon.ps1
  .\tools\Link-Addon.ps1 -Remove
#>
param(
    [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft",
    [string]$Flavor = "_classic_beta_",
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

$from = Split-Path $PSScriptRoot -Parent
$addons = Join-Path (Join-Path $WowRoot $Flavor) "Interface\AddOns"
$to = Join-Path $addons "GatherTrail"

if (-not (Test-Path $addons)) {
    throw "AddOns folder not found: $addons"
}

$existing = Get-Item $to -Force -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.LinkType -ne "Junction") {
        throw "$to exists and is a real folder, not a junction. Left untouched."
    }
    # Removes only the junction, never the files it points to.
    [System.IO.Directory]::Delete($to)
    if ($Remove) { Write-Host "Unlinked GatherTrail" }
}

if (-not $Remove) {
    New-Item -ItemType Junction -Path $to -Target $from | Out-Null
    Write-Host "Linked GatherTrail -> $to"
}
