# Builds every board project with Vivado 2024.2, one after another, and prints a summary:
# result, WNS / WHS, LUT / FF / BRAM use and the number of critical warnings.
#   .\build_all.ps1                    all projects
#   .\build_all.ps1 arty_a7_35t ...    only these folders
# Each project's own build.ps1 does the work; its outputs stay in <project>\build\.
# The summary is also written to build\summary.md (git-ignored).
param([string[]]$Projects)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
  if (-not $Projects) {
    $Projects = Get-ChildItem -Directory | Where-Object { Test-Path "$($_.Name)\build.ps1" } |
      ForEach-Object Name
  }
  function Get-UtilCount([string]$Rpt, [string[]]$Names) {
    if (-not (Test-Path $Rpt)) { return '' }
    foreach ($n in $Names) {
      $m = Select-String -Path $Rpt -Pattern "^\|\s*$n\s*\|\s*([\d.]+)\s*\|" | Select-Object -First 1
      if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return ''
  }
  $rows = @()
  foreach ($p in $Projects) {
    $t0 = Get-Date
    Write-Host "=== $p"
    $ok = $true
    try { & ".\$p\build.ps1" } catch { $ok = $false; Write-Host "  $_" }
    $mins = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)
    $log = "$p\build\build.log"
    $wns = ''; $whs = ''; $crit = ''
    if (Test-Path $log) {
      $m = Select-String -Path $log -Pattern 'BUILD DONE\s+WNS\s+(\S+)\s+WHS\s+(\S+)' | Select-Object -Last 1
      if ($m) { $wns = $m.Matches[0].Groups[1].Value; $whs = $m.Matches[0].Groups[2].Value }
      $crit = @(Select-String -Path $log -Pattern '^CRITICAL WARNING').Count
    }
    $util = "$p\build\util.rpt"
    $rows += [pscustomobject]@{
      Project = $p
      Result  = if ($ok -and $wns -ne '' -and [double]$wns -ge 0 -and [double]$whs -ge 0) { 'PASS' } else { 'FAIL' }
      WNS     = $wns
      WHS     = $whs
      LUT     = Get-UtilCount $util 'CLB LUTs', 'Slice LUTs'
      FF      = Get-UtilCount $util 'CLB Registers', 'Slice Registers'
      BRAM    = Get-UtilCount $util 'Block RAM Tile'
      Crit    = $crit
      Minutes = $mins
    }
  }
  $rows | Format-Table -AutoSize | Out-String | Write-Host
  New-Item -ItemType Directory -Force build | Out-Null
  $md = @('| Project | Result | WNS ns | WHS ns | LUT | FF | BRAM | Crit. warnings | Minutes |',
          '|---|---|---|---|---|---|---|---|---|')
  $md += $rows | ForEach-Object {
    "| $($_.Project) | $($_.Result) | $($_.WNS) | $($_.WHS) | $($_.LUT) | $($_.FF) | $($_.BRAM) | $($_.Crit) | $($_.Minutes) |"
  }
  $md | Set-Content -Encoding utf8 build\summary.md
  if ($rows | Where-Object Result -ne 'PASS') { exit 1 }
} finally { Pop-Location }
