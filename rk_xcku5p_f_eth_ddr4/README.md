# RK-XCKU5P-F Ethernet to DDR4 ring recorder

Combines [`rk_xcku5p_f_eth`](../rk_xcku5p_f_eth) and [`rk_xcku5p_f_ddr4`](../rk_xcku5p_f_ddr4).
It receives the frames from [`arty_a7_35t_eth_stream`](../arty_a7_35t_eth_stream) on the
RTL8211F PHY (RGMII, 100 Mb/s). It writes every good frame, all 64 bytes, into a circular
buffer that fills the board's whole 2 GB of DDR4, and reads every frame back to check it.
LED1..LED4 show the first payload nibble of the newest frame, which is the Arty's rolling one-hot
pattern, **as read back from DDR4**. So the LEDs only
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
| LED1..LED4 | low nibble of frame byte 14 (the pattern) of the newest frame, read back from DDR4; off until the first |
| KEY1 | clears the counters and restarts the ring at slot 0 |
| USB UART (COM6) | one status line a second, 115200 8N1 |

```
ku5p-f eth-ddr4 cal 1 bmsr 79ad gbcr 0000 good 000001a2 bad 00000000 miss 00000000 ovf 00000000 wr 000001a2 fps 00000004 wrap 00000000 rderr 00000000 old 00000192 olderr 00000000 led 4
```

| Field | Meaning |
|---|---|
| `cal` | DDR4 calibrated (frames are only counted and stored after this) |
| `bmsr` | PHY register 1; bit 2 = link up |
| `gbcr` | PHY register 9, the 1000BASE-T advertisement; `0000` once cleared at start-up |
| `good` / `bad` | frames of ours with a correct FCS / frames with a wrong FCS or shorter than 64 bytes |
| `miss` | sequence numbers skipped between good frames |
| `ovf` | good frames dropped because the FIFO in front of the DDR4 was full |
| `wr` | slots written to DDR4 (= `good` - `ovf`, give or take the frames in flight) |
| `fps` | slots written in the last second (4 with the Arty's default rate; `24548` = 148,808 at line rate) |
| `wrap` | times the ring wrapped (2^24 slots: 48 days at 4 frames/s, 1 min 53 s at line rate) |
| `rderr` | read-back 32-byte words that differ from what was written |
| `old` / `olderr` | checks of the slot written 16 frames earlier (4 s at 4 frames/s) / failed ones |
| `led` | the LED value |

All numbers are hex.

## Ring layout

2 GB = 2^24 slots of 128 bytes. Frame n goes to slot `n mod 2^24`, byte address `128 * slot`:

| Bytes | Value |
|---|---|
| 0..63 | the frame: the 64 bytes after the SFD (MACs, EtherType, pattern, sequence number, `SQUEEZE`, data, FCS) |
| 64..65 | frame length after the SFD, FCS included (64) |
| 66..67 | zero |
| 68..71 | slot index n (frames written before this one) |
| 72..75 | wrap count when it was written |
| 76..91 | zero |
| 92..95 | `DDR4` |
| 96..127 | zero |

## Design notes

- `rtl/eth_rx_frame.v` (from `rk_xcku5p_f_eth`) now also returns the first 64 bytes of the frame. In
  the 25 MHz RXC domain, each good frame is pushed with its length into `rtl/async_fifo.v`, a
  16-deep 528-bit dual-clock FIFO with Gray-coded pointers.
- `rtl/ddr_ring.v` runs on the MIG's 300 MHz `ui_clk`. It handles one frame at a time: four
  32-byte writes, a 256-cycle wait, then four reads that are compared with what was written.
  Once 16 slots have been written, it also reads the metadata word of slot n - 16 and checks its
  index and magic. That catches address aliasing and lost data, which reading back the address
  just written cannot. One frame takes about 1.3 us, well inside the 6.7 us between frames even
  at line rate.
- The MIG is the same as in `rk_xcku5p_f_ddr4`: MT40A512M16LY-075 at 2400 MT/s, native port,
  200 MHz clock on T24/U24. The 50 MHz PL_CLK does not toggle on this board. MDIO and the UART
  also run on `ui_clk`.
- RGMII receive is the same as in `rk_xcku5p_f_eth`: RXD/RXCTL are sampled on the falling edge of
  RXC, mid-nibble, so the PHY's RX delay strap doesn't matter at 100 Mb/s.
- The receiver only handles 10/100, but the RTL8211F would link at 1000 Mb/s to a gigabit
  switch. So on the first second after configuration, MDIO (`rtl/mdio_rw.v`) writes 0 to
  register 9, which stops the PHY advertising 1000BASE-T, and 0x1200 to register 0, which
  restarts auto-negotiation. The link then comes up at 100 Mb/s with either the Arty directly or
  a gigabit switch such as the TL-SG105 in between. The Arty's frames go to the broadcast
  address, so an unmanaged switch floods them to every port. Keep the Arty at 4 frames/s when
  other devices share the switch.

## Files

```
gen_ip.tcl          creates ip/ddr4_0 (not committed)
rtl/top.v           MIG, RGMII capture, counters, UART report
rtl/eth_rx_frame.v  frame parser + CRC check + frame capture
rtl/async_fifo.v    RXC -> ui_clk frame FIFO
rtl/ddr_ring.v      DDR4 ring writer and read-back checker
rtl/mdio_rw.v       clause 22 MDIO read and write
sim/tb_ring.v       end-to-end testbench with a MIG model (wraps a 64-slot ring 3 times)
sim/tb_mdio.v       MDIO write and read framing
```

Verified 2026-11-21 with a direct cable to the Arty running `arty_a7_35t_eth_stream`: WNS +0.42 ns,
DONE=1, DDR4 calibrated, `fps 00000004`, `bad 0`, `miss 0`, `ovf 0`, `rderr 0`, `olderr 0`, and
the LEDs stepping with the Arty's on every frame. The UART samples once a second, so with 4
frames/s and a 4-step pattern its `led` field shows the same value each time. With the Arty at
line rate, 1.5 million frames were stored the same way with no errors. The 64-byte-slot version
of this design also ran 41.7 million frames at line rate, past a full 2 GB wrap, with no errors.

Update 2026-11-21: the start-up MDIO writes that turn off the PHY's gigabit advertisement (for a
gigabit switch) pass simulation and build with WNS +0.57 ns. They are not yet tested on hardware.
