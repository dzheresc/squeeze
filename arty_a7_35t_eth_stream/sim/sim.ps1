# Runs tb_top with the Vivado 2024.2 simulator (xsim): the whole stream sender (MMCM, clock
# crossings, MDIO, UART) at scaled rates, with an MII frame decoder and a UART receiver.
$ErrorActionPreference = 'Stop'
$bin = 'C:\Xilinx\Vivado\2024.2\bin'
$glbl = 'C:\Xilinx\Vivado\2024.2\data\verilog\src\glbl.v'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force work | Out-Null
  Push-Location work
  & "$bin\xvlog.bat" ..\..\rtl\crc32_d8.v ..\..\rtl\eth_tx_frame.v ..\..\rtl\mdio_rd.v ..\..\rtl\uart_tx.v ..\..\rtl\top.v ..\tb_top.v $glbl
  if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
  & "$bin\xelab.bat" -timescale 1ns/1ps -debug off -L unisims_ver tb_top glbl -s tb_top
  if ($LASTEXITCODE -ne 0) { throw 'xelab tb_top failed' }
  & "$bin\xsim.bat" tb_top -R | Select-String -Pattern 'uart:|frame|SW=|PASS|FAIL|ERROR|Error'
} finally { Pop-Location; Pop-Location }
