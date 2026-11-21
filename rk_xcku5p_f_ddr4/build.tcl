# Non-project build of the RK-XCKU5P-F DDR4 demo, Vivado 2024.2 (run gen_ip.tcl once first):
#   C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -nojournal -log build/build.log -source build.tcl
# (or just .\build.ps1, which also runs gen_ip.tcl when ip/ is missing)
# Outputs: build/top.bit (JTAG load), reports in build/
set d [file normalize [file dirname [info script]]]
cd $d
file mkdir build
create_project -in_memory -part xcku5p-ffvb676-2-i
read_ip $d/ip/ddr4_0/ddr4_0.xci
set_property generate_synth_checkpoint false [get_files ddr4_0.xci]
generate_target all [get_ips]
read_verilog [glob $d/rtl/*.v]
read_xdc $d/top.xdc
synth_design -top top
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file build/timing.rpt
report_utilization -file build/util.rpt
report_clocks -file build/clocks.rpt
report_drc -file build/drc.rpt
write_bitstream -force build/top.bit
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "BUILD DONE  WNS $wns  WHS $whs"
