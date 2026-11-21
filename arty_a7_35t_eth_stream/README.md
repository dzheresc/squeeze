# Arty A7-35T Ethernet stream sender

Streams raw Ethernet frames through the Arty's 10/100 PHY (TI DP83848J, MII) at up to the full
100 Mb/s line rate. Every frame carries a new sequence number. The one-hot 4-bit pattern in the
first payload byte rolls over (`0001 -> 0010 -> 0100 -> 1000 -> 0001`) only every 2 s, so the
LEDs on the receiving side blink at a pace you can follow. The receiver is
[`rk_xcku5p_f_eth_ddr4`](../rk_xcku5p_f_eth_ddr4). It stores every frame in DDR4 and drives its
LEDs from the copy it reads back. Use a plain patch cable between the two RJ45 jacks. The link
comes up at 100 Mb/s full duplex.

This is [`arty_a7_35t_eth`](../arty_a7_35t_eth) (one frame a second) turned into a stream. The
frame format is the same, except the padding now carries data.

## Build and load

```powershell
.\build.ps1      # ~2 min, writes build\top.bit and build\top.bin
.\program.ps1    # JTAG load via hw_server localhost:3121 (volatile)
```

## What it does

| I/O | Behaviour |
|---|---|
| LD4..LD7 (green) | current pattern, changes every 2 s |
| LD0 (green, dim) | PHY link up |
| SW1..SW0 | frame rate: `00` line rate (~148.8k frames/s), `01` 10k/s, `10` 1k/s, `11` 100/s |
| RESET (red) | resets the PHY, restarts the pattern and the sequence number |
| USB UART (COM3) | one status line a second, 115200 8N1 |

```
arty eth stream sent 0089a4f2 fps 000245ba led 4 sw 0 bmsr 782d physts 0715
```

`sent` = frames sent so far (= last sequence number) and `fps` = frames in the last second
(`245ba` = 148,922 at line rate), both hex. `bmsr` and `physts` are PHY registers 0x01 and 0x10.
`physts 0715` is link up at 100 Mb/s full duplex.

## Frame

| Bytes | Value |
|---|---|
| 0..5 | `FF:FF:FF:FF:FF:FF` (broadcast) |
| 6..11 | `02:00:00:00:A7:35` (locally administered) |
| 12..13 | EtherType `88B5` (IEEE local experimental) |
| 14 | `{4'h0, pattern}` |
| 15..18 | sequence number, big endian, first frame = 1 |
| 19..25 | `SQUEEZE` |
| 26..59 | payload byte k (k = 12..45) = `seq[7:0] + k`, so every frame's data differs |
| 60..63 | FCS (CRC-32) |

At line rate, frames go out back to back: 72 bytes with the preamble, then the minimum 12-byte
gap. That is 168 TX_CLK cycles per frame, or 25 MHz / 168 = 148,810 frames/s.

## Design notes

- The frame generator, the 2 s pattern timer and the frame counter all run on the PHY's 25 MHz
  TX_CLK, so the frame rate is exact. Once a second a snapshot of the counters crosses into the
  100 MHz domain for the UART line.
- An MMCM makes the PHY's 25 MHz reference clock. The PHY is held in reset for 10 ms, and frames
  start 120 ms after configuration.
- MDIO (`rtl/mdio_rd.v`, 1 MHz MDC) reads BMSR and PHYSTS once a second.
- The frame generator is simulated against the receiver in
  [`rk_xcku5p_f_eth_ddr4/sim`](../rk_xcku5p_f_eth_ddr4/sim).

Verified 2026-11-21 with a direct cable to the RK-XCKU5P-F running `rk_xcku5p_f_eth_ddr4`: WNS +5.16 ns,
DONE=1, `physts 0715`, `fps 0002454a` (148,810 frames/s), and the pattern stepping every 2 s.
The receiver stored every frame with no FCS errors and no gaps.
