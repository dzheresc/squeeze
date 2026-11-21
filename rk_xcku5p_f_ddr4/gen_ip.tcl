# Generate the MIG once (Vivado 2024.2):
#   C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -nojournal -log build/gen_ip.log -source gen_ip.tcl
# ddr4_0: UltraScale MIG DDR4, native interface. Board memory is two MT40A512M16LY-062E (x16, 8 Gb)
#   = 32-bit, 2 GB. The 2024.2 catalog has no -062E, so MT40A512M16LY-075 (the vendor example's part,
#   same organisation, slower bin) is used. 833 ps = 2400 MT/s (the vendor example runs 2666),
#   4:1 -> ui_clk 300 MHz, 256-bit user data. 200 MHz differential system clock on T24/U24.
set d [file normalize [file dirname [info script]]]
create_project -in_memory -part xcku5p-ffvb676-2-i
file mkdir $d/ip
file delete -force $d/ip/ddr4_0
create_ip -name ddr4 -vendor xilinx.com -library ip -module_name ddr4_0 -dir $d/ip
set m [get_ips ddr4_0]
set_property -dict [list CONFIG.C0.DDR4_MemoryType {Components} CONFIG.C0.DDR4_TimePeriod {833}] $m
set_property CONFIG.C0.DDR4_MemoryPart {MT40A512M16LY-075} $m
set_property -dict [list \
  CONFIG.C0.DDR4_DataWidth {32} \
  CONFIG.C0.DDR4_DataMask {DM_NO_DBI} \
  CONFIG.C0.DDR4_Ecc {false} \
  CONFIG.C0.DDR4_AxiSelection {false} \
  CONFIG.C0.DDR4_InputClockPeriod {4998} \
  CONFIG.C0.DDR4_CasLatency {17} \
  CONFIG.C0.DDR4_CasWriteLatency {12} \
  CONFIG.System_Clock {Differential} \
  CONFIG.Reference_Clock {Differential} \
  CONFIG.C0.DDR4_Mem_Add_Map {ROW_COLUMN_BANK} \
  CONFIG.C0.DDR4_Ordering {Normal} \
  CONFIG.Debug_Signal {Disable} \
] $m
generate_target {instantiation_template synthesis} $m
foreach p {CONFIG.C0.DDR4_MemoryPart CONFIG.C0.DDR4_DataWidth CONFIG.C0.DDR4_TimePeriod
           CONFIG.C0.DDR4_InputClockPeriod CONFIG.C0.DDR4_CasLatency CONFIG.C0.DDR4_CasWriteLatency} {
  puts "CHK $p = [get_property -quiet $p $m]"
}
puts "GEN DONE"
