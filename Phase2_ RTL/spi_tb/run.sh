#!/usr/bin/env bash
set -euo pipefail
src_name() {
  case "$1" in
    zero_aware_systolic_npu_param) echo systolic_cfg ;;
    zero_aware_systolic_npu) echo systolic ;;
    qualification_stream) echo qual_stream ;;
    qualification_ctrl) echo qual ;;
    npu_spi_top) echo spi_top ;;
    npu_spi_bridge) echo spi_bridge ;;
    mac4_stream) echo mac ;;
    iteration_lut) echo iter ;;
    hardware_command_queue) echo queue ;;
    fx_signed_divider_stream) echo div_stream ;;
    fx_signed_divider) echo div ;;
    cordic_design) echo cordic ;;
    cordic_core) echo core ;;
    cordic_activation_top) echo act_top ;;
    cordic_activation_stream) echo act_stream ;;
    activation_stream_array) echo act_array ;;
    activation_ping_pong) echo buffers ;;
    activation_ip_top) echo act_ip ;;
    accelerator_top) echo accel ;;
    stream_job_engine) echo jobs ;;
    tb_systolic_param) echo tb_systolic ;;
    tb_stream_throughput) echo tb_rate ;;
    tb_stream_learning) echo tb_learn ;;
    tb_stream_job_engine) echo tb_jobs ;;
    tb_qualification_ctrl) echo tb_qual ;;
    tb_mac4_stream) echo tb_mac ;;
    tb_divider_stream) echo tb_div_stream ;;
    tb_divider_parallel) echo tb_div ;;
    tb_cordic_core_all) echo tb_core ;;
    tb_cordic_activation_top) echo tb_act ;;
    tb_controlled_eval) echo tb_sweep ;;
    tb_command_queue) echo tb_queue ;;
    tb_activation_stream_array) echo tb_array ;;
    tb_activation_accuracy) echo tb_accuracy ;;
    tb_accelerator) echo tb_accel ;;
    tb_npu_spi) echo tb_spi ;;
    spi_host_if) echo spi_if ;;
    activation_reference_pkg) echo ref ;;
    activation_ip_pkg) echo ip_pkg ;;
    activation_ip_csr_addrs_pkg) echo csr_pkg ;;
    stream_uvm_pkg) echo uvm_pkg ;;
    tb_pynq_soc) echo tb_soc ;;
    tb_fused_layer) echo tb_fused ;;
    tb_fixed_evaluation) echo tb_fixed ;;
    tb_banknote_model) echo tb_model ;;
    tb_autonomous_model) echo tb_auto ;;
    pynq_npu_soc) echo soc ;;
    jupyter_npu) echo host ;;
    *) echo "$1" ;;
  esac
}
rtl_root=$(cd "$(dirname "$0")/.." && pwd)
mode=${1:-verilator}
lanes=${2:-1}
if [[ "$lanes" != 1 && "$lanes" != 4 && "$lanes" != 8 && "$lanes" != 16 ]]; then
  echo 'ACTIVATION_LANES must be 1, 4, 8, or 16' >&2
  exit 2
fi
if [[ "$mode" == xrun && "$lanes" != 1 ]]; then
  echo 'Use verilator for the parameterized four-lane regression' >&2
  exit 2
fi
if [[ "$mode" != verilator && "$mode" != xrun ]]; then
  echo 'Usage: bash spi_tb/run.sh [verilator|xrun]' >&2
  exit 2
fi
command -v "$mode" >/dev/null
work_dir=$(mktemp -d /tmp/npu-spi.XXXXXX)
echo "Simulation workspace: $work_dir"
mkdir -p "$rtl_root/spi_tb/results"
for dir in rtl verification; do
  mkdir -p "$work_dir/$dir"
  cp "$rtl_root/$dir/"*.sv "$work_dir/$dir/"
done
mkdir -p "$work_dir/spi_tb" "$work_dir/uvm_tb/tb"
cp "$rtl_root/spi_tb/"*.sv "$work_dir/spi_tb/"
cp "$rtl_root/uvm_tb/tb/ref.sv" "$work_dir/uvm_tb/tb/"
cd "$work_dir"
sources=(rtl/cordic_pkg.sv
  rtl/div.sv rtl/div_stream.sv rtl/act_stream.sv
   rtl/iter.sv
  rtl/core.sv rtl/qual.sv rtl/qual_stream.sv
  rtl/csr_apb.sv rtl/systolic_cfg.sv rtl/mac.sv rtl/systolic.sv
  rtl/act_ip.sv rtl/act_array.sv
  rtl/queue.sv rtl/buffers.sv
  rtl/jobs.sv rtl/accel.sv
  rtl/spi_bridge.sv rtl/spi_top.sv
  uvm_tb/tb/ref.sv spi_tb/spi_if.sv)
for top in ${3:-tb_spi_bridge tb_npu_spi tb_accelerator}; do
  generics=()
  [[ "$top" != tb_spi_bridge && "$top" != tb_divider_parallel && "$top" != tb_divider_stream && "$top" != tb_cordic_stream && "$top" != tb_cordic_core_all && "$top" != tb_systolic_param ]] && generics=(-GACTIVATION_LANES="$lanes")
  test_file="spi_tb/tb_spi.sv"
  if [[ "$top" == tb_command_queue ]]; then
    generics=()
    test_file="verification/$(src_name "$top").sv"
  fi
  if [[ "$top" == tb_stream_learning ]]; then
    generics=()
    test_file="verification/$(src_name "$top").sv"
  fi
  [[ "$top" == tb_accelerator || "$top" == tb_activation_accuracy || "$top" == tb_activation_stream_array || "$top" == tb_stream_job_engine || "$top" == tb_stream_throughput ]] && test_file="verification/$(src_name "$top").sv"
  [[ "$top" == tb_divider_parallel || "$top" == tb_divider_stream || "$top" == tb_cordic_stream || "$top" == tb_cordic_core_all ]] && test_file="verification/$(src_name "$top").sv"
  [[ "$top" == tb_systolic_param ]] && test_file="verification/$(src_name "$top").sv"
  log_root="$rtl_root/spi_tb/results/${top}_lanes${lanes}"
  if [[ "$mode" == verilator ]]; then
    if ! verilator --binary --timing --assert "${generics[@]}" -Wno-fatal -j 2 --Mdir "obj_$top" \
      --top-module "$top" "${sources[@]}" "$test_file" >"$log_root.build.log" 2>&1; then
      tail -n 60 "$log_root.build.log"
      exit 1
    fi
    "obj_$top/V$top" | tee "$log_root.run.log"
  else
    xrun -sv -timescale 1ns/1ps "${sources[@]}" "$test_file" -top "$top" \
      -xmlibdirname "xcelium_$top.d" -l "$log_root.run.log"
  fi
done
