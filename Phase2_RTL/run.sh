#!/usr/bin/env bash
set -euo pipefail
rtl=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
action=${1:-help}
if (( $# )); then shift; fi
case "$action" in
  spi) exec bash "$rtl/spi_tb/run.sh" xrun "$@" ;;
  uvm) exec bash "$rtl/asic/uvm.sh" "$@" ;;
  wave) exec bash "$rtl/spi_tb/run.sh" wave 1 "${1:-tb_accelerator}" ;;
  asic) exec bash "$rtl/asic/run.sh" "$@" ;;
  check)
    while IFS= read -r -d '' file; do bash -n "$file"; done < <(find "$rtl" -path '*/.git' -prune -o -name '*.sh' -type f -print0)
    bash "$rtl/spi_tb/run.sh" check
    bash "$rtl/asic/uvm.sh" 1 check
    exec bash "$rtl/asic/run.sh" check
    ;;
  help|-h|--help) printf 'Usage: bash run.sh {spi [lanes] [tests...]|uvm [seed] [wave]|wave [test]|asic [stage]|check}\n' ;;
  *) echo "Unknown action: $action" >&2; exit 2 ;;
esac
