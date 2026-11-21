# Volatile JTAG load of build/top.bit (DDR3 demo) into the Arty A7-35T (no flash access).
#   C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -nojournal -log build/program.log -source program.tcl [-tclargs host:port]
# (or just .\program.ps1)
set url [expr {[llength $argv] > 0 ? [lindex $argv 0] : "localhost:3121"}]
set d [file normalize [file dirname [info script]]]
open_hw_manager
connect_hw_server -url $url
set dev ""
foreach t [get_hw_targets] {
  open_hw_target $t
  set dev [lindex [get_hw_devices -quiet xc7a35t*] 0]
  if {$dev ne ""} { puts "Arty A7-35T on target $t"; break }
  close_hw_target $t
}
if {$dev eq ""} { error "No xc7a35t on any JTAG target of $url" }
current_hw_device $dev
set_property PROGRAM.FILE $d/build/top.bit $dev
program_hw_devices $dev
refresh_hw_device $dev
puts "DONE pin: [get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev]"
close_hw_target
disconnect_hw_server
close_hw_manager
