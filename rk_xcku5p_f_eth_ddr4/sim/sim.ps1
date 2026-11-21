# Runs tb_ring with the Vivado 2024.2 simulator (xsim): arty_a7_35t_eth_stream's frame generator
# -> this project's receiver, FIFO and DDR4 ring writer -> a simple MIG model.
$ErrorActionPreference = 'Stop'
$bin = 'C:\Xilinx\Vivado\2024.2\bin'
$arty = '..\..\..\arty_a7_35t_eth_stream\rtl'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force work | Out-Null
  Push-Location work
  & "$bin\xvlog.bat" "$arty\crc32_d8.v" "$arty\eth_tx_frame.v" ..\..\rtl\eth_rx_frame.v ..\..\rtl\async_fifo.v ..\..\rtl\ddr_ring.v ..\tb_ring.v
  if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
  & "$bin\xelab.bat" -timescale 1ns/1ps -debug off tb_ring -s tb_ring
  if ($LASTEXITCODE -ne 0) { throw 'xelab tb_ring failed' }
  & "$bin\xsim.bat" tb_ring -R | Select-String -Pattern 'clean|slot|stuck|PASS|FAIL|ERROR'
} finally { Pop-Location; Pop-Location }
