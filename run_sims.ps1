# Runs every project's simulation (<project>\sim\sim.ps1) with the Vivado 2024.2 simulator and
# prints one PASS / FAIL line per project. No hardware needed.
#   .\run_sims.ps1                    all projects that have a sim folder
#   .\run_sims.ps1 arty_a7_35t ...    only these folders
# A project passes when its output has a PASS line and no FAIL or ERROR line. The full output of
# each run is kept in <project>\sim\work\sim.out.
param([string[]]$Projects)
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
  if (-not $Projects) {
    $Projects = Get-ChildItem -Directory | Where-Object { Test-Path "$($_.Name)\sim\sim.ps1" } |
      ForEach-Object Name
  }
  $rows = @()
  foreach ($p in $Projects) {
    $t0 = Get-Date
    Write-Host "=== $p"
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File ".\$p\sim\sim.ps1" 2>&1 | Out-String -Width 400
    New-Item -ItemType Directory -Force "$p\sim\work" | Out-Null
    $out | Set-Content -Encoding utf8 "$p\sim\work\sim.out"
    $pass = @([regex]::Matches($out, '(?m)^\s*PASS\s*$')).Count
    $fail = [regex]::IsMatch($out, '(?m)FAIL|^ERROR|Error:')
    $result = if ($pass -gt 0 -and -not $fail) { 'PASS' } else { 'FAIL' }
    if ($result -eq 'FAIL') {
      $out -split "`n" | Where-Object { $_ -match 'FAIL|ERROR|Error' } | Select-Object -First 10 |
        ForEach-Object { Write-Host "  $_" }
    }
    $rows += [pscustomobject]@{
      Project = $p
      Result  = $result
      Benches = $pass
      Seconds = [math]::Round(((Get-Date) - $t0).TotalSeconds)
    }
  }
  $rows | Format-Table -AutoSize | Out-String | Write-Host
  if ($rows | Where-Object Result -ne 'PASS') { exit 1 }
} finally { Pop-Location }
