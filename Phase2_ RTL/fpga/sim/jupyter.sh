#!/usr/bin/env bash
set -euo pipefail
board=$(cd "$(dirname "$0")/.." && pwd)
lanes=${1:-4}
if [[ "$lanes" != 1 && "$lanes" != 4 ]]; then
  echo 'ACTIVATION_LANES must be 1 or 4' >&2
  exit 2
fi
result="$board/sim/results_jupyter_lanes${lanes}"
mkdir -p "$result"
bash "$board/firmware/build.sh" jupyter
work=$(mktemp -d /tmp/pynq-jupyter.XXXXXX)
python3 "$board/scripts/sources.py" "$work"
cp "$board/firmware/build_jupyter/firmware.mem" "$work/firmware.mem"
cp "$board/sim/tb_jupyter.sv" "$board/sim/verilator.vlt" "$work/"
cp "$board/../uvm_tb/tb/ref.sv" "$work/"
cd "$work"
if ! verilator --binary --timing --assert -GACTIVATION_LANES="$lanes" -Wno-fatal -j 2 \
  -Ifpga/rtl --top-module tb_jupyter \
  verilator.vlt -f sources.f ref.sv tb_jupyter.sv \
  > "$result/build.log" 2>&1; then
  tail -n 60 "$result/build.log"
  exit 1
fi
./obj_dir/Vtb_jupyter | tee "$result/run.log"
