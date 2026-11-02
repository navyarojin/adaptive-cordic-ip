# PYNQ runtime source

This directory contains the runtime, validation and benchmark scripts, notebooks,
and classifier model for the four-lane PYNQ-Z2 accelerator.

Before deployment, build and export matching board.bit and board.hwh using the
FPGA scripts, and place them in this directory. Prebuilt images and run manifests
are excluded from this source repository.

Upload the runtime and rebuilt overlay together. On the board, source
/etc/profile.d/xrt_setup.sh and /etc/profile.d/boardname.sh, then use the PYNQ
Python environment with hardware privileges:

```bash
python validate.py --runs 100 --model-runs 20 --output board_validation.json
python bench.py --autonomous --runs 100 --profiles 5 --output banknote_autonomous_results.json
python bench.py --runs 100 --profiles 5 --output banknote_host_chained_results.json
```

Keep clocks running during reset and hold reset for at least eight cycles.
