# Generate the MIG once (Vivado 2024.2):
#   C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -nojournal -log build/gen_ip.log -source gen_ip.tcl
# mig_ddr3: MIG 7-series DDR3L, native interface, from mig_ddr3.prj (Digilent's Arty A7-35 board-store
#   settings: MT41K128M16XX-15E x16, 256 MB, 3077 ps = 325 MHz / 650 MT/s, 4:1 -> ui_clk 81.25 MHz;
#   changed to native port, no-buffer 100 MHz system clock and 200 MHz reference clock from top's MMCM).
set d [file normalize [file dirname [info script]]]
create_project -in_memory -part xc7a35ticsg324-1L
file mkdir $d/ip
file delete -force $d/ip/mig_ddr3
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name mig_ddr3 -dir $d/ip
file copy -force $d/mig_ddr3.prj $d/ip/mig_ddr3/mig_ddr3.prj
set_property -dict [list CONFIG.XML_INPUT_FILE {mig_ddr3.prj} CONFIG.RESET_BOARD_INTERFACE {Custom} \
  CONFIG.MIG_DONT_TOUCH_PARAM {Custom} CONFIG.BOARD_MIG_PARAM {Custom}] [get_ips mig_ddr3]
generate_target {instantiation_template synthesis} [get_ips mig_ddr3]
puts "GEN DONE"
