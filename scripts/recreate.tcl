# ---------------------------------------------------------------------------
# recreate.tcl
# Recreates the Vivado project for the FFT accelerator from the sources in
# this repository.
#
# Usage (from any directory):
#     vivado -mode batch -source scripts/recreate.tcl
# or, in the Vivado Tcl console:
#     source <path-to-repo>/scripts/recreate.tcl
#
# Requires: Vivado 2025.2. Target: Zybo Z7-20 (xc7z020clg400-1).
# The block design is rebuilt from scripts/Dizajn_bd.tcl, which was exported
# with write_bd_tcl.
# ---------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
set repo_dir   [file dirname $script_dir]
set proj_name  Diplomski
set proj_dir   [file join $repo_dir vivado_proj]

create_project $proj_name $proj_dir -part xc7z020clg400-1 -force
set_property target_language VHDL [current_project]

# --- Design sources ---------------------------------------------------------
add_files -fileset sources_1 [glob -directory [file join $repo_dir rtl] *.vhd]

# --- Constraints ------------------------------------------------------------
add_files -fileset constrs_1 [file join $repo_dir constraints Zybo-Z7-Master.xdc]

# --- Simulation sources -----------------------------------------------------
add_files -fileset sim_1 [glob -directory [file join $repo_dir sim] *.vhd]
set_property top fft_axis_tb [get_filesets sim_1]

update_compile_order -fileset sources_1

# --- User IP repository -----------------------------------------------------
# The block design uses fft_axis packaged as a user IP (ip_repo/).
set_property ip_repo_paths [file join $repo_dir ip_repo] [current_project]
update_ip_catalog -rebuild

# --- Block design -----------------------------------------------------------
source [file join $script_dir Dizajn_bd.tcl]

# HDL wrapper for the block design, set as top module
make_wrapper -files [get_files Dizajn.bd] -top
set wrapper [file join $proj_dir ${proj_name}.gen sources_1 bd Dizajn hdl Dizajn_wrapper.vhd]
add_files -norecurse $wrapper
set_property top Dizajn_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts "Project recreated in: $proj_dir"
puts "Next: run synthesis and implementation, generate the bitstream, then export hardware."
