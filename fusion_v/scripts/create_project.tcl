# Creates the Vivado project in fusion_v/vivado/ from the sources in fusion_v/.
#   GUI:   Tools -> Run Tcl Script... -> fusion_v/scripts/create_project.tcl
#   batch: vivado -mode batch -source fusion_v/scripts/create_project.tcl
# Add "-tclargs build" in batch mode to also run synthesis, implementation and bitstream.

set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado]

create_project fusion_v $proj_dir -part xc7a35tcpg236-1 -force
set_property target_language Verilog [current_project]

add_files -fileset sources_1 [glob [file join $root src *.v]]
set_property top top_fusion [get_filesets sources_1]

add_files -fileset sources_1 [file join $root ip cam_xclk cam_xclk.xci]
generate_target all [get_ips cam_xclk]

add_files -fileset constrs_1 [file join $root constrs basys3_fusion.xdc]

add_files -fileset sim_1 [glob [file join $root sim *.v]]
set_property top tb_fusion [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1

if {[llength $argv] > 0 && [lindex $argv 0] eq "build"} {
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    open_run impl_1
    report_utilization -file [file join $proj_dir utilization.rpt]
    report_timing_summary -file [file join $proj_dir timing.rpt]
}
