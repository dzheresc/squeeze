# Arty A7-35T Ethernet sender

Sends one raw Ethernet frame a second through the Arty's 10/100 PHY (TI DP83848J, MII).
Each frame carries a one-hot 4-bit pattern that rolls over (`0001 -> 0010 -> 0100 -> 1000 -> 0001`).
The pattern goes on the green LEDs LD4..LD7 just before the frame leaves. The receiving side is
[`rk_xcku5p_f_eth`](../rk_xcku5p_f_eth), which shows the same pattern on its LEDs. A plain patch
cable between the two RJ45 jacks is enough: both PHYs do Auto-MDIX and auto-negotiation and settle
on 100 Mb/s full duplex.

## Build and load

```powershell
.\build.ps1      # ~2 min, writes build\top.bit and build\top.bin
.\program.ps1    # JTAG load via hw_server localhost:3121 (volatile)
```

## What it does

| I/O | Behaviour |
|---|---|
| LD4..LD7 (green) | pattern of the frame being sent |
| LD0 (green, dim) | PHY link up |
| RESET (red) | resets the PHY, restarts the pattern and the sequence number |
| USB UART (COM3) | `arty eth tx SSSSSSSS led L bmsr XXXX physts XXXX` after every frame, 115200 8N1 |

`S` = sequence number of the frame and `L` = pattern, both hex. `bmsr` and `physts` are PHY
registers 0x01 and 0x10 (PHY address 1). In PHYSTS, bit 0 = link, bit 1 = 10 Mb/s, bit 2 = full
duplex, so `physts 0715` is link up at 100 Mb/s full duplex.

## Frame

| Bytes | Value |
|---|---|
| 0..5 | `FF:FF:FF:FF:FF:FF` (broadcast) |
| 6..11 | `02:00:00:00:A7:35` (locally administered) |
| 12..13 | EtherType `88B5` (IEEE local experimental) |
| 14 | `{4'h0, pattern}` |
| 15..18 | sequence number, big endian, first frame = 1 |
| 19..25 | `SQUEEZE` |
| 26..59 | zero padding (60 bytes before the FCS, the Ethernet minimum) |
| 60..63 | FCS (CRC-32) |

## Design notes

- An MMCM makes the PHY's 25 MHz reference clock from the 100 MHz oscillator and sends it out
  of G18 (`eth_ref_clk`) through an ODDR. The PHY is held in reset for 10 ms after that, and
  frames start 120 ms after configuration.
- The frame generator (`rtl/eth_tx_frame.v`) runs on the PHY's 25 MHz TX_CLK. The 1 Hz tick in
  the 100 MHz domain changes the LEDs and toggles a request bit. TX_CLK picks up the request
  through a 3-flop synchroniser, so the frame leaves about 100 ns after the LEDs change.
- MDIO (`rtl/mdio_rd.v`, 1 MHz MDC) reads BMSR and PHYSTS once a second for the UART line.
- `rtl/crc32_d8.v` is the byte-wide Ethernet CRC. It is checked in simulation against the
  standard check value `CBF43926` and against the receiver's CRC residue (see
  [`rk_xcku5p_f_eth/sim`](../rk_xcku5p_f_eth/sim)).

Verified 2026-11-21 with a direct cable to the RK-XCKU5P-F running `rk_xcku5p_f_eth`: WNS +4.46 ns,
DONE=1, `physts 0715` (100 Mb/s full duplex). The receiver counted every frame, with no FCS errors
and no gaps in the sequence numbers.
