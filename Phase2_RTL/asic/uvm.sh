#!/usr/bin/env bash

set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
seed=${1:-1}
mode=${2:-batch}
if [[ "$seed" == check ]]; then seed=1; mode=check; fi
case "$mode" in batch|wave|check) ;; *) echo "Usage: bash uvm.sh [seed] [batch|wave|check]" >&2; exit 2 ;; esac
[[ "$seed" =~ ^[0-9]+$ ]] || { echo 'Seed must be numeric'; exit 2; }
out="$root/asic/reports/xcelium_seed_$seed"
sources=()
while IFS= read -r source || [[ -n "$source" ]]; do
  source=${source%$'\r'}
  [[ -z "$source" ]] || sources+=("$root/$source")
done < "$root/asic/verification.f"
sources+=("$root/uvm_tb/tb/ref.sv" "$root/asic/uvm/stream_if.sv"
  "$root/asic/uvm/uvm_pkg.sv" "$root/asic/uvm/stream_top.sv")
for source in "${sources[@]}" "$root/evaluation/data/model.mem" "$root/evaluation/data/inputs.mem"; do
  [[ -f "$source" ]] || { echo "Missing source/data: $source" >&2; exit 2; }
done
if [[ "$mode" == check ]]; then echo 'PASS streaming UVM source/data paths'; exit 0; fi
command -v xrun >/dev/null || { echo 'Cadence Xcelium xrun is not on PATH; load the lab environment first' >&2; exit 127; }
mkdir -p "$out"
cp "$root/evaluation/data/"{model,inputs}.mem "$out/"
cd "$out"
xrun -version > tool_version.log
gui=()
if [[ "$mode" == wave ]]; then
  printf 'database -open waves -into waves.shm -default\nprobe -create stream_top -shm -all -depth all\n' > wave.tcl
  gui=(-gui -input wave.tcl)
fi
xrun -64bit -uvm -sv -access +rwc -timescale 1ns/1ps "${gui[@]}" \
  -top stream_top -svseed "$seed" -coverage all -covdut stream_mmio \
  -covoverwrite -xmlibdirname xcelium.d -l uvm.log "${sources[@]}"
if [[ "$mode" == wave ]]; then exit 0; fi
if ! grep -q 'PASS stream_model_test' uvm.log; then echo 'FAIL: missing UVM completion marker; inspect uvm.log' >&2; exit 1; fi
if grep -Eq '(UVM_ERROR|UVM_FATAL)[[:space:]]+@|(UVM_ERROR|UVM_FATAL)[[:space:]]*:[[:space:]]*[1-9]|\*[EF],' uvm.log; then
  echo 'FAIL: inspect uvm.log'; exit 1
fi
echo "PASS seed=$seed; retain coverage database and review closure in Cadence IMC"
