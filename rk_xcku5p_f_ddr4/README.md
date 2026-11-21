# RK-XCKU5P-F DDR4 memory test

Uses the board's 2 GB of DDR4 (two Micron MT40A512M16LY x16 = 32-bit) through the UltraScale
MIG, native interface, and runs an endless full-memory write/read/verify test at full rate,
printing results on the USB UART.

| | |
|---|---|
| Memory | 32-bit, 2 GB; MIG part `MT40A512M16LY-075` (2024.2 has no `-062E`; same organisation, slower bin) |
| DDR clock | 1200 MHz (2400 MT/s), 4:1 PHY, `ui_clk` 300.12 MHz, 256-bit user data |
| Peak bandwidth | 32 B x 300.12 MHz = 9.60 GB/s |
| Clocks | 200 MHz differential board clock (T24/U24) straight into the MIG |
| Pins | from the vendor's `ddr4_0_ex` example design |

## Build, simulate and load

```powershell
.\build.ps1      # first run also generates the MIG into ip\ (~1 min); build ~12 min
.\sim\sim.ps1    # xsim: memtest engine vs a MIG native-port model (backpressure, injected bit error)
.\program.ps1    # JTAG load (volatile)
```

## Output

UART 115200 8N1 (COM6 on the Dell):

```
ddr4 calib ok
pass 00000001 mode 1 errs 00000000 wcyc 04ff6bf0 rcyc 044f5cf8 bad ffffffff exp 00000000 got 00000000
```

- `ddr4 calib wait` repeats about once a second if calibration does not finish
- one line per full 2 GB pass (write all, then read and verify all, ~0.5 s); numbers are hex
- `mode` cycles 0..3: address, inverted address, xorshift of address, all-bits-toggle; the seed changes every pass
- `errs` = mismatched 32-bit lanes; `bad`/`exp`/`got` = first failure (`bad ffffffff` = none)
- `wcyc`/`rcyc` = `ui_clk` cycles for the write and read pass;
  MB/s = 2147483648 * 300.12e6 / cycles / 1e6

Verified 2026-11-21 on the Dell: calibrates, 0 errors over all modes (15+ passes),
write 7.69 GB/s, read 8.91 GB/s (80% and 93% of the 9.60 GB/s peak; the rest is refresh and
bank/row turnaround). WNS +0.29 ns.

LEDs: LED1 calibrated, LED2 toggles every pass, LED3 sticky error, LED4 test running.
Hold KEY1 to reset the MIG; on release it recalibrates and the test restarts.

## Files

```
gen_ip.tcl        creates ip/ddr4_0 (not committed)
rtl/top.v         MIG, test sequencer, UART report, LEDs
rtl/ddr_memtest.v full-rate pattern write/verify engine (same as arty_a7_35t_ddr3, 8 lanes here)
rtl/uart_tx.v     8N1 transmitter
sim/tb_memtest.v  memtest testbench with a behavioural MIG model
```
