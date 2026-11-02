import hashlib
import json
import shutil
import zipfile
from pathlib import Path


board = Path(__file__).resolve().parents[1]
root = board.parent.parent
report = board / 'reports/row_gating_20261029'
work = board / 'work_row_compare'
inputs = report / 'inputs'
previous_archive = report / 'archived_large_inputs.json'
if previous_archive.exists():
    archived = json.loads(previous_archive.read_text())
    missing = [name for name in archived['files'] if not (report / name).exists()]
    assert not missing, 'Restore archived inputs before rebuilding the archive: ' + ', '.join(missing)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def retain(source, destination):
    if source.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    else:
        assert destination.exists(), destination


build = json.loads((report / 'build_inputs.json').read_text())
with zipfile.ZipFile(inputs / 'build_sources.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
    for name, expected in build['sha256'].items():
        path = root / name
        assert hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest() == expected
        archive.write(path, name)
with zipfile.ZipFile(inputs / 'build_sources.zip') as archive:
    assert archive.testzip() is None
    for name, expected in build['sha256'].items():
        assert hashlib.sha256(archive.read(name).replace(b'\r\n', b'\n')).hexdigest() == expected
for path in (board / 'scripts').iterdir():
    if 'row' in path.name or path.name in ['prepare_carry_reproducer.py', 'normalize_carry_ports.py']:
        retain(path, inputs / 'verification_scripts' / path.name)
for path in (board / 'sim').glob('*row*'):
    retain(path, inputs / 'verification_scripts' / path.name)
for path in board.parent.joinpath('verification').glob('*.sv'):
    retain(path, inputs / 'testbenches' / path.name)
retain(board / 'jupyter_streaming/validate.py', inputs / 'validate.py')
for name in ['acts.mem', 'weights.mem', 'bias.mem', 'ends.mem', 'mac_row_compare.sv', 'tb_mac_row_compare.sv', 'provenance.json']:
    retain(work / name, inputs / 'comparison' / name)
for name in ['legacy.sv', 'plain.sv', 'retained.sv', 'zero_hold.sv', 'zero_dual_hold.sv', 'legacy_compare.sv', 'tb_legacy_compare.sv']:
    retain(work / 'legacy' / name, inputs / 'comparison/legacy' / name)
flat = board / 'work_row_flat'
for name in ['mac_row_compare.sv', 'legacy_compare.sv', 'tb_mac_row_compare.sv', 'tb_legacy_compare.sv', 'run_all.tcl']:
    if (flat / name).exists():
        retain(flat / name, inputs / 'flat_comparison' / name)
diagnostic = report / 'compare/mac/transition_diagnostic'
for pattern in ['mac_vendor*.log', 'vendor_carry_compile.log', 'mac_transport*.log', 'carry_reproducer*.log']:
    for path in work.glob(pattern):
        retain(path, diagnostic / path.name)
retain(work / 'legacy.elaborate.log', report / 'compare/legacy/optimization_O0_cancelled.elaborate.log')
for name in ['functional.tcl', 'transition.tcl', 'carry_pins.tcl', 'carry_direct.tcl', 'carry_cell_trace.tcl']:
    retain(work / name, diagnostic / name)

paths = sorted(path for path in report.rglob('*') if path.is_file() and path.suffix.lower() in ['.v', '.sdf', '.saif', '.vcd'])
records = {path.relative_to(report).as_posix(): digest(path) for path in paths}
archive_path = report / 'comparison_activity_and_netlists.zip'
with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in paths:
        archive.write(path, path.relative_to(report).as_posix())
with zipfile.ZipFile(archive_path) as archive:
    assert archive.testzip() is None
    for name, expected in records.items():
        assert hashlib.sha256(archive.read(name)).hexdigest() == expected, name
(report / 'archived_large_inputs.json').write_text(json.dumps(dict(
    archive=archive_path.name, archive_sha256=digest(archive_path), files=records,
    restore='Extract into this report directory to restore original relative paths. Regenerate netlists for a different workspace path.'), indent=2) + '\n')
print('PASS archived and hash-verified', len(records), 'activity/netlist inputs; build sources frozen')
