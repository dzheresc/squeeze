# Runs both testbenches with the Vivado 2024.2 simulator (xsim):
#   tb_ring  arty_a7_35t_eth_stream's frame generator -> this project's receiver, FIFO and DDR4
#            ring writer -> a simple MIG model
#   tb_mdio  mdio_rw write and read framing
$ErrorActionPreference = 'Stop'
$bin = 'C:\Xilinx\Vivado\2024.2\bin'
$arty = '..\..\..\arty_a7_35t_eth_stream\rtl'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force work | Out-Null
  Push-Location work
  & "$bin\xvlog.bat" "$arty\crc32_d8.v" "$arty\eth_tx_frame.v" ..\..\rtl\eth_rx_frame.v ..\..\rtl\async_fifo.v ..\..\rtl\ddr_ring.v ..\..\rtl\mdio_rw.v ..\tb_ring.v ..\tb_mdio.v
  if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
  foreach ($tb in 'tb_ring', 'tb_mdio') {
    & "$bin\xelab.bat" -timescale 1ns/1ps -debug off $tb -s $tb
    if ($LASTEXITCODE -ne 0) { throw "xelab $tb failed" }
    & "$bin\xsim.bat" $tb -R | Select-String -Pattern 'clean|slot|stuck|write|read|PASS|FAIL|ERROR'
  }
} finally { Pop-Location; Pop-Location }
