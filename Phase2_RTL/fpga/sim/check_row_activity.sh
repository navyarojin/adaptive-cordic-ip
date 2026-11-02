#!/usr/bin/env bash
set -euo pipefail
board=$(cd "$(dirname "$0")/.." && pwd)
work="$board/work_row_compare"
reports="$board/reports/row_gating_20261029/compare/mac/verilator"
scratch=$(mktemp -d /tmp/npu-row-activity.XXXXXXXX)
trap 'case "$scratch" in /tmp/npu-row-activity.*) rm -rf -- "$scratch";; esac' EXIT
mkdir -p "$reports"
cp "$board/../rtl/mac.sv" "$board/experiments/mac_row_compare.sv" "$board/experiments/tb_mac_row_compare.sv" "$scratch/"
cp "$work/acts.mem" "$work/weights.mem" "$work/bias.mem" "$work/ends.mem" "$scratch/"
printf '%s\n' 'module BUFG(input wire I,output wire O); assign O=I; endmodule' > "$scratch/clock_model.sv"
cd "$scratch"
verilator --binary --timing --assert --top-module tb_mac_row_compare -j 1 -Wno-fatal -DRTL_ACTIVITY mac.sv mac_row_compare.sv tb_mac_row_compare.sv clock_model.sv > "$reports/build.log" 2>&1
for profile in ACTUAL DENSE MASKS IDLE; do
  ./obj_dir/Vtb_mac_row_compare "+$profile" > "$reports/$profile.log" 2>&1
  grep '^PASS\|^SWITCH_ROW' "$reports/$profile.log"
done
