# Runs tb_memtest with the Vivado 2024.2 simulator (xsim): ddr_memtest against a behavioural MIG
# native-interface model with random backpressure, random read latency and one injected bit error.
$ErrorActionPreference = 'Stop'
$bin = 'C:\Xilinx\Vivado\2024.2\bin'
Push-Location $PSScriptRoot
try {
  New-Item -ItemType Directory -Force work | Out-Null
  Push-Location work
  & "$bin\xvlog.bat" ..\..\rtl\ddr_memtest.v ..\tb_memtest.v
  if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
  & "$bin\xelab.bat" -timescale 1ns/1ps -debug off tb_memtest -s tb_memtest
  if ($LASTEXITCODE -ne 0) { throw 'xelab tb_memtest failed' }
  & "$bin\xsim.bat" tb_memtest -R | Select-String -Pattern '^run |PASS|FAIL|ERROR'
} finally { Pop-Location; Pop-Location }
