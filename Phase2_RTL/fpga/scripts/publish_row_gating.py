import hashlib
import json
import shutil
import zipfile
from datetime import datetime, timezone
from pathlib import Path


board = Path(__file__).resolve().parents[1]
root = board.parent.parent
report = board / 'reports/row_gating_20261029'
bundle = board / 'jupyter_streaming'
candidate = report / 'candidate'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


summary = json.loads((report / 'summary.json').read_text())
assert summary['status'] == 'fpga_flow_complete_with_simulation_workaround'
assert (report / 'REVIEW.md').is_file()
for name, expected in summary['board_hashes'].items():
    assert digest(candidate / name) == expected, name
for name in ['board.bit', 'board.hwh']:
    shutil.copy2(candidate / name, bundle / name)
for name, expected in summary['board_hashes'].items():
    assert digest(bundle / name) == expected, name
inputs = json.loads((report / 'build_inputs.json').read_text())
manifest = dict(build_date='2026-10-29', packaged_utc=datetime.now(timezone.utc).isoformat(),
                tool='Vivado 2023.2', part='xc7z020clg400-1', clock_mhz=25, lanes=4,
                capability_register='0x00010007', board_execution_verified=True,
                board_verification_basis='Physical PYNQ-Z2 validation, all row masks, activation policies and both fixed14 classifier workflows. Exact overlay/runtime SHA256 values match board_validation.json.',
                architecture='Cached per-layer zero-weight row masks, bias bypass, valid-aware MAC payload register enables; no new gated clock.',
                file_hash_normalization='raw bytes',
                files={p.name: digest(p) for p in sorted(bundle.iterdir()) if p.is_file() and p.name != 'manifest.json'},
                rtl_hash_normalization='LF',
                rtl_source_sha256={k: v for k, v in inputs['sha256'].items() if k.endswith(('.sv', '.v'))},
                firmware_mem_sha256=inputs['sha256']['Phase2_RTL/fpga/firmware/build_streaming/firmware.mem'],
                build_inputs='Phase2_RTL/fpga/reports/row_gating_20261029/build_inputs.json',
                implementation_evidence='Phase2_RTL/fpga/reports/row_gating_20261029/summary.json',
                physical_power_measurement='not_measured_no_external_meter',
                historical_comment_cleanup='comment_cleanup.json describes an earlier deployment; current functional changes were rebuilt and physically validated.')
manifest['comparison_status']=summary['comparison_status']
manifest['verification_status']=summary['status']
manifest['board_verification_utc']=summary['reconnected_board_validation']['completed_utc']
(bundle / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
shutil.copy2(bundle / 'README.md', candidate / 'README.md')
shutil.copy2(bundle / 'manifest.json', candidate / 'manifest.json')
archive = root / 'output/fpga/NPU_PYNQ_row_gating_20261029.zip'
archive.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted(bundle.iterdir()):
        if path.is_file():
            z.write(path, path.name)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name, expected in manifest['files'].items():
        assert hashlib.sha256(z.read(name)).hexdigest() == expected, name
record = dict(archive=str(archive.relative_to(root)), archive_sha256=digest(archive),
              manifest_sha256=digest(bundle / 'manifest.json'),
              board_hashes=summary['board_hashes'], zip_verified=True)
(report / 'package.json').write_text(json.dumps(record, indent=2) + '\n')
print('PASS published package matches physically validated overlay and runtime:', archive)
