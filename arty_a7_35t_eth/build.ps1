# Synthesize + implement + write bitstream with Vivado 2024.2.
$ErrorActionPreference = 'Stop'
$vivado = 'C:\Xilinx\Vivado\2024.2\bin\vivado.bat'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force build | Out-Null
  & $vivado -mode batch -nojournal -log build\build.log -source build.tcl
  if ($LASTEXITCODE -ne 0) { throw "vivado build failed ($LASTEXITCODE), see build\build.log" }
} finally { Pop-Location }
