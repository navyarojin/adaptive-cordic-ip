import hashlib
import json
import re
import shutil
from pathlib import Path


board = Path(__file__).resolve().parents[1]
root = board.parent.parent
report = board / 'reports/row_gating_20261029'
external = Path('C:/Users/pc/.codex/visualizations/2026/10/27/01a17b06-e973-7dd1-a2b4-f919223014ec')


def digest(path):
    if path.exists():
        return hashlib.sha256(path.read_bytes()).hexdigest()
    import zipfile
    record=json.loads((report / 'archived_large_inputs.json').read_text())
    key=path.relative_to(report).as_posix()
    with zipfile.ZipFile(report / record['archive']) as archive:
        value=hashlib.sha256(archive.read(key)).hexdigest()
    assert value == record['files'][key]
    return value


def load(name):
    return json.loads((report / name).read_text())


def text(path):
    return path.read_text(errors='replace')


def retain(source, destination):
    if source.exists():
        shutil.copy2(source, destination)
    else:
        assert destination.exists(), destination


def timing(path):
    match = re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+\d+\s+([-\d.]+)\s+([-\d.]+)\s+(\d+)', text(path), re.S)
    assert match, path
    setup, tns, setup_bad, hold, ths, hold_bad = match.groups()
    assert int(setup_bad) == int(hold_bad) == 0, path
    return dict(setup_slack_ns=float(setup), hold_slack_ns=float(hold),
                setup_failing_endpoints=int(setup_bad), hold_failing_endpoints=int(hold_bad))


def field(contents, label):
    match = re.search(r'^\|\s*' + re.escape(label) + r'\s*\|\s*([^|]+)', contents, re.M)
    assert match, label
    return match.group(1).strip()


def require_pass(path, marker):
    contents = text(path)
    assert marker in contents, path
    assert not re.search(r'Fatal:|Error:|[Tt]iming violation', contents), path


validation = load('board_validation.json')
assert validation['status'] == 'passed'
assert validation['execution'] == 'physical_pynq'
assert validation['row_gating']['checked_outputs'] == 4096
assert len(validation['row_gating']['cases']) == 64
assert all(case['passed'] for case in validation['row_gating']['cases'])
candidate = report / 'candidate'
for name, expected in validation['hashes'].items():
    assert digest(candidate / name) == expected, name
