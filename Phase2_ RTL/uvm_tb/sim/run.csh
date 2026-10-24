#!/bin/csh -f

if ($#argv != 1) then
  echo "Usage: csh run.csh uvm|wave|check"
  exit 2
endif
set mode = "$argv[1]"
if ("$mode" != "uvm" && "$mode" != "wave" && "$mode" != "check") then
  echo "Unknown mode: $mode"
  exit 2
endif
if ("$0" =~ */*) then
  cd "$0:h"
  if ($status != 0) exit 2
endif

set sources = ( \
  ../../rtl/cordic_pkg.sv \
  ../../rtl/div.sv \
  ../../rtl/iter.sv \
  ../../rtl/core.sv \
  ../../rtl/qual.sv \
  ../../rtl/csr_apb.sv \
  ../../rtl/systolic.sv \
  ../../rtl/act_ip.sv \
  ../../rtl/accel.sv \
  ../tb/ref.sv \
  ../tb/apb_if.sv \
  ../tb/act_if.sv \
  ../tb/tcdm_if.sv \
  ../tb/csr_pkg.sv \
  ../tb/ip_pkg.sv \
  ../top/hdl_top.sv \
  ../top/hvl_top.sv )

foreach source_file ($sources:q)
  if (! -f "$source_file") then
    echo "Missing source: $source_file"
    echo "Upload the complete Phase2_ RTL folder, including the main RTL directories."
    exit 2
  endif
end
if ("$mode" == "check") then
  echo "All $#sources source files exist."
  exit 0
endif

which xrun >& /dev/null
if ($status != 0) then
  echo "xrun is not in PATH. Run source /home/install/cshrc first."
  exit 127
endif

set common = ( -uvm -sv -access +rwc -timescale 1ns/1ps \
  -incdir ../tb \
  $sources:q -top hdl_top -top hvl_top \
  +UVM_TESTNAME=coverage_closure_test +UVM_VERBOSITY=UVM_MEDIUM \
  -svseed 1 -xmlibdirname xcelium_uvm_local.d )
if (-f uvm_standalone.cds.lib) then
  set common = ( $common:q -cdslib ./uvm_standalone.cds.lib )
endif

if ("$mode" == "uvm") then
  xrun $common:q -covdut accelerator_top -coverage all -covoverwrite -l run_coverage_closure_test.log
  set run_status = $status
else
  xrun $common:q +WAVE_MODE -gui -input wave.tcl -l run_wave.log
  set run_status = $status
endif
exit $run_status
