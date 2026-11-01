#!/usr/bin/env bash
set -euo pipefail
rtl_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-verilator}
lanes=${2:-1}
case "$mode" in
  verilator|xrun|wave|check) ;;
  *) echo 'Usage: bash run.sh [verilator|xrun|wave|check] [1|4|8|16] [tests...]' >&2; exit 2 ;;
esac
case "$lanes" in 1|4|8|16) ;; *) echo 'Lanes must be 1, 4, 8, or 16' >&2; exit 2 ;; esac
if (( $# > 2 )); then
  shift 2
  read -r -a tests <<< "$*"
else
  tests=(tb_spi_bridge tb_npu_spi tb_accelerator)
fi
sources=()
while IFS= read -r source || [[ -n "$source" ]]; do
  source=${source%$'\r'}
  [[ -z "$source" ]] || sources+=("$source")
done < "$rtl_root/rtl/sources.f"
sources+=(rtl/act_top.sv uvm_tb/tb/ref.sv spi_tb/spi_if.sv)
test_file() {
  case "$1" in
    tb_spi_bridge|tb_npu_spi) echo spi_tb/tb_spi.sv ;;
    tb_accelerator) echo verification/tb_accel.sv ;;
    tb_activation_accuracy) echo verification/tb_accuracy.sv ;;
    tb_activation_stream_array) echo verification/tb_array.sv ;;
    tb_stream_job_engine) echo verification/tb_jobs.sv ;;
    tb_stream_throughput) echo verification/tb_rate.sv ;;
    tb_stream_learning) echo verification/tb_learn.sv ;;
    tb_command_queue) echo verification/tb_queue.sv ;;
    tb_systolic_param) echo verification/tb_systolic.sv ;;
    tb_mac4_stream) echo verification/tb_mac.sv ;;
    tb_divider_parallel) echo verification/tb_div.sv ;;
    tb_divider_stream) echo verification/tb_div_stream.sv ;;
    tb_cordic_stream) echo verification/tb_cordic_stream.sv ;;
    tb_cordic_core_all) echo verification/tb_core.sv ;;
    tb_cordic_activation_top) echo verification/tb_act.sv ;;
    tb_qualification_ctrl) echo verification/tb_qual.sv ;;
    tb_fused_layer) echo fpga/sim/tb_fused.sv ;;
    *) echo "Unsupported testbench: $1" >&2; return 2 ;;
  esac
}
test_sources=()
for top in "${tests[@]}"; do test_sources+=("$(test_file "$top")"); done
for source in "${sources[@]}" "${test_sources[@]}"; do
  [[ -f "$rtl_root/$source" ]] || { echo "Missing source: $rtl_root/$source" >&2; exit 2; }
done
if [[ "$mode" == check ]]; then echo 'PASS SPI/accelerator source paths'; exit 0; fi
tool=$mode
[[ "$mode" != wave ]] || tool=xrun
command -v "$tool" >/dev/null || { echo "$tool is not on PATH; load the tool environment first" >&2; exit 127; }
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/npu-spi.XXXXXX")
echo "Simulation workspace: $work_dir"
mkdir -p "$rtl_root/spi_tb/results"
for source in "${sources[@]}" "${test_sources[@]}"; do
  mkdir -p "$work_dir/$(dirname "$source")"
  cp "$rtl_root/$source" "$work_dir/$source"
done
cd "$work_dir"
for index in "${!tests[@]}"; do
  top=${tests[$index]}
  generics=()
  case "$top" in
    tb_npu_spi|tb_accelerator|tb_activation_accuracy)
      if [[ "$tool" == verilator ]]; then generics=(-GACTIVATION_LANES="$lanes")
      else generics=(-defparam "$top.ACTIVATION_LANES=$lanes"); fi ;;
  esac
  log_root="$rtl_root/spi_tb/results/${top}_lanes${lanes}"
  if [[ "$tool" == verilator ]]; then
    if ! verilator --binary --timing --assert "${generics[@]}" -Wno-fatal -j 2 --Mdir "obj_$top" \
      --top-module "$top" "${sources[@]}" "${test_sources[$index]}" >"$log_root.build.log" 2>&1; then
      tail -n 60 "$log_root.build.log"; exit 1
    fi
    "obj_$top/V$top" | tee "$log_root.run.log"
  else
    gui=()
    if [[ "$mode" == wave ]]; then
      printf 'database -open waves -into waves.shm -default\nprobe -create %s -shm -all -depth all\n' "$top" > wave.tcl
      gui=(-gui -input wave.tcl)
    fi
    xrun -64bit -sv -access +rwc -timescale 1ns/1ps "${generics[@]}" "${gui[@]}" \
      "${sources[@]}" "${test_sources[$index]}" -top "$top" -xmlibdirname "xcelium_$top.d" -l "$log_root.run.log"
  fi
  if [[ "$mode" != wave ]]; then
    if ! grep -Eq 'PASS|STREAM_THROUGHPUT,' "$log_root.run.log" || grep -Eq '\*[EF],|(^|[[:space:]])(FATAL|Fatal:|Error:)' "$log_root.run.log"; then
      echo "FAIL: inspect $log_root.run.log" >&2; exit 1
    fi
  fi
done
