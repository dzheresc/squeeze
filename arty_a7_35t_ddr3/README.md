# Arty A7-35T DDR3 memory test

Uses the board's 256 MB DDR3L (Micron MT41K128M16, x16) through the Xilinx MIG 7-series,
native interface, and runs an endless full-memory write/read/verify test at full rate,
printing results on the USB UART.

| | |
|---|---|
| Memory | MT41K128M16XX-15E settings, 16-bit, 256 MB |
| DDR clock | 325 MHz (650 MT/s), 4:1 PHY, `ui_clk` 81.25 MHz, 128-bit user data |
| Peak bandwidth | 16 B x 81.25 MHz = 1.30 GB/s |
| MIG settings | `mig_ddr3.prj`, from Digilent's Arty A7-35 board-store file, switched to native port and no-buffer clocks |
| Clocks | 100 MHz board clock -> MMCM -> 100 MHz MIG system clock + 200 MHz IDELAY reference |

## Build and load

```powershell
.\build.ps1      # first run also generates the MIG into ip\ (~1 min); build ~5 min
.\program.ps1    # JTAG load (volatile)
```

## Output

UART 115200 8N1 (COM3 on the Dell):

```
ddr3 calib ok
pass 00000000 mode 0 errs 00000000 wcyc 012dcd97 rcyc 0114db3b bad ffffffff exp 00000000 got 00000000
```

- one line per full 256 MB pass (write all, then read and verify all); numbers are hex
- `mode` cycles 0..3: address, inverted address, xorshift of address, all-bits-toggle; the seed changes every pass
- `errs` = mismatched 32-bit lanes; `bad`/`exp`/`got` = first failure (`bad ffffffff` = none)
- `wcyc`/`rcyc` = `ui_clk` cycles for the write and read pass;
  MB/s = 268435456 * 81.25e6 / cycles / 1e6

Verified 2026-11-21 on the Dell: calibrates, 0 errors over all modes, write 1103 MB/s, read 1202 MB/s
(85% and 92% of the 1.30 GB/s peak; the rest is refresh and bank/row turnaround).

LEDs: LD4 calibrated, LD5 toggles every pass, LD6 sticky error, LD7 test running;
RGB LD0 dim green while clean, red after any error. The red RESET button recalibrates and restarts.

## Files

```
mig_ddr3.prj      MIG configuration (pins, timing) fed to gen_ip.tcl
gen_ip.tcl        creates ip/mig_ddr3 (not committed)
rtl/top.v         clocks, MIG, test sequencer, UART report, LEDs
rtl/ddr_memtest.v full-rate pattern write/verify engine on the MIG native port
rtl/uart_tx.v     8N1 transmitter
```
