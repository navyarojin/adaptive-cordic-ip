import argparse
import csv
import hashlib
import json
import re
import shutil
import zipfile
from pathlib import Path


VARIANTS = ['legacy', 'plain', 'retained', 'isolated', 'dual']
LABELS = ['Old force-zero isolation', 'Ungated', 'Ungated with data retention',
          'Activation hold with zero flag', 'Dual-operand hold']
TIMING_CASES = range(4)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table_value(text, label):
    match = re.search(r'^\|\s*' + re.escape(label) + r'\s*\|\s*([^|]+)', text, re.M)
    if not match:
        raise ValueError(f'Missing report field: {label}')
    return match.group(1).strip()


def net_activity(path):
    totals = {name: dict(transitions=0, net_bits=0) for name in VARIANTS}
    current = None
    in_nets = False
    with path.open() as handle:
        for line in handle:
            instance = re.match(r'^      \(INSTANCE\s+(\w+)\s*$', line)
            if instance:
                current = instance.group(1) if instance.group(1) in totals else None
                in_nets = False
            if current and re.match(r'^         \(NET\s*$', line):
                in_nets = True
            elif in_nets and re.match(r'^         \)\s*$', line):
                in_nets = False
            elif current and in_nets:
                match = re.search(r'\(TC (\d+)\)', line)
                if match:
                    totals[current]['transitions'] += int(match.group(1))
                    totals[current]['net_bits'] += 1
    assert min(value['net_bits'] for value in totals.values()) > 1000
    return totals


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    board = Path(__file__).resolve().parents[1]
    report = board / 'reports/isolation_hold_20261028'
    inputs = report / 'inputs'
    inputs.mkdir(exist_ok=True)
    for name in ['legacy.sv', 'plain.sv', 'retained.sv', 'zero_hold.sv',
                 'zero_dual_hold.sv', 'tb_isolation.sv', 'isolation_monitors.svh',
                 'tb_hold_sizes.sv', 'tb_dual_sizes.sv', 'provenance.json']:
        shutil.copy2(work / name, inputs / name)
    for name in ['run.log', 'phy_directed.log', 'phy_elaborate.log',
                 'tb_hold_sizes.run.log', 'tb_dual_sizes.run.log']:
        shutil.copy2(work / name, report / name)
    rtl = (work / 'run.log').read_text(errors='replace')
    phy = (work / 'phy_directed.log').read_text(errors='replace')
    expected_pass = 'PASS isolation: jobs=4397 checked_rows_across_variants=87940 latency_min=8 latency_max=8 case=-1'
    assert expected_pass in rtl
    assert 'PASS isolation: jobs=141 checked_rows_across_variants=2820 latency_min=8 latency_max=8 case=8' in phy
    assert len(re.findall('SDF backannotation was successful', (work / 'phy_elaborate.log').read_text(errors='replace'))) == 1
    annotation_cells = json.loads((work / 'netlists/annotation_cells.json').read_text(encoding='utf-8-sig'))
    assert set(annotation_cells) == set(VARIANTS) and min(annotation_cells.values()) > 2000
    combined_sdf = (work / 'netlists/all.sdf').read_text()
    for variant, count in annotation_cells.items():
        assert len(re.findall(r'\(INSTANCE\s+' + variant + r'(?:/|\))', combined_sdf)) == count
    shutil.copy2(work / 'netlists/annotation_cells.json', report / 'annotation_cells.json')
    for log in [rtl, phy]:
        assert not re.search(r'Fatal:|Error:|[Tt]iming violation', log)
    for name in ['hold', 'dual']:
        text = (work / f'tb_{name}_sizes.run.log').read_text(errors='replace')
        for n, count in [(4, 480), (8, 960), (16, 1920)]:
            assert f'PASS systolic N={n} checks={count} measured latency={n*2}' in text
    provenance = json.loads((work / 'provenance.json').read_text())
    production = board.parent / 'rtl/systolic_cfg.sv'
    assert digest(production) == provenance['source_sha256']
    resources = {}
    for variant in VARIANTS:
        text = (report / variant / 'utilization.rpt').read_text()
        timing = (report / variant / 'timing.rpt').read_text()
        match = re.search(r'WNS\(ns\).*?\n\s*-+.*?\n\s*([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+\d+\s+([-\d.]+)\s+([-\d.]+)\s+(\d+)', timing, re.S)
        assert match, variant
        wns, tns, setup_fail, whs, ths, hold_fail = match.groups()
        resources[variant] = dict(lut=int(table_value(text, 'Slice LUTs')),
                                  ff=int(table_value(text, 'Slice Registers')),
                                  dsp=int(table_value(text, 'DSPs')),
                                  wns_ns=float(wns), whs_ns=float(whs),
                                  setup_failing_endpoints=int(setup_fail),
                                  hold_failing_endpoints=int(hold_fail),
                                  checkpoint_sha256=digest(report / variant / 'routed.dcp'))
        assert resources[variant]['dsp'] == 0
        assert int(setup_fail) == 0
        internal = dict(line.split() for line in (report / variant / 'internal_timing.txt').read_text().splitlines())
        resources[variant]['internal_setup_slack_ns'] = float(internal['setup'])
        resources[variant]['internal_hold_slack_ns'] = float(internal['hold'])
        assert min(map(float, internal.values())) >= 0
    diagnostics = report / 'diagnostics'
    diagnostics.mkdir(exist_ok=True)
    for source, target in [('phy_case_4/run.log', 'changing_weight_timing_case4.log'),
                           ('functional_diagnostic/run.log', 'plain_functional_netlist_case4.log'),
                           ('functional_diagnostic/elaborate.log', 'plain_functional_netlist_elaborate.log'),
                           ('functional_diagnostic/compile.log', 'plain_functional_netlist_compile.log'),
                           ('slow_clock_diagnostic.log', 'slow_clock_case4.log')]:
        if (work / source).exists():
            shutil.copy2(work / source, diagnostics / target)
    failure = (diagnostics / 'changing_weight_timing_case4.log').read_text(errors='replace')
    assert re.search(r'Fatal: Variant=\s+1 row=\s+0 got=\s+75061 expected=\s+9525', failure)
    activity = {case: net_activity(work / f'phy_case_{case}/activity.saif') for case in TIMING_CASES}
    rows = []
    for match in re.finditer(r'^SWITCH,(\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)', rtl, re.M):
        case, index, target, zeros, total, operands, products = map(int, match.groups())
        variant = VARIANTS[index]
        power = (report / variant / f'case_{case}/power.rpt').read_text() if case in TIMING_CASES else None
        for stage in ['case'] + (['phy_case'] if case in TIMING_CASES else []):
            logfile = work / f'{stage}_{case}/run.log'
            log = logfile.read_text(errors='replace')
            jobs, checks = (512, 10240) if stage == 'case' else (64, 1280)
            assert f'PASS isolation: jobs={jobs} checked_rows_across_variants={checks} latency_min=8 latency_max=8 case={case}' in log
            assert not re.search(r'Fatal:|Error:|[Tt]iming violation', log)
            target_dir = report / 'logs' / f'{stage}_{case}'
            target_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(logfile, target_dir / 'run.log')
        phy_row = None
        if case in TIMING_CASES:
            phy_log = (work / f'phy_case_{case}/run.log').read_text(errors='replace')
            phy_row = re.search(r'^SWITCH,' + str(case) + r',0,(\d+),(\d+),(\d+),', phy_log, re.M)
            assert phy_row and int(phy_row.group(3)) == 256
        rows.append(dict(case=case, profile='fixed_weights' if case < 4 else 'changing_weights',
                         target_zero_percent=target, actual_zeros=zeros, activations=total,
                         variant=variant, operand_bit_transitions=operands,
                         product_bit_transitions=products,
                         timing_status='passed' if case in TIMING_CASES else ('failed_ungated_baseline' if case == 4 else 'not_run'),
                         power_status='provisional_fixed_weight_estimate' if power else 'unavailable',
                         timing_net_bit_transitions=activity[case][variant]['transitions'] if phy_row else None,
                         timing_net_bits=activity[case][variant]['net_bits'] if phy_row else None,
                         timing_actual_zeros=int(phy_row.group(2)) if phy_row else None,
                         timing_activations=int(phy_row.group(3)) if phy_row else None,
                         estimated_dynamic_w=table_value(power, 'Dynamic (W)') if power else None,
                         estimated_static_w=table_value(power, 'Device Static (W)') if power else None,
                         estimated_total_w=table_value(power, 'Total On-Chip Power (W)') if power else None,
                         confidence=table_value(power, 'Confidence Level') if power else None,
                         nets_matched=table_value(power, 'Design Nets Matched') if power else None))
    assert len(rows) == 40
    with (report / 'comparison.csv').open('w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    deployment = board / 'jupyter_streaming'
    deployment_manifest = json.loads((deployment / 'manifest.json').read_text())
    assert digest(deployment / 'board.bit') == deployment_manifest['board_verified_bit_sha256']
    assert digest(deployment / 'board.hwh') == deployment_manifest['board_verified_hwh_sha256_raw']
    for name, expected in deployment_manifest['file_sha256_raw'].items():
        assert digest(deployment / name) == expected, f'Deployment manifest mismatch: {name}'
    script_names = ['prepare_isolation.py', 'test_isolation.ps1', 'implement_isolation.tcl',
                    'test_isolation_netlist.ps1', 'estimate_isolation.tcl', 'summarize_isolation.py']
    scripts = inputs / 'scripts'
    scripts.mkdir(exist_ok=True)
    for name in script_names:
        shutil.copy2(board / 'scripts' / name, scripts / name)
    summary = dict(scope=provenance['scope'], clock_mhz=25,
                   methodology='Identical seeded inputs, five LUT-only OOC routed variants. RTL edge-sampled bit transitions; post-route SDF SAIF for power.',
                   workload=dict(seeds_per_case=4, jobs_per_seed=128, jobs_per_case=512,
                                 activation_values_per_case=2048,
                                 timing_jobs_per_seed=16, timing_jobs_per_case=64,
                                 timing_activation_values_per_case=256,
                                 weight_zeros='Three of sixteen weights forced zero; other weights include signed limits and random INT8.',
                                 dense_definition='Zero target activation sparsity; weights still contain zeros.',
                                 timing='All variants receive identical reset, clear, weight-load and idle intervals.'),
                   validation=dict(status='experimental_not_deployment_ready', rtl_jobs=4397, rtl_row_checks=87940,
                                   sdf_passed_jobs=397, sdf_passed_row_checks=7940,
                                   sdf_passed_cases=list(TIMING_CASES), sdf_failed_cases=[4], sdf_not_run_cases=[5, 6, 7],
                                   sdf_jobs_per_case=64, sdf_directed_jobs=141,
                                   sdf_annotated_cores=5, sdf_combined_file_annotations=1,
                                   sdf_cells_by_core=annotation_cells, latency_cycles_4x4=8,
                                   parameterized_row_checks_per_prototype=3360,
                                   parameterized_latency_cycles={'4': 8, '8': 16, '16': 32}),
                   limitations=['Simulation is not physical power measurement.',
                                'SDF uses the maximum-delay column; exhaustive multi-corner timing simulation was not performed.',
                                'Power report resolution is 0.001 W; small changes and percentages are not resolved.',
                                'Changing-weight SDF comparison fails in the ungated baseline, even at half clock rate; its functional netlist passes. Root cause is unresolved.',
                                'Power estimates are provisional and cover fixed-weight traces only. Vivado Power 33-332 warns about high-fanout reset activity.',
                                'Isolated OOC core excludes system software, memory traffic and CPU; boundary routing is virtual.',
                                'LUT-only mapping controls the comparison; DSP-based mapping needs a separate experiment.',
                                'Internal setup/hold pass; virtual input-boundary hold violations remain with zero input delay. No integrated timing closure is claimed.',
                                'No cycle skipping; no demonstrated classifier latency or board-energy improvement.'],
                   production_sha256=digest(production),
                   timing_simulator_settings=dict(transport_interconnect_delays=True,
                                                  pulse_reject_percent=0, pulse_error_percent=0,
                                                  interconnect_pulse_reject_percent=0,
                                                  interconnect_pulse_error_percent=0,
                                                  timing_checks_enabled=True),
                   script_sha256={name:digest(board / 'scripts' / name) for name in script_names},
                   sdf_sha256={name:digest(work / 'netlists' / f'{name}.sdf') for name in VARIANTS + ['all']},
                   deployed_sha256={name:digest(deployment / name) for name in ['board.bit', 'board.hwh', 'manifest.json']},
                   resources=resources, cases=rows)
    (report / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    lines = ['# Zero-operand isolation experiments', '',
             'Two implemented prototypes improve RTL multiplier switching under suitable workloads. '
             'They are experimental alternatives to the legacy systolic core. Production RTL, '
             'the deployed FPGA image and the streaming classifier path remain unchanged.', '',
             '**Deployment status: experimental.** Changing-weight timing simulation fails in '
             'the plain ungated baseline; the root cause is unresolved. Fixed-weight timing checks '
             'pass, but associated timing-activity and power estimates remain provisional. No '
             'physical power saving or deployable implementation is established by this experiment.', '',
             'Activation hold preserves the previous nonzero activation and carries a zero flag '
             'through the array. Zero operations forward the partial sum, so the stale held product '
             'cannot change the answer. Weights connect directly to the multiplier.', '',
             'Dual-operand hold preserves both multiplier inputs when either operand is zero or '
             'the operation is invalid. It bypasses the product in those cycles. It handles weight '
             'changes better, at the cost of operand storage and selection logic.', '',
             'The fair ungated retention control also preserves data across clears. Comparing against '
             'this control separates zero-aware savings from ordinary retention benefits.', '',
             '## Verification and implementation', '',
             'Vivado/Xsim 2023.2; XC7Z020-1; 25 MHz; signed INT8 multiplication and 24-bit wrapped accumulation. '
             'All five 4x4 variants pass 4,397 jobs / 87,940 row comparisons in RTL. '
             'Post-route SDF simulation separately passes 397 jobs / 7,940 row comparisons: '
             'four fixed-weight cases with four seeds and sixteen jobs per seed, plus 141 directed jobs. '
             'The shorter timing corpus uses the prefix of each RTL seed; it does not repeat the full RTL corpus. '
             'Tests cover random values, signed limits, sparse inputs, '
             'weight reloads, continuous accumulation through overflow, clear abort and reset abort. '
             'Both prototypes also pass 3,360 row checks each across 4x4, 8x8 and 16x16 arrays.', '',
             'Changing-weight SDF case 4 fails at 1,360 ns: plain ungated row 0 gives 75,061 '
             'instead of 9,525. The same failure repeats at a forced 12.5 MHz clock (2,720 ns). '
             'A separate diagnostic using the plain routed netlist without SDF, alongside the '
             'four RTL designs, passes all 64 jobs in that case. This narrows the problem to the '
             'timing comparison but does not establish its cause. Cases 5-7 were not run with SDF '
             'after the failure. Their RTL results remain included below; no power estimate uses '
             'the failed or unrun timing cases. Raw diagnostic logs are retained.', '',
             'An initial timing harness enabled transport interconnect delays and zero pulse rejection '
             'but left pulse-error thresholds at their default 100%. It produced an X at a LUT with '
             'known inputs and later failed a result comparison. That raw failure, its harness and '
             'a diagnostic trace log remain in diagnostics/. The corrected configuration sets both '
             'pulse rejection and pulse-error thresholds to zero for path and interconnect pulses. '
             'Cell/interconnect delays and timing checks remain enabled; the corrected simulations '
             'pass the checks stated above. A long corrected full-corpus run was interrupted for '
             'runtime before completion and is not counted as passed. The smaller timing corpus '
             'is used explicitly instead. These are digital timing-model results, not physical '
             'glitch measurements or exhaustive multi-corner simulation. See '
             '[AMD simulator options](https://docs.amd.com/r/2023.1-English/ug900-vivado-logic-simulation/xelab-xvhdl-and-xvlog-xsim-Command-Options).', '',
             'Latency remains 8 / 16 / 32 clocks for 4x4 / 8x8 / 16x16. No cycle skipping is implemented.', '',
             '| Variant | LUTs | Registers | DSPs | Internal setup slack (ns) | Internal hold slack (ns) |',
             '|---|---:|---:|---:|---:|---:|']
    for variant, label in zip(VARIANTS, LABELS):
        r = resources[variant]
        lines.append(f"| {label} | {r['lut']} | {r['ff']} | {r['dsp']} | {r['internal_setup_slack_ns']:.3f} | {r['internal_hold_slack_ns']:.3f} |")
    lines += ['', 'Internal register-to-register setup and hold pass. Full OOC timing reports retain '
              'input-boundary hold violations under the artificial zero input-delay assumption; '
              'the worst overall slack and failing endpoint counts are preserved in summary.json. '
              'Timing simulation drives inputs on falling clock edges. The cores were built out '
              'of context with virtual boundary routing, not integrated into a new full-chip image. '
              'These results do not establish integrated timing closure. '
              'All five designs use zero DSPs. The legacy/plain baselines naturally mapped to LUTs '
              'and were reused after checking their DSP count; the remaining designs used '
              '`-max_dsp 0`. The reproducible script now applies that policy to all five. '
              'Register counts are final routed counts after synthesis optimization and replication.', '',
              '## Switching results', '',
              'Four deterministic seeds, 128 jobs per seed in every case. Each case contains 2,048 '
              'activation values. Three of sixteen matrix weights are forced zero; other weights '
              'include random INT8 values and -128/127. “Dense” refers to activations. Fixed weights '
              'are loaded once per seed; changing weights are loaded every job. Clear and variable '
              'idle intervals are identical across variants.', '',
              'Counts below are bit transitions sampled at clock edges in RTL, summed over sixteen '
              'multiplier outputs. These are not total circuit transitions, glitch counts or watts. '
              'The complete operand and product counts are in comparison.csv.', '',
              '| Weight profile | Target activation zeros | Actual zeros | Old isolation | Ungated | Retained ungated | Activation hold | Dual hold |',
              '|---|---:|---:|---:|---:|---:|---:|---:|']
    for case in range(8):
        group = [r for r in rows if r['case'] == case]
        first = group[0]
        counts = ' | '.join(str(r['product_bit_transitions']) for r in group)
        lines.append(f"| {first['profile']} | {first['target_zero_percent']}% | {first['actual_zeros']}/2048 | {counts} |")
    def result_for(case, variant):
        return next(r for r in rows if r['case'] == case and r['variant'] == variant)

    def saving(case, candidate, field):
        base = result_for(case, 'retained')[field]
        value = result_for(case, candidate)[field]
        return (base-value)*100/base
    lines += ['', f"At roughly 90% activation zeros with fixed weights, activation hold reduces product transitions "
              f"by {saving(2, 'isolated', 'product_bit_transitions'):.2f}% and operand transitions by "
              f"{saving(2, 'isolated', 'operand_bit_transitions'):.2f}% versus retained ungated. "
              'This demonstrates that recognizing zeros can reduce redundant multiplier activity while preserving results and latency.', '',
              'The lightweight activation-hold method has a significant counterexample: with weights changing '
              f"every job at roughly 90% zeros, product transitions increase from {result_for(6, 'retained')['product_bit_transitions']:,} "
              f"to {result_for(6, 'isolated')['product_bit_transitions']:,}. "
              'A held nonzero activation still reacts to a changing weight. Dual hold reduces that '
              f"case to {result_for(6, 'dual')['product_bit_transitions']:,} ({saving(6, 'dual', 'product_bit_transitions'):.2f}% fewer than retained ungated). "
              'Some dual-hold savings on dense inputs also come from invalid-cycle and zero-weight isolation. '
              'Do not attribute all savings exclusively to activation sparsity.', '',
              'All-zero cases show that the old force-zero scheme can itself suppress product activity. '
              'No candidate is declared universally better from selected sparse cases.', '',
              '## Timing-simulation net activity', '',
              'These counts sum the TC field of the flat core NET section in the SDF timing SAIF. '
              'They include modeled glitches and each listed net bit, including ports. They exclude '
              'primitive-pin duplicates and are not weighted by capacitance; clock fanout power '
              'cannot be inferred from this sum. Use the power reports for the modeled hardware cost.', '',
              '| Weight profile | Target zeros | Old isolation | Ungated | Retained ungated | Activation hold | Dual hold |',
              '|---|---:|---:|---:|---:|---:|---:|']
    for case in TIMING_CASES:
        group = [r for r in rows if r['case'] == case]
        first = group[0]
        counts = ' | '.join(str(r['timing_net_bit_transitions']) for r in group)
        lines.append(f"| {first['profile']} | {first['target_zero_percent']}% | {counts} |")
    lines += ['', f"In the shorter fixed-weight 90%-target trace, activation hold reduces listed core net "
              f"transitions by {saving(2, 'isolated', 'timing_net_bit_transitions'):.2f}% versus retained ungated. "
              f"In the dense activation trace, it instead increases them by {-saving(0, 'isolated', 'timing_net_bit_transitions'):.2f}%. "
              'This exposes the control/selection overhead that multiplier-output counts alone miss. '
              'The net-transition sum is not capacitance-weighted and must not be presented as a power-saving percentage.', '',
              '## Power estimates', '',
              'Each routed checkpoint receives its own hierarchical activity from the same SDF timing '
              'simulation, including modeled delays and glitches. Five core SDF files are combined '
              'under the testbench hierarchy without changing delay values, because this Xsim '
              'version accepts one annotation per invocation. Only the four passing fixed-weight '
              'traces are used. Estimates are provisional because the broader timing comparison '
              'has an unresolved baseline failure. Activity is reset before each annotation.', '',
              'Timing power traces contain 64 jobs / 256 activation values per case, compared with '
              '512 jobs / 2,048 activation values for RTL edge-sampled switching. Actual timing-trace '
              'zero counts are shown below. All variants receive the same inputs within each trace.', '',
              '| Weight profile | Target zeros | Actual timing zeros | Variant | Estimated dynamic (W) | Estimated total (W) | Matched design nets | Confidence |',
              '|---|---:|---:|---|---:|---:|---|---|']
    for r in rows:
        if r['case'] not in TIMING_CASES:
            continue
        lines.append(f"| {r['profile']} | {r['target_zero_percent']}% | {r['timing_actual_zeros']}/256 | {r['variant']} | {r['estimated_dynamic_w']} | {r['estimated_total_w']} | {r['nets_matched']} | {r['confidence']} |")
    rounded_dynamic_win = any(float(result_for(case, variant)['estimated_dynamic_w']) <
                              float(result_for(case, 'retained')['estimated_dynamic_w'])
                              for case in TIMING_CASES for variant in ['isolated', 'dual'])
    lines += ['', ('The rounded dynamic power values show a provisional advantage in some cases.' if rounded_dynamic_win else
                    'The rounded dynamic power values do not show an advantage for either hold prototype over retained ungated.'), '',
              f"At 90%-target zeros, retained ungated reports {result_for(2, 'retained')['estimated_dynamic_w']} W dynamic / "
              f"{result_for(2, 'retained')['estimated_total_w']} W total. Activation hold reports "
              f"{result_for(2, 'isolated')['estimated_dynamic_w']} W / {result_for(2, 'isolated')['estimated_total_w']} W, "
              f"and dual hold reports {result_for(2, 'dual')['estimated_dynamic_w']} W / {result_for(2, 'dual')['estimated_total_w']} W. "
              'These rounded values do not support a precise power percentage or establish a measured net power benefit.', '',
              'Values above are isolated-core Vivado estimates, not board measurements. Reports round '
              'to 0.001 W, so a one-digit difference does not establish a precise percentage saving. '
              'Vivado Power 33-332 warns about high-fanout reset activity. The corpus clears before '
              'each job and resets between seeds. This warning and the unresolved changing-weight '
              'timing mismatch limit interpretation even when the coverage confidence is High. '
              'See power_console.log for the warning output. '
              'Device static power belongs to the FPGA device, not uniquely to this core. Clock, '
              'register, control and routing costs can offset reduced multiplier activity. No '
              'external power meter is available, and no physical energy-saving claim is made.', '',
              '## Interpretation', '',
              'Use activation hold as a candidate for sparse activations with stationary weights. '
              'Dual hold has promising changing-weight RTL switching results, but its broader '
              'timing comparison remains unvalidated. Select between them using integrated '
              'timing, area and activity-based power under the real model workload. These results '
              'establish conditional switching benefits, not a universal power advantage. The '
              'current board implementation has not been replaced by either prototype.', '',
              'Presentation wording: “We replaced forced-zero operand muxing with state retention '
              'and explicit zero-result bypass. In the fixed-weight sparse test, multiplier-output '
              'bit transitions fell by about 46% against an ungated retention baseline, with exact '
              'outputs and unchanged latency. This is simulated switching reduction; physical power '
              'savings remain unmeasured.”', '',
              '## Reproduce', '',
              'Run from the repository root in PowerShell. Native Vivado commands need a normal '
              'Vivado-capable host. Python must be available.', '', '```powershell',
              '$work = "$PWD/Phase2_RTL/fpga/work_isolation"',
              'python Phase2_RTL/fpga/scripts/prepare_isolation.py --out $work',
              '& Phase2_RTL/fpga/scripts/test_isolation.ps1 -Work $work',
              '& C:/Xilinx/Vivado/2023.2/bin/vivado.bat -mode batch -source Phase2_RTL/fpga/scripts/implement_isolation.tcl',
              '& Phase2_RTL/fpga/scripts/test_isolation_netlist.ps1 -Work $work -FixedOnly',
              '& C:/Xilinx/Vivado/2023.2/bin/vivado.bat -mode batch -source Phase2_RTL/fpga/scripts/estimate_isolation.tcl -tclargs --fixed-only *> Phase2_RTL/fpga/reports/isolation_hold_20261028/power_console.log',
              'python Phase2_RTL/fpga/scripts/summarize_isolation.py --work $work', '```', '',
              'Omit -FixedOnly to reproduce the full timing attempt, which currently fails at '
              'changing-weight case 4. Existing diagnostic logs document the failure. ', '',
              'Raw activity and timing netlists are compressed in activity_and_netlists.zip. '
              'The failed case 4 activity, when present, is archived only as diagnostic evidence. '
              'Inputs, logs, per-case power/annotation reports and all five routed checkpoints '
              'are retained here. summary.json records source and deployment hashes. The source '
              'snapshot and all workload seeds are reproducible from prepare_isolation.py and tb_isolation.sv.', '']
    (report / 'README.md').write_text('\n'.join(lines), encoding='utf-8')
    archive = report / 'activity_and_netlists.zip'
    artifacts = [work / f'case_{case}/activity.saif' for case in range(8)]
    artifacts += [work / f'phy_case_{case}/activity.saif' for case in range(8)
                  if (work / f'phy_case_{case}/activity.saif').exists()]
    artifacts += [work / 'netlists' / f'{variant}.{extension}'
                  for variant in VARIANTS for extension in ['v', 'sdf']]
    artifacts += [work / 'netlists/all.sdf', work / 'netlists/annotation_cells.json']
    if (work / 'isolated_debug.vcd').exists():
        artifacts.append(work / 'isolated_debug.vcd')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for path in artifacts:
            bundle.write(path, path.relative_to(work).as_posix())
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert len(bundle.infolist()) == len(artifacts)
    archive_metadata = dict(archive=archive.name, sha256=digest(archive),
                            compressed_bytes=archive.stat().st_size,
                            files=[dict(path=p.relative_to(work).as_posix(),
                                        bytes=p.stat().st_size, sha256=digest(p),
                                        role='failed_trace_excluded_from_estimates' if p.parent.name == 'phy_case_4' else 'experiment_evidence') for p in artifacts])
    (report / 'activity_manifest.json').write_text(json.dumps(archive_metadata, indent=2) + '\n')
    evidence = {p.relative_to(report).as_posix(): digest(p) for p in sorted(report.rglob('*'))
                if p.is_file() and p.name != 'evidence_manifest.json'}
    (report / 'evidence_manifest.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(dict(report=str(report), variants=len(resources), comparisons=len(rows),
                          validation=summary['validation'], archive_bytes=archive.stat().st_size), indent=2))


if __name__ == '__main__':
    main()
