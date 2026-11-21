# Runs tb_top with the Vivado 2024.2 simulator (xsim): the whole starter design at a scaled
# clock, with the UNISIM SYSMONE4 model and a UART receiver checking the heartbeat lines.
$ErrorActionPreference = 'Stop'
$bin = 'C:\Xilinx\Vivado\2024.2\bin'
$glbl = 'C:\Xilinx\Vivado\2024.2\data\verilog\src\glbl.v'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force work | Out-Null
  Push-Location work
  # SYSMONE4 analog stimulus: 45.0 C throughout
  Set-Content -Encoding ascii design.txt "TIME TEMP VCCINT VCCAUX VCCBRAM`n00000 45.0 0.85 1.8 0.85`n"
  & "$bin\xvlog.bat" ..\..\rtl\uart_tx.v ..\..\rtl\sysmon_temp.v ..\..\rtl\top.v ..\tb_top.v $glbl
  if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
  & "$bin\xelab.bat" -timescale 1ns/1ps -debug off -L unisims_ver tb_top glbl -s tb_top
  if ($LASTEXITCODE -ne 0) { throw 'xelab tb_top failed' }
  & "$bin\xsim.bat" tb_top -R | Select-String -Pattern 'uart:|PASS|FAIL|ERROR|Error'
} finally { Pop-Location; Pop-Location }
