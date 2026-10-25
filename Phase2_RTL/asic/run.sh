#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
interpreter=${TCLSH:-tclsh}
command -v "$interpreter" >/dev/null || { echo 'Tcl interpreter is not on PATH; load Tcl/Cadence tools or set TCLSH' >&2; exit 127; }
exec "$interpreter" "$here/flow/flow.tcl" "$@"
