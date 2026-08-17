# =============================================================================
# sim/modelsim/run_all.do -- ModelSim ASE batch regression
# Implements VERIF_PLAN.md section 5.
#
# Second simulator for the same sources. The RTL is compiled as plain Verilog
# (it is strict Verilog-2001) and the testbenches with -sv, matching the Icarus
# flow's -g2001 / -g2012 split.
#
# `onfinish stop` keeps $finish from tearing down vsim between runs, so all
# runs happen in one invocation.
# =============================================================================

if {[file exists work]} { vdel -all -lib work }
vlib work

# ---- RTL: strict Verilog-2001 ----------------------------------------------
vlog -quiet ../../rtl/axi4_lite_slave.v
vlog -quiet ../../rtl/axi4_lite_interconnect.v
vlog -quiet ../../rtl/axi4_mem_slave.v
vlog -quiet ../../rtl/axi4_interconnect.v

# ---- Testbenches: Verilog-2001 plus the small SV subset of SPEC.md section 0 -
vlog -quiet -sv ../../tb/axi4_lite_master_bfm.v
vlog -quiet -sv ../../tb/axi4_master_bfm.v
vlog -quiet -sv ../../tb/axi4_lite_protocol_checker.v
vlog -quiet -sv ../../tb/axi4_protocol_checker.v
vlog -quiet -sv ../../tb/axi4_coverage.v
vlog -quiet -sv ../../tb/tb_axi4_lite_slave.v
vlog -quiet -sv ../../tb/tb_axi4_lite_interconnect.v
vlog -quiet -sv ../../tb/tb_axi4_mem_slave.v
vlog -quiet -sv ../../tb/tb_axi4_interconnect.v

onerror {resume}

# ---- regression matrix: {testbench test seed} ------------------------------
set runs {
    {tb_axi4_lite_slave         smoke      1}
    {tb_axi4_lite_slave         strobes    1}
    {tb_axi4_lite_slave         errors     1}
    {tb_axi4_lite_slave         aliasing   1}
    {tb_axi4_lite_slave         random     1}
    {tb_axi4_lite_slave         random     7}
    {tb_axi4_lite_interconnect  targeted   1}
    {tb_axi4_lite_interconnect  decerr     1}
    {tb_axi4_lite_interconnect  contention 1}
    {tb_axi4_lite_interconnect  parallel   1}
    {tb_axi4_lite_interconnect  fairness   1}
    {tb_axi4_lite_interconnect  random     1}
    {tb_axi4_lite_interconnect  random     7}
    {tb_axi4_mem_slave          smoke      1}
    {tb_axi4_mem_slave          incr       1}
    {tb_axi4_mem_slave          wrap       1}
    {tb_axi4_mem_slave          fixed      1}
    {tb_axi4_mem_slave          narrow     1}
    {tb_axi4_mem_slave          errors     1}
    {tb_axi4_mem_slave          boundary   1}
    {tb_axi4_mem_slave          random     1}
    {tb_axi4_mem_slave          random     7}
    {tb_axi4_interconnect       targeted   1}
    {tb_axi4_interconnect       decerr     1}
    {tb_axi4_interconnect       parallel   1}
    {tb_axi4_interconnect       contention 1}
    {tb_axi4_interconnect       random     1}
    {tb_axi4_interconnect       random     7}
}

foreach r $runs {
    set tb   [lindex $r 0]
    set test [lindex $r 1]
    set seed [lindex $r 2]
    echo "=== RUN $tb $test seed=$seed ==="
    vsim -quiet -c +TEST=$test +SEED=$seed work.$tb
    # onfinish only accepts a mode change once a design is elaborated, so it has
    # to be set per run rather than once up front; without it the first $finish
    # tears vsim down and the remaining runs never happen.
    onfinish stop
    run -all
    quit -sim
}

quit -f
