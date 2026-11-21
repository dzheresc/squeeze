# Runs tb_top with the Vivado 2024.2 simulator (xsim): the whole starter design at a scaled
# clock, with a UART receiver checking the heartbeat lines.
$ErrorActionPreference = 'Stop'
$bin = 'C:\Xilinx\Vivado\2024.2\bin'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force work | Out-Null
  Push-Location work
  & "$bin\xvlog.bat" ..\..\rtl\uart_tx.v ..\..\rtl\top.v ..\tb_top.v
  if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
  & "$bin\xelab.bat" -timescale 1ns/1ps -debug off tb_top -s tb_top
  if ($LASTEXITCODE -ne 0) { throw 'xelab tb_top failed' }
  & "$bin\xsim.bat" tb_top -R | Select-String -Pattern 'uart:|PASS|FAIL|ERROR'
} finally { Pop-Location; Pop-Location }