inputs = load('build_inputs.json')
for name, expected in inputs['sha256'].items():
    assert hashlib.sha256((root / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest() == expected, name

for name in ['row_gating_build.log', 'row_compare_build_corrected.log', 'row_gating_board.log', 'row_gating_dma.log', 'row_compare_exports.log', 'row_activity_checked.log', 'row_activity_verilator.log', 'row_activity_map.log', 'row_compare_power_rtl_mapped.log']:
    retain(external / name, report / name)
require_pass(report / 'row_gating_build.log', 'PASS engineering audit:')
require_pass(report / 'row_gating_dma.log', 'PASS row-gating vendor AXI DMA regression')
require_pass(report / 'row_compare_exports.log', 'PASS physical MAC register enables: 894 nonconstant enables among 911 registers')
require_pass(report / 'row_compare_build_corrected.log', 'PASS routed common-clock comparisons')
require_pass(report / 'row_gating_mac.log', 'PASS MAC4: 6892')
require_pass(report / 'row_gating_system.log', 'PASS')
assert 'Ran 35 tests' in text(report / 'python_tests.log')
rtl_logs = list((report / 'rtl_regression').glob('*.run.log'))
assert len(rtl_logs) == 12
for path in rtl_logs:
    if path.name == 'tb_stream_throughput.run.log':
        for marker in ['STREAM_THROUGHPUT,4,0,2048,102,2116,2218',
                       'STREAM_THROUGHPUT,4,32,2048,102,2368,2470',
                       'STREAM_THROUGHPUT,4,1,2048,107,10236,10343']:
            require_pass(path, marker)
    else:
        require_pass(path, 'PASS')
assert re.search(r'Violations found:\s+0', text(report / 'methodology.rpt'))

comparison = report / 'compare'
work = board / 'work_row_compare'
legacy_attempt = comparison / 'legacy/optimization_O2_attempt'
legacy_failure = text(legacy_attempt / 'legacy_case4.log')
assert re.search(r'Fatal: Variant=\s+1 row=\s+0 got=\s+75061 expected=\s+9525', legacy_failure)
mac_attempt = comparison / 'mac/optimization_O0_attempt'
assert 'Fatal: MAC timing mismatch profile=0 variant=0 item=288 row=3 got=-262144 expected=-8386' in text(mac_attempt / 'run.log')
for kind, attempt in [('mac', mac_attempt), ('legacy', legacy_attempt)]:
    annotation = text(attempt / f'{kind}.elaborate.log')
    assert annotation.count('SDF backannotation was successful') == 1
    assert not re.search(r'ERROR:|WARNING:', annotation)
    timing(comparison / kind / 'timing.rpt')
for profile in ['actual', 'dense', 'masks', 'idle']:
    require_pass(comparison / 'mac' / f'rtl_{profile}' / 'run.log', 'PASS MAC_ROW_COMPARE')
    require_pass(comparison / 'mac/verilator' / f'{profile.upper()}.log', 'PASS MAC_ROW_COMPARE')
switching = load('compare/rtl_switching.json')
assert switching['simulators_agree']
power = load('compare/rtl_power.json')
require_pass(report / 'row_compare_power_rtl_mapped.log', 'PASS matched MAC estimates using checked RTL activity')

diagnostic = comparison / 'mac/transition_diagnostic'
for name in ['mac_functional_compile.log', 'mac_functional_elaborate.log', 'mac_functional_actual.log']:
    retain(work / name, diagnostic / name)
require_pass(diagnostic / 'mac_functional_actual.log', 'PASS MAC_ROW_COMPARE profile=0 accepted=574')
for profile in ['DENSE', 'MASKS', 'IDLE']:
    retain(work / f'mac_functional_{profile}.log', diagnostic / f'mac_functional_{profile}.log')
    require_pass(diagnostic / f'mac_functional_{profile}.log', 'PASS MAC_ROW_COMPARE')

util = text(report / 'utilization.rpt')
resources = dict(lut=int(field(util, 'Slice LUTs')), ff=int(field(util, 'Slice Registers')),
                 bram_tiles=float(field(util, 'Block RAM Tile')), dsp=int(field(util, 'DSPs')))
control_sets = int(field(text(report / 'control_sets.rpt'), 'Total control sets'))
benchmarks = {}
for mode in ['autonomous', 'host_chained']:
    baseline = load(f'baseline_{mode}.json')
    measured = load(f'banknote_{mode}_results.json')
    assert measured['runs'] == 100 and measured['diagnostic_passes'] == 5
    assert abs(measured['hardware_accuracy'] - 266 / 271) < 1e-12
    assert measured['samples_per_run'] == 271
    counters = {}
    for count in [64, 15]:
        before = [row for row in baseline['hardware_counters'] if row['vectors'] == count]
        after = [row for row in measured['hardware_counters'] if row['vectors'] == count]
        first_before = sorted({row['first_input_to_first_output'] for row in before})
        first_after = sorted({row['first_input_to_first_output'] for row in after})
        assert first_before == first_after, (mode, count, first_before, first_after)
        counters[count] = dict(first_output_cycles=first_after,
                               baseline_last_output_cycles=sorted({row['first_input_to_last_output'] for row in before}),
                               candidate_last_output_cycles=sorted({row['first_input_to_last_output'] for row in after}))
    benchmarks[mode] = dict(baseline_us=baseline['hardware_workflow_us'],
                            candidate_us=measured['hardware_workflow_us'],
                            accuracy=measured['hardware_accuracy'],
                            runs=100, samples_per_run=271, counter_comparison=counters,
                            latency_claim='First-output cycle counts unchanged. Completion spans can include DMA stalls; host timings include software and operating-system variation.')

summary = dict(status='hardware_passed_comparison_limited', scope='Built, routed, STA checked and physically validated PYNQ-Z2 deployment. Native SDF switching comparison remains unsuccessful and is excluded from power analysis.',
               clock_mhz=25, lanes=4, resources=resources, control_sets=control_sets,
               timing=timing(report / 'timing.rpt'),
               target_checks=dict(REQP_1839=0, LUTAR_1=0, DPIR_1=0, ULMTCS_1=0),
               physical_row_mask_cases=64, physical_row_mask_outputs=4096,
               classifier_correct=266, classifier_total=271, benchmarks=benchmarks,
               tests=dict(rtl_tops=13, python_tests=35, cpu_reset_and_model='passed',
                          vendor_dma='passed', mapped_mac_functional_profiles=4,
                          rtl_activity_profiles_per_simulator=4,
                          mac_sdf='failed_at_item_288_row_3',
                          legacy_sdf='original_case4_failure_reproduced'),
               switching=switching, preliminary_mac_power=power,
               physical_power=dict(status='not_measured', reason='No external meter available.'),
               board_hashes=validation['hashes'],
               build_inputs_sha256=digest(report / 'build_inputs.json'))
flat = report / 'flat_compare'
flat_logs = [flat / 'mac' / f'{name}.log' for name in ['actual', 'dense', 'masks', 'idle']]
flat_logs += [flat / 'legacy/case_4.log', flat / 'legacy/all.log']
if all(path.exists() for path in flat_logs[:4]):
    flat_row_checks = 0
    for path in flat_logs[:4]:
        require_pass(path, 'PASS MAC_ROW_COMPARE')
        counts = re.search(r'^PASS MAC_ROW_COMPARE profile=(\d+) accepted=(\d+) checked_rows=(\d+) cycles=(\d+)', text(path), re.M)
        assert counts and int(counts[3]) == int(counts[2]) * 8
        flat_row_checks += int(counts[3])
    assert flat_row_checks == 13552
    require_pass(flat_logs[4], 'PASS isolation: jobs=64 checked_rows_across_variants=1280 latency_min=8 latency_max=8 case=4')
    for kind in ['mac', 'legacy']:
        annotation = text(flat / kind / 'elaborate.log')
        assert annotation.count('SDF backannotation was successful') == 1
        assert not re.search(r'ERROR:|WARNING:', annotation)
    for name in ['row_flat_build.log', 'row_flat_mac_sdf.log', 'row_flat_legacy_sdf.log']:
        retain(external / name, report / name)
    summary['status'] = 'classifier_flow_passed_legacy_sdf_limited'
    summary['scope'] = 'Classifier implementation built, routed, STA checked, physically validated and passing all four flattened native-SDF MAC profiles. Extended legacy prototype comparison remains limited.'
    summary['tests']['flattened_mac_sdf_profiles'] = 4
    summary['tests']['flattened_mac_sdf_checked_rows'] = flat_row_checks
    summary['tests']['flattened_legacy_case4_jobs'] = 64
    summary['tests']['flattened_legacy_case4_row_checks'] = 1280
    summary['flattened_comparison_timing'] = {kind: timing(flat / kind / 'timing.rpt') for kind in ['mac', 'legacy']}
    full_pass = 'PASS isolation: jobs=653 checked_rows_across_variants=13060 latency_min=8 latency_max=8 case=-1'
    if full_pass in text(flat_logs[5]):
        require_pass(flat_logs[5], full_pass)
        summary['status'] = 'hardware_and_flat_sdf_passed'
        summary['tests']['flattened_legacy_sdf_jobs'] = 653
        summary['tests']['flattened_legacy_sdf_row_checks'] = 13060
        summary['comparison_status'] = 'Flattened native-SDF classifier and legacy comparisons pass. Original hierarchical replay failures remain documented; power estimates use independently checked RTL activity.'
    else:
        assert re.search(r'Fatal: Variant=\s+2 row=\s+3 got=\s+222135 expected=\s+25527', text(flat_logs[5]))
        summary['tests']['flattened_legacy_full_sdf'] = 'failed_changing_weight_case5_retention_control_variant2_row3'
        summary['comparison_status'] = 'All four classifier MAC SDF profiles and the original legacy case4 pass with flattened native exports. Combined legacy stress still fails in the non-production retention-control variant in case5. Power estimates use independently checked RTL activity.'
        standalone = flat / 'legacy/case_5_diagnostic.log'
        assert re.search(r'Fatal: Variant=\s+2 row=\s+3 got=\s+222135 expected=\s+25527', text(standalone))
        summary['tests']['flattened_legacy_case5_independent'] = 'same_variant2_failure_at_1360ns'
else:
    summary['comparison_status'] = 'Independent RTL switching agreement obtained. Native hierarchical SDF replay still fails; its traces are excluded from power estimation.'
aliases = flat / 'legacy/bus_ports'
audit = json.loads((aliases / 'connection_audit.json').read_text())
assert audit['inverse_transform_recovers_original']
assert audit['carry_instances'] == 1417 and audit['aliases'] == 2834
assert digest(flat / 'legacy/timing.sdf') == audit['unchanged_native_sdf_sha256']
assert digest(flat / 'legacy/timing.v') == audit['original_netlist_sha256']
assert digest(aliases / 'timing.v') == audit['normalized_netlist_sha256']
annotation = text(aliases / 'elaborate.log')
assert annotation.count('SDF backannotation was successful') == 1
assert not re.search(r'ERROR:|WARNING:', annotation)
require_pass(aliases / 'case_5.log', 'PASS isolation: jobs=64 checked_rows_across_variants=1280 latency_min=8 latency_max=8 case=5')
require_pass(aliases / 'all.log', 'PASS isolation: jobs=653 checked_rows_across_variants=13060 latency_min=8 latency_max=8 case=-1')
reconnect = load('board_reconnect_20261031.json')
assert reconnect['status'] == 'passed' and reconnect['execution'] == 'physical_pynq'
assert reconnect['hashes'] == validation['hashes']
assert reconnect['row_gating']['checked_outputs'] == 4096
retain(external / 'row_gating_reconnect.log', report / 'row_gating_reconnect.log')
summary['status'] = 'fpga_flow_complete_with_simulation_workaround'
summary['scope'] = 'Classifier built, routed, STA checked, physically validated twice and passing all four native-SDF MAC profiles. Legacy comparison also passes its full corpus using audited simulation-only identity wire aliases.'
summary['tests']['legacy_sdf_with_identity_aliases'] = dict(jobs=653, checked_rows=13060, latency_cycles=8, standalone_case5_jobs=64)
summary['comparison_status'] = 'Classifier MAC native-SDF profiles pass. Legacy full native-SDF replay passes after reversible identity-wire normalization of CARRY4 output connections; original SDF bytes, primitive logic and timing checks are preserved. Historical failed runs remain archived.'
summary['reconnected_board_validation'] = dict(file='board_reconnect_20261031.json', status='passed', completed_utc=reconnect['completed_utc'], checked_row_mask_outputs=4096)
summary['historical_diagnostics'] = {key: summary['tests'].pop(key) for key in ['mac_sdf', 'legacy_sdf', 'flattened_legacy_full_sdf', 'flattened_legacy_case5_independent'] if key in summary['tests']}
publication = load('publication_verified.json')
assert publication['status'] == 'passed'
assert publication['manifest_sha256'] == digest(board / 'jupyter_streaming/manifest.json')
assert publication['files'] == json.loads((board / 'jupyter_streaming/manifest.json').read_text())['files']
summary['final_board_publication'] = dict(status='passed', verified_utc=publication['verified_utc'], manifest_sha256=publication['manifest_sha256'])
(report / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print('PASS row-gating evidence and deployment hashes verified')
