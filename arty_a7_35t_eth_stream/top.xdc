## Digilent Arty A7-35T (xc7a35ticsg324-1L) Ethernet stream sender. Pins from the Digilent Arty-A7-35
## master XDC / board files.

## 100 MHz oscillator
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -name sys_clk -period 10.000 [get_ports CLK100MHZ]

## Red RESET button (active low)
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports ck_rst]

## Slide switches SW0, SW1 (frame rate)
set_property -dict {PACKAGE_PIN A8  IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]

## Green LEDs LD4..LD7
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## RGB LEDs LD0..LD3, green channel
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports {led_g[0]}]
set_property -dict {PACKAGE_PIN J4 IOSTANDARD LVCMOS33} [get_ports {led_g[1]}]
set_property -dict {PACKAGE_PIN J2 IOSTANDARD LVCMOS33} [get_ports {led_g[2]}]
set_property -dict {PACKAGE_PIN H6 IOSTANDARD LVCMOS33} [get_ports {led_g[3]}]

## USB-UART (FT2232H channel B). uart_rxd_out = FPGA TX.
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_rxd_out]

## Ethernet PHY (TI DP83848J, MII, PHY address 1)
set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33} [get_ports eth_ref_clk]
set_property -dict {PACKAGE_PIN C16 IOSTANDARD LVCMOS33} [get_ports eth_rstn]
set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33} [get_ports eth_tx_clk]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports eth_tx_en]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33} [get_ports {eth_txd[0]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {eth_txd[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {eth_txd[2]}]
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {eth_txd[3]}]
set_property -dict {PACKAGE_PIN F16 IOSTANDARD LVCMOS33} [get_ports eth_mdc]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33 PULLUP TRUE} [get_ports eth_mdio]

## MII transmit: 25 MHz TX_CLK from the PHY; the PHY samples TXD/TX_EN on its rising edge
## (DP83848J: 10 ns setup, 0 ns hold).
create_clock -name eth_tx_clk -period 40.000 [get_ports eth_tx_clk]
set_output_delay -clock eth_tx_clk -max 10.000 [get_ports {eth_txd[*] eth_tx_en}]
set_output_delay -clock eth_tx_clk -min  0.000 [get_ports {eth_txd[*] eth_tx_en}]
set_clock_groups -asynchronous -group [get_clocks -include_generated_clocks sys_clk] -group [get_clocks eth_tx_clk]

## Async inputs and slow outputs: no timing to meet
set_false_path -from [get_ports {ck_rst sw[*] eth_mdio}]
set_false_path -to   [get_ports {led[*] led_g[*] uart_rxd_out eth_rstn eth_mdc eth_mdio eth_ref_clk}]

## Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
