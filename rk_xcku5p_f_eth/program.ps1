# Load build\top.bit over the board's USB JTAG (volatile; lost on power cycle).
param([string]$Url = 'localhost:3121')
$ErrorActionPreference = 'Stop'
$vivado = 'C:\Xilinx\Vivado\2024.2\bin\vivado.bat'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force build | Out-Null
  & $vivado -mode batch -nojournal -log build\program.log -source program.tcl -tclargs $Url
  if ($LASTEXITCODE -ne 0) { throw "vivado program failed ($LASTEXITCODE), see build\program.log" }
} finally { Pop-Location }
