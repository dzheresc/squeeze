## RK-XCKU5P-F V1.2 (xcku5p-ffvb676-2-i) Ethernet receiver. Pins from the vendor schematic and
## pin table (RK-XCKU5P-F V1.2), balls checked against the Vivado 2024.2 package data.

## 200 MHz differential oscillator on T24/U24 (bank 65, 1.2 V).
## The 50 MHz PL_CLK on AC13 (bank 84) does not toggle on this board, so it is not used.
set_property -dict {PACKAGE_PIN T24 IOSTANDARD DIFF_SSTL12} [get_ports sys_clk_p]
set_property -dict {PACKAGE_PIN U24 IOSTANDARD DIFF_SSTL12} [get_ports sys_clk_n]
create_clock -name sys_clk -period 5.000 [get_ports sys_clk_p]

## KEY1..KEY4 (bank 86, 3.3 V): pulled up on the board, low when pressed
set_property -dict {PACKAGE_PIN K9  IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {key_n[0]}]
set_property -dict {PACKAGE_PIN K10 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {key_n[1]}]
set_property -dict {PACKAGE_PIN J10 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {key_n[2]}]
set_property -dict {PACKAGE_PIN J11 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports {key_n[3]}]

## LED1..LED4 (bank 86, 3.3 V, transistor drivers: high = on)
set_property -dict {PACKAGE_PIN H9  IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J9  IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN G11 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN H11 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## USB-UART (FT2232H channel B, COM6 on the Dell): FPGA_UART_TX on AC14
set_property -dict {PACKAGE_PIN AC14 IOSTANDARD LVCMOS33} [get_ports uart_tx]

## Ethernet PHY (Realtek RTL8211F-CG, RGMII). Bank 66, VCCO = VCC_ADJ1 = 1.8 V.
## The PHY's reset and interrupt pins are not wired to the FPGA.
set_property -dict {PACKAGE_PIN K22 IOSTANDARD LVCMOS18} [get_ports phy_rxck]
set_property -dict {PACKAGE_PIN K23 IOSTANDARD LVCMOS18} [get_ports phy_rxctl]
set_property -dict {PACKAGE_PIN L24 IOSTANDARD LVCMOS18} [get_ports {phy_rxd[0]}]
set_property -dict {PACKAGE_PIN L25 IOSTANDARD LVCMOS18} [get_ports {phy_rxd[1]}]
set_property -dict {PACKAGE_PIN K25 IOSTANDARD LVCMOS18} [get_ports {phy_rxd[2]}]
set_property -dict {PACKAGE_PIN K26 IOSTANDARD LVCMOS18} [get_ports {phy_rxd[3]}]
set_property -dict {PACKAGE_PIN M25 IOSTANDARD LVCMOS18} [get_ports phy_txck]
set_property -dict {PACKAGE_PIN M26 IOSTANDARD LVCMOS18} [get_ports phy_txctl]
set_property -dict {PACKAGE_PIN L23 IOSTANDARD LVCMOS18} [get_ports {phy_txd[0]}]
set_property -dict {PACKAGE_PIN L22 IOSTANDARD LVCMOS18} [get_ports {phy_txd[1]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS18} [get_ports {phy_txd[2]}]
set_property -dict {PACKAGE_PIN K20 IOSTANDARD LVCMOS18} [get_ports {phy_txd[3]}]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS18} [get_ports phy_mdc]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS18 PULLUP TRUE} [get_ports phy_mdio]

## RGMII receive at 100 Mb/s: RXC 25 MHz. Data changes near the rising edge of RXC (a little
## before it if the PHY's RX delay strap is set) and is captured on the falling edge.
create_clock -name rgmii_rxc -period 40.000 [get_ports phy_rxck]
set_input_delay -clock rgmii_rxc -max  1.500 [get_ports {phy_rxd[*] phy_rxctl}]
set_input_delay -clock rgmii_rxc -min -3.000 [get_ports {phy_rxd[*] phy_rxctl}]
set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks rgmii_rxc]

## Async inputs and slow or constant outputs: no timing to meet
set_false_path -from [get_ports {key_n[*] phy_mdio}]
set_false_path -to   [get_ports {led[*] uart_tx phy_mdc phy_mdio phy_txck phy_txctl phy_txd[*]}]

## Configuration (values match the vendor image: 1.8 V config bank, SPI x4 flash)
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
