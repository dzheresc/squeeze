# Digilent Arty A7-35T

Part `xc7a35ticsg324-1L`, 100 MHz oscillator, FT2232H USB (channel A = JTAG, channel B = UART).
Toolchain: Vivado 2024.2 at `C:\Xilinx\Vivado\2024.2`.

## Build, simulate and load

```powershell
.\build.ps1      # ~2 min, writes build\top.bit and build\top.bin
.\sim\sim.ps1    # xsim: whole design at a scaled clock, UART decoded and checked (no board needed)
.\program.ps1    # JTAG load via hw_server localhost:3121 (volatile)
```

`.\program.ps1 -Url host:3121` targets a remote hw_server.

## What the starter design does

| I/O | Behaviour |
|---|---|
| LD4..LD7 (green) | 4-bit binary counter; `SW0..SW1` pick the speed |
| LD0..LD3 (RGB) | colour walk, dimmed to 1/16 duty |
| BTN0 | hold to freeze the counter |
| RESET (red) | clears the counter |
| USB UART | `arty a7 up NNNNNNNN` once a second (seconds since config, hex), 115200 8N1 |

Read the UART from PowerShell (the port was COM3 on the Dell):

```powershell
$p = New-Object System.IO.Ports.SerialPort COM3,115200; $p.Open(); 1..3 | % { $p.ReadLine() }; $p.Close()
```

Verified 2026-11-21: DONE=1, timing WNS +5.08 ns, UART lines counting.

## Not done yet

- SPI flash programming (`build/top.bin` is written, but the flash part differs by board revision; back up the flash first).
- UART RX (`uart_txd_in`, pin A9) is commented out in `top.xdc`.
