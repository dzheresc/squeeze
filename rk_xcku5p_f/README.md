# RK-XCKU5P-F V1.2 (Kintex UltraScale+ KU5P)

Part `xcku5p-ffvb676-2-i`, IDCODE `04A62093`. One USB-C port with an FT2232H
(channel A = JTAG, hw_server target `Xilinx/0ABC01A`; channel B = UART, COM6 on the Dell).
Toolchain: Vivado 2024.2 at `C:\Xilinx\Vivado\2024.2`.

## Build, simulate and load

```powershell
.\build.ps1      # ~3 min, writes build\top.bit
.\sim\sim.ps1    # xsim: whole design at a scaled clock, SYSMONE4 model at 45.0 C, UART checked
.\program.ps1    # JTAG load via hw_server localhost:3121 (volatile)
```

`.\program.ps1 -Url host:3121` targets a remote hw_server.

## What the starter design does

| I/O | Behaviour |
|---|---|
| LED1..LED4 | 4-bit binary counter |
| KEY1 | each press steps the counter speed 0..3 (wraps) |
| KEY2 | hold to freeze the counter |
| KEY3 | hold to clear the counter |
| KEY4 | lamp test: all LEDs on while held |
| USB UART | `ku5p-f up SSSSSSSS speed N keys K temp +TTT.TC` once a second, 115200 8N1 |

`S` = seconds since load and `K` = pressed keys (bit 0 = KEY1), both hex. `temp` is the FPGA die
temperature from the SYSMONE4 (`rtl/sysmon_temp.v`, read over the DRP every 1 ms), in degrees Celsius.

Read the UART from PowerShell:

```powershell
$p = New-Object System.IO.Ports.SerialPort COM6,115200; $p.Open(); 1..3 | % { $p.ReadLine() }; $p.Close()
```

Verified 2026-11-21: DONE=1, WNS +0.87 ns, UART lines counting once a second,
`temp +029.4C`, the same value the Vivado Hardware Manager SYSMON reported at that time.
The keys were not pressed during the check (nobody at the board).

## Board notes

- Clock: the design runs on the 200 MHz differential oscillator on T24/U24 (bank 65,
  `DIFF_SSTL12`, also the DDR4 system clock). The schematic's 50 MHz `PL_CLK` on AC13 does not
  toggle on this board: a counter on it stayed at 0 while the 200 MHz domain ran.
- UART: `FPGA_UART_TX` = AC14 (FPGA output), `FPGA_UART_RX` = AD13, both 3.3 V bank 84.
- LEDs H9 J9 G11 H11 (high = on), keys K9 K10 J10 J11 (pulled up, low = pressed), bank 86.
- Config bank is 1.8 V, SPI x4 flash; this project only does volatile JTAG loads.
