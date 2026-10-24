#!/usr/bin/env bash

set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
seed=${1:-1}
[[ "$seed" =~ ^[0-9]+$ ]] || { echo 'Seed must be numeric'; exit 2; }
command -v xrun >/dev/null || { echo 'Cadence Xcelium xrun is not on PATH'; exit 2; }
out="$root/asic/reports/xcelium_seed_$seed"
mkdir -p "$out"
sources=()
while IFS= read -r source || [[ -n "$source" ]]; do
  source=${source%$'\r'}
  [[ -z "$source" ]] || sources+=("$root/$source")
done < "$root/asic/verification.f"
sources+=("$root/uvm_tb/tb/ref.sv" "$root/asic/uvm/stream_if.sv"
  "$root/asic/uvm/uvm_pkg.sv" "$root/asic/uvm/stream_top.sv")
cp "$root/evaluation/data/"{model,inputs}.mem "$out/"
cd "$out"
xrun -version > tool_version.log
xrun -64bit -uvm -sv -access +rwc -timescale 1ns/1ps \
  -top stream_top -svseed "$seed" -coverage all -covdut stream_mmio \
  -covoverwrite -xmlibdirname xcelium.d -l uvm.log "${sources[@]}"
grep -q 'PASS stream_model_test' uvm.log
if grep -Eq '(UVM_ERROR|UVM_FATAL)[[:space:]]+@|\*[EF],' uvm.log; then
  echo 'FAIL: inspect uvm.log'; exit 1
fi
echo "PASS seed=$seed; retain coverage database and review closure in Cadence IMC"
