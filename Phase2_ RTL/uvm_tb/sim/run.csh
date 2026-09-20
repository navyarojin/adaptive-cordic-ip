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
  ../../cordic_rtl/cordic_pkg.sv \
  ../../cordic_rtl/cordic_ashr.sv \
  ../../cordic_rtl/cordic_saturate.sv \
  ../../cordic_rtl/fx_mul_round.sv \
  ../../cordic_rtl/fx_signed_divider.sv \
  ../../cordic_rtl/cordic_atanh_rom.sv \
  ../../cordic_rtl/cordic_iter_seq_rom.sv \
  ../../controller_rtl/iteration_lut.sv \
  ../../cordic_rtl/cordic_core.sv \
  ../../controller_rtl/qualification_ctrl.sv \
  ../../apb_rtl/csr_apb.sv \
  ../../npu_rtl/zero_aware_systolic_npu.sv \
  ../../integration_rtl/activation_ip_top.sv \
  ../../integration_rtl/accelerator_top.sv \
  ../tb/activation_reference_pkg.sv \
  ../tb/if/apb_if.sv \
  ../tb/if/act_if.sv \
  ../tb/if/tcdm_if.sv \
  ../tb/activation_ip_csr_addrs_pkg.sv \
  ../tb/activation_ip_pkg.sv \
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
  -incdir ../tb/agents/apb_agent \
  -incdir ../tb/agents/act_agent \
  -incdir ../tb/env -incdir ../tb/seq_lib -incdir ../tb/tests \
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
