# squeeze

FPGA and dev-board projects. Every board gets its own folder with a self-contained
starter project (RTL in Verilog, Vivado 2024.2 non-project Tcl build, JTAG program script).

| Folder | Board | Part | Status |
|---|---|---|---|
| [arty_a7_35t](arty_a7_35t) | Digilent Arty A7-35T | xc7a35ticsg324-1L | blinky + UART heartbeat, verified on hardware |
| [arty_a7_35t_ddr3](arty_a7_35t_ddr3) | Digilent Arty A7-35T | xc7a35ticsg324-1L | 256 MB DDR3L via MIG, endless memory test on the UART |
| [rk_xcku5p_f](rk_xcku5p_f) | RK-XCKU5P-F V1.2 | xcku5p-ffvb676-2-i | LED counter, keys, UART heartbeat with die temperature, verified on hardware |
| [rk_xcku5p_f_ddr4](rk_xcku5p_f_ddr4) | RK-XCKU5P-F V1.2 | xcku5p-ffvb676-2-i | 2 GB DDR4 via MIG at 2400 MT/s, endless memory test on the UART, verified on hardware |

Common layout of a board folder:

```
rtl/*.v                   Verilog sources
top.xdc                   pins and timing for the board
build.tcl                 non-project Vivado build -> build/top.bit (+ .bin)
program.tcl               volatile JTAG load of build/top.bit
build.ps1 / program.ps1   PowerShell wrappers
```
