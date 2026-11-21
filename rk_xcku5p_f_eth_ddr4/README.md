# RK-XCKU5P-F Ethernet to DDR4 ring recorder

Combines [`rk_xcku5p_f_eth`](../rk_xcku5p_f_eth) and [`rk_xcku5p_f_ddr4`](../rk_xcku5p_f_ddr4).
It receives the frame stream from [`arty_a7_35t_eth_stream`](../arty_a7_35t_eth_stream) on the
RTL8211F PHY (RGMII, 100 Mb/s) and writes every good frame into the board's 2 GB of DDR4 as a
circular buffer. It reads every frame back to check it. LED1..LED4 show the first payload
nibble, which is the Arty's rolling one-hot pattern, **as read back from DDR4**. So the LEDs only
follow the Arty if the whole Ethernet -> FIFO -> DDR4 -> LED path works.

## Build, simulate and load

```powershell
.\build.ps1      # first run also generates the MIG into ip\ (~1 min); build ~12 min
.\program.ps1    # JTAG load via hw_server localhost:3121 (volatile)
.\sim\sim.ps1    # xsim: Arty frame generator -> receiver -> FIFO -> ring writer -> MIG model
```

## What it does

| I/O | Behaviour |
|---|---|
| LED1..LED4 | low nibble of payload byte 0 of the last frame, read back from DDR4; off until the first |
| KEY1 | clears the counters and restarts the ring at slot 0 |
| USB UART (COM6) | one status line a second, 115200 8N1 |

```
ku5p-f eth-ddr4 cal 1 bmsr 79ad good 0089a4f2 bad 00000000 miss 00000000 ovf 00000000 wr 0089a4f2 fps 000245ba wrap 00000000 rderr 00000000 old 0079a4f2 olderr 00000000 led 4
```

| Field | Meaning |
|---|---|
| `cal` | DDR4 calibrated (frames are only counted and stored after this) |
| `bmsr` | PHY register 1; bit 2 = link up |
| `good` / `bad` | frames of ours with a correct FCS / frames with a wrong FCS or shorter than 64 bytes |
| `miss` | sequence numbers skipped between good frames |
| `ovf` | good frames dropped because the FIFO in front of the DDR4 was full |
| `wr` | slots written to DDR4 (= `good` - `ovf`, give or take the frames in flight) |
| `fps` | slots written in the last second (`245ba` = 148,922, the 100 Mb/s line rate) |
| `wrap` | times the ring wrapped (2^25 slots, ~3 min 45 s at line rate) |
| `rderr` | read-back 32-byte words that differ from what was written |
| `old` / `olderr` | checks of the slot written 2^20 frames earlier (~7 s at line rate) / failed ones |
| `led` | the LED value |

All numbers are hex.

## Ring layout

2 GB = 2^25 slots of 64 bytes. Frame n goes to slot `n mod 2^25`, byte address `64 * slot`:

| Bytes | Value |
|---|---|
| 0..45 | frame payload (frame bytes 14..59: pattern, sequence number, `SQUEEZE`, data) |
| 46..47 | frame length after the SFD, FCS included (64) |
| 48..51 | slot index n (frames written before this one) |
| 52..55 | wrap count when it was written |
| 56..59 | zero |
| 60..63 | `DDR4` |

## Design notes

- `rtl/eth_rx_frame.v` (from `rk_xcku5p_f_eth`) now also returns the 46 payload bytes. In the
  25 MHz RXC domain, each good frame is pushed with its length into `rtl/async_fifo.v`, a 16-deep
  384-bit dual-clock FIFO with Gray-coded pointers.
- `rtl/ddr_ring.v` runs on the MIG's 300 MHz `ui_clk`. It handles one frame at a time: two
  32-byte writes, a 256-cycle wait, then two reads that are compared with what was written. Once
  2^20 slots have been written, it also reads the second word of slot n - 2^20 and checks its
  index and magic. That catches address aliasing and lost data, which reading back the address
  just written cannot. One frame takes about 1.2 us out of the 6.7 us between frames at line
  rate.
- The MIG is the same as in `rk_xcku5p_f_ddr4`: MT40A512M16LY-075 at 2400 MT/s, native port,
  200 MHz clock on T24/U24. The 50 MHz PL_CLK does not toggle on this board. MDIO and the UART
  also run on `ui_clk`.
- RGMII receive is the same as in `rk_xcku5p_f_eth`: RXD/RXCTL are sampled on the falling edge of
  RXC, mid-nibble, so the PHY's RX delay strap doesn't matter at 100 Mb/s.

## Files

```
gen_ip.tcl          creates ip/ddr4_0 (not committed)
rtl/top.v           MIG, RGMII capture, counters, UART report
rtl/eth_rx_frame.v  frame parser + CRC check + payload capture
rtl/async_fifo.v    RXC -> ui_clk frame FIFO
rtl/ddr_ring.v      DDR4 ring writer and read-back checker
sim/tb_ring.v       end-to-end testbench with a MIG model (wraps a 64-slot ring 3 times)
```

Verified 2026-11-21 with a direct cable to the Arty running `arty_a7_35t_eth_stream` at line rate:
WNS +0.35 ns, DONE=1, DDR4 calibrated, `fps 00024548` (148,808 frames/s). After 41.7 million frames
(`wr 027c6128`, one full 2 GB wrap) the counters read `bad 0`, `miss 0`, `ovf 0`, `rderr 0` and
`olderr 0`, with 40.6 million old-slot checks done. The LEDs step with the Arty every 2 s.
Uses 11.6k LUTs (5%).
