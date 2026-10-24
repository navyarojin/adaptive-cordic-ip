#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out="$here/build"
extra=()
if [[ "${1:-}" == jupyter ]]; then
  out="$here/build_jupyter"
  extra=(-DJUPYTER)
elif [[ "${1:-}" == streaming ]]; then
  out="$here/build_streaming"
  extra=(-DJUPYTER -DSTREAMING)
elif [[ $# -ne 0 ]]; then
  exit 2
fi
mkdir -p "$out"
prefix=${CROSS_COMPILE:-riscv64-unknown-elf-}
python3 "$here/../scripts/gen_vectors.py" "$out/golden.h"
"${prefix}gcc" -march=rv32imc_zicsr -mabi=ilp32 -O2 -g -ffreestanding \
  -fno-builtin -fno-common -msmall-data-limit=0 -nostdlib -nostartfiles \
  -Wall -Wextra -Werror "${extra[@]}" -I"$out" -T "$here/link.ld" \
  -Wl,-Map,"$out/firmware.map" -o "$out/firmware.elf" "$here/start.S" "$here/main.c"
"${prefix}objcopy" -O binary "$out/firmware.elf" "$out/firmware.bin"
"${prefix}objdump" -d "$out/firmware.elf" > "$out/firmware.dis"
"${prefix}size" "$out/firmware.elf"
python3 "$here/../scripts/mem.py" "$out/firmware.bin" "$out/firmware.mem"
