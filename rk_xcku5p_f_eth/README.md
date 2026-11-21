# RK-XCKU5P-F Ethernet receiver

Receives the once-a-second frames from [`arty_a7_35t_eth`](../arty_a7_35t_eth) on the board's RJ45
jack and shows the rolling one-hot pattern they carry on LED1..LED4. The jack is wired to a Realtek
RTL8211F-CG gigabit PHY (RGMII). Connect it to the Arty with a plain patch cable, with no switch
in between. Both PHYs do Auto-MDIX and auto-negotiation, and the link comes up at 100 Mb/s full
duplex.

## Build, simulate and load

```powershell
.\build.ps1      # ~3 min, writes build\top.bit
.\program.ps1    # JTAG load via hw_server localhost:3121 (volatile)
.\sim\sim.ps1    # xsim: Arty frame generator -> this receiver, and MDIO reads against a PHY model
```

## What it does

| I/O | Behaviour |
|---|---|
| LED1..LED4 | pattern of the last good frame (EtherType 88B5, correct FCS); off until the first one |
| KEY1 | clears the counters |
| USB UART (COM6) | one status line a second, 115200 8N1 |

```
ku5p-f eth phy 00 id 001cc916 bmsr 79ad lpa 41e1 good 0000000a bad 00000000 miss 00000000 seq 0000009b led 4
```

| Field | Meaning |
|---|---|
| `phy` | PHY address found by scanning PHYID1 on all 32 addresses (0 on this board) |
| `id` | PHYID1:PHYID2, `001cc916` = RTL8211F |
| `bmsr` | register 1; bit 2 = link up, bit 5 = auto-negotiation complete |
| `lpa` | register 5, the link partner's abilities; `41e1` = 10/100 half and full (the DP83848J) |
| `good` | frames of ours with a correct FCS |
| `bad` | frames with a wrong FCS or shorter than 64 bytes |
| `miss` | sequence numbers skipped between good frames |
| `seq` / `led` | sequence number and pattern of the last good frame |

All numbers are hex.

## Board notes (RK-XCKU5P-F V1.2)

- The RJ45 jack (HR911130A, with magnetics) is the only Ethernet port. The green and yellow LEDs
  in the jack are driven by the PHY.
- The RTL8211F sits on bank 66, whose VCCO is VCC_ADJ1 = 1.8 V (shared with the FMC LA pins), so
  the pins are LVCMOS18. Pins: MDC L19, MDIO M19, RXCK K22 (clock-capable), RXCTL K23,
  RXD0..3 L24 L25 K25 K26, TXCK M25, TXCTL M26, TXD0..3 L23 L22 L20 K20.
- The PHY's reset (PHYRSTB) and interrupt pins are not wired to the FPGA. The PHY resets itself at
  power-up and runs from its own 25 MHz crystal.
- The PHY's RGMII delay straps can't be read from the schematic. This design doesn't depend on
  them (see below).
- `BITSTREAM.CONFIG.UNUSEDPIN Pullup` would pull an unused TXCTL high and make the PHY transmit,
  so the design drives TXCK, TXCTL and TXD low.

## Design notes

- At 100 Mb/s RGMII, RXC is 25 MHz and each nibble is held for a whole clock. The receiver samples
  RXD and RXCTL on the falling edge of RXC, in the middle of the nibble, so it works whether or
  not the PHY delays RXC. These pins are timed against a 40 ns clock, which holds only at 10/100.
  Gigabit would need DDR capture and proper RGMII delays.
- `rtl/eth_rx_frame.v` finds the SFD, puts the nibbles back together low nibble first, and runs
  the CRC over the data and the FCS, expecting the residue `DEBB20E3`. It also picks out the
  EtherType, the pattern and the sequence number.
- Counters run in the RXC domain. After every frame a toggle bit carries them into the 200 MHz
  domain, which drives the LEDs and the UART. The 50 MHz PL_CLK on this board does not toggle, so
  everything runs from the 200 MHz oscillator.
- MDIO (`rtl/mdio_rd.v`, 1 MHz MDC) scans for the PHY once, then reads BMSR and the link partner
  abilities once a second.

Verified 2026-11-21 with a direct cable to the Arty running `arty_a7_35t_eth`: WNS +2.92 ns,
DONE=1, PHY at address 0, link up, every frame good, `bad 0`, `miss 0`, and the LED pattern
tracking the Arty's.
