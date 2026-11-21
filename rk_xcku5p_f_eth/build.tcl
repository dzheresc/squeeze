# Non-project build for the RK-XCKU5P-F, Vivado 2024.2:
#   C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -nojournal -log build/build.log -source build.tcl
# (or just .\build.ps1)
# Outputs: build/top.bit (JTAG load), reports in build/
set d [file normalize [file dirname [info script]]]
cd $d
file mkdir build
create_project -in_memory -part xcku5p-ffvb676-2-i
read_verilog [glob $d/rtl/*.v]
read_xdc $d/top.xdc
synth_design -top top
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file build/timing.rpt
report_utilization -file build/util.rpt
report_drc -file build/drc.rpt
write_bitstream -force build/top.bit
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "BUILD DONE  WNS $wns  WHS $whs"
