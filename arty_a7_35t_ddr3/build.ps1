# Generate the MIG (first time only), then synthesize + implement + write bitstream with Vivado 2024.2.
$ErrorActionPreference = 'Stop'
$vivado = 'C:\Xilinx\Vivado\2024.2\bin\vivado.bat'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force build | Out-Null
  if (-not (Test-Path ip\mig_ddr3\mig_ddr3.xci)) {
    & $vivado -mode batch -nojournal -log build\gen_ip.log -source gen_ip.tcl
    if ($LASTEXITCODE -ne 0) { throw "MIG generation failed ($LASTEXITCODE), see build\gen_ip.log" }
  }
  & $vivado -mode batch -nojournal -log build\build.log -source build.tcl
  if ($LASTEXITCODE -ne 0) { throw "vivado build failed ($LASTEXITCODE), see build\build.log" }
} finally { Pop-Location }
