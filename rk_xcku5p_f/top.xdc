## RK-XCKU5P-F V1.2 (xcku5p-ffvb676-2-i). Pins from the vendor schematic (RK-XCKU5P-F V1.2).

## 200 MHz differential oscillator on T24/U24 (bank 65, 1.2 V; the DDR4 system clock).
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

## USB-UART (FT2232H channel B, COM6 on the Dell): FPGA_UART_TX on AC14 (FPGA_UART_RX is AD13)
set_property -dict {PACKAGE_PIN AC14 IOSTANDARD LVCMOS33} [get_ports uart_tx]

## Async inputs and slow outputs: no timing to meet
set_false_path -from [get_ports {key_n[*]}]
set_false_path -to   [get_ports {led[*] uart_tx}]

## Configuration (values match the vendor image: 1.8 V config bank, SPI x4 flash)
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
