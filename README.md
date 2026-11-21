# squeeze

FPGA and dev-board projects. Every board gets its own folder with a self-contained
starter project (RTL in Verilog, Vivado 2024.2 non-project Tcl build, JTAG program script).

| Folder | Board | Part | Status |
|---|---|---|---|
| [arty_a7_35t](arty_a7_35t) | Digilent Arty A7-35T | xc7a35ticsg324-1L | blinky + UART heartbeat, verified on hardware |
| [arty_a7_35t_ddr3](arty_a7_35t_ddr3) | Digilent Arty A7-35T | xc7a35ticsg324-1L | 256 MB DDR3L via MIG, endless memory test on the UART |
| [rk_xcku5p_f](rk_xcku5p_f) | RK-XCKU5P-F V1.2 | xcku5p-ffvb676-2-i | LED counter, keys, UART heartbeat with die temperature, verified on hardware |
| [rk_xcku5p_f_ddr4](rk_xcku5p_f_ddr4) | RK-XCKU5P-F V1.2 | xcku5p-ffvb676-2-i | 2 GB DDR4 via MIG at 2400 MT/s, endless memory test on the UART, verified on hardware |
| [arty_a7_35t_eth](arty_a7_35t_eth) | Digilent Arty A7-35T | xc7a35ticsg324-1L | Ethernet sender: rolling LED pattern in a raw frame once a second (MII, 100 Mb/s), verified on hardware |
| [rk_xcku5p_f_eth](rk_xcku5p_f_eth) | RK-XCKU5P-F V1.2 | xcku5p-ffvb676-2-i | Ethernet receiver: shows the Arty's LED pattern, FCS and sequence checks on the UART (RGMII, RTL8211F), verified on hardware |
| [arty_a7_35t_eth_stream](arty_a7_35t_eth_stream) | Digilent Arty A7-35T | xc7a35ticsg324-1L | Ethernet sender: rolling one-hot pattern, one step per frame, 4 frames/s (up to line rate on SW1..0) |
| [rk_xcku5p_f_eth_ddr4](rk_xcku5p_f_eth_ddr4) | RK-XCKU5P-F V1.2 | xcku5p-ffvb676-2-i | Ethernet -> DDR4 ring recorder: every whole frame into all 2 GB, LEDs from RAM read-back, counters on the UART, verified on hardware |

Common layout of a board folder:

```
rtl/*.v                   Verilog sources
top.xdc                   pins and timing for the board
build.tcl                 non-project Vivado build -> build/top.bit (+ .bin)
program.tcl               volatile JTAG load of build/top.bit
build.ps1 / program.ps1   PowerShell wrappers
```

## Regression (no boards needed)

```powershell
.\run_sims.ps1     # every <project>\sim\sim.ps1 in xsim, one PASS / FAIL line per project (~5 min)
.\build_all.ps1    # every project's build.ps1 in turn, then WNS / WHS / LUT / FF / BRAM / critical warnings
```

Both take folder names to run a subset, e.g. `.\run_sims.ps1 arty_a7_35t rk_xcku5p_f`.
`build_all.ps1` also writes its table to `build\summary.md`.

| Folder | Testbench | What it checks |
|---|---|---|
| arty_a7_35t | sim/tb_top.v | whole design at a scaled clock: UART heartbeat lines, BTN0 hold, reset, LED bit select |
| arty_a7_35t_ddr3 | sim/tb_memtest.v | memtest engine (4 lanes) vs a MIG native-port model with random backpressure and read latency; all modes, base/length window, injected bit error reported at the right address |
| arty_a7_35t_eth_stream | sim/tb_top.v | whole sender incl. MMCM and clock crossings at scaled rates: PHY reset timing, every MII frame decoded (addresses, payload, seq, pattern, FCS), frame spacing at SW 00/01/11, fps on the UART, restart after reset |
| rk_xcku5p_f | sim/tb_top.v | whole design at a scaled clock with the UNISIM SYSMONE4 at 45.0 C: UART lines incl. temperature, KEY1..4 |
| rk_xcku5p_f_ddr4 | sim/tb_memtest.v | the same memtest bench with the 8-lane (256-bit) engine |
| rk_xcku5p_f_eth | sim/tb_eth.v, tb_mdio.v | Arty frame generator -> receiver (FCS, bad frame), MDIO reads |
| rk_xcku5p_f_eth_ddr4 | sim/tb_ring.v | Arty stream generator -> receiver -> FIFO -> DDR4 ring writer -> MIG model |

arty_a7_35t_eth's frame generator is covered by rk_xcku5p_f_eth's tb_eth.

Clean rebuild of `main` (a08d09d) with Vivado 2024.2 on 2026-11-21, all from `build_all.ps1`:

| Project | WNS ns | WHS ns | LUT | FF | BRAM | Crit. warnings | Minutes |
|---|---|---|---|---|---|---|---|
| arty_a7_35t | 5.084 | 0.085 | 105 | 160 | 0 | 0 | 1.3 |
| arty_a7_35t_ddr3 | 1.316 | 0.012 | 5415 | 5026 | 0 | 0 | 6.3 |
| arty_a7_35t_eth | 4.464 | 0.131 | 399 | 670 | 0 | 0 | 1.6 |
| arty_a7_35t_eth_stream | 4.995 | 0.118 | 612 | 1061 | 0 | 0 | 1.8 |
| rk_xcku5p_f | 0.869 | 0.028 | 201 | 535 | 0 | 0 | 3.6 |
| rk_xcku5p_f_ddr4 | 0.292 | 0.010 | 11207 | 14078 | 25.5 | 0 | 12.3 |
| rk_xcku5p_f_eth | 2.916 | 0.009 | 719 | 1402 | 0 | 0 | 3.0 |
| rk_xcku5p_f_eth_ddr4 | 0.418 | 0.014 | 11992 | 16986 | 25.5 | 0 | 11.8 |

rk_xcku5p_f_eth_ddr4 failed once in opt_design ("Cannot open file ... u_mig_ddr4_phy_phy.xdc" while
regenerating the MIG PHY in %TEMP%) and built cleanly on the retry; that error is a Vivado flake,
not a design problem.
