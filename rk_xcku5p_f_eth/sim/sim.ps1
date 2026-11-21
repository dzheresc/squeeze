# Runs both testbenches with the Vivado 2024.2 simulator (xsim):
#   tb_eth   arty_a7_35t_eth's frame generator -> this project's frame receiver
#   tb_mdio  mdio_rd against a small PHY model
$ErrorActionPreference = 'Stop'
$bin = 'C:\Xilinx\Vivado\2024.2\bin'
$arty = '..\..\..\arty_a7_35t_eth\rtl'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force work | Out-Null
  Push-Location work
  & "$bin\xvlog.bat" "$arty\crc32_d8.v" "$arty\eth_tx_frame.v" ..\..\rtl\eth_rx_frame.v ..\..\rtl\mdio_rd.v ..\tb_eth.v ..\tb_mdio.v
  if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
  foreach ($tb in 'tb_eth', 'tb_mdio') {
    & "$bin\xelab.bat" -timescale 1ns/1ps -debug off $tb -s $tb
    if ($LASTEXITCODE -ne 0) { throw "xelab $tb failed" }
    & "$bin\xsim.bat" $tb -R | Select-String -Pattern 'rx done|read ad|PASS|FAIL'
  }
} finally { Pop-Location; Pop-Location }
