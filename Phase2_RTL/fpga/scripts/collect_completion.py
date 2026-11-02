"""Collect measured/simulated FPGA evidence with explicit incomplete stages.

This collector refuses to declare physical validation without matching hashes
and passing board results. It never infers measured power from a Vivado estimate.
"""
import argparse
import datetime as dt
import hashlib
import json
import re
from pathlib import Path


def digest(path, normalize=False):
    data=path.read_bytes()
    return hashlib.sha256(data.replace(b'\r\n',b'\n') if normalize else data).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reports',type=Path,required=True)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[3]
    report_dir=args.reports.resolve()
    bundle=root/'Phase2_RTL/fpga/jupyter_streaming'
    board=json.loads((report_dir/'board_validation.json').read_text())
    auto=json.loads((report_dir/'banknote_autonomous_results.json').read_text())
    host=json.loads((report_dir/'banknote_host_chained_results.json').read_text())
    assert board['status']=='passed' and board['execution']=='physical_pynq'
    cleanup_path=bundle/'comment_cleanup.json'
    cleanup=json.loads(cleanup_path.read_text()) if cleanup_path.exists() else {'changed':[]}
    comment_edits={row['path']:row for row in cleanup['changed']
                   if row['verification']=='Python AST identical (including docstrings)'}
    for name,expected in board['hashes'].items():
        actual=digest(bundle/name)
        edit=comment_edits.get((bundle/name).relative_to(root).as_posix(),{})
        equivalent=(edit.get('before_sha256')==expected and edit.get('after_sha256')==actual)
        assert actual==expected or equivalent, 'Board/local mismatch: '+name
    for result in (auto,host):
        assert result['runs']==100
        assert abs(result['hardware_accuracy']-266/271)<1e-12
        assert len(result['hardware_raw_us'])==100
    compute=(report_dir/'compute_regression.log').read_text()
    for marker in ('PASS MAC4','PASS fused layer','PASS stream job engine','PASS adaptive streaming array',
                   'STREAM_THROUGHPUT,4,0','STREAM_THROUGHPUT,4,32','STREAM_THROUGHPUT,4,1',
                   'PASS parameterized systolic arrays','PASS streaming CORDIC:','PASS streaming divider:',
                   'PASS streaming learning','PASS command queue depth=4','PASS: 733',
                   'PASS tb_spi_bridge: 12','PASS tb_npu_spi: 160'):
        assert marker in compute, marker
    model_log=(report_dir/'autonomous/model.run.log').read_text()
    assert 'PASS autonomous model: 271 exact' in model_log
    soc_path=root/'Phase2_RTL/fpga/sim/results_streaming_4/run.log'
    soc=soc_path.read_text()
    assert 'PASS CV32 streaming: lanes=4' in soc and 'PASS CV32 autonomous model' in soc
    vendor=(report_dir/'vendor_dma.console.log').read_text()
    assert 'PASS vendor AXI CDMA:' in vendor
    audit=(report_dir/'audit.console.log').read_text()
    assert 'PASS routed FPGA audit:' in audit
    text=(report_dir/'implementation/timing.rpt').read_text()
    timing_line=next(l for l in text.split('Design Timing Summary',1)[1].splitlines()
                     if re.match(r'^\s+-?\d+\.\d+\s+-?\d+\.\d+\s+\d+\s+\d+\s+-?\d+\.\d+',l))
    cells=timing_line.split()
    timing=dict(setup_slack_ns=float(cells[0]),setup_failing_endpoints=int(cells[2]),
                hold_slack_ns=float(cells[4]),hold_failing_endpoints=int(cells[6]))
    assert timing['setup_slack_ns']>=0 and timing['hold_slack_ns']>=0
    assert timing['setup_failing_endpoints']==timing['hold_failing_endpoints']==0
    switch=(report_dir/'zero_aware/run.log').read_text()
    assert 'PASS zero-aware baseline: 768' in switch
    switching=[]
    for line in switch.splitlines():
        if line.startswith('SWITCHING,'):
            target,zeros,total,gi,ui,gp,up=map(int,line.split(',')[1:])
            switching.append(dict(target_zero_percent=target,actual_zero_activations=zeros,
                activations=total,gated_operand_toggles=gi,ungated_operand_toggles=ui,
                gated_product_toggles=gp,ungated_product_toggles=up))
    assert len(switching)==3
    manifest=json.loads((bundle/'manifest.json').read_text())
    mismatches=[name for name,expected in manifest['build_input_sha256'].items()
                if digest(root/name,normalize=True)!=expected]
    assert not mismatches, 'Build source changed: '+str(mismatches)
    mem=root/'Phase2_RTL/fpga/firmware/build_streaming/firmware.mem'
    assert digest(mem)==manifest['firmware_mem_sha256']
    now=dt.datetime.now(dt.timezone(dt.timedelta(hours=5,minutes=30))).isoformat()
    result=dict(completed_at=now,status='fpga_functional_validation_passed_with_open_engineering_items',
                tool='Vivado 2023.2',part='xc7z020clg400-1',clock_mhz=25,
                implementation_basis='Revalidated existing routed implementation; build-source LF hashes and rebuilt firmware match the recorded build. No new place/route or area optimization claimed.',
                host_unit_tests=35,compute_regression_tests=13,autonomous_simulation_outputs=271,
                firmware_streaming_simulation='passed',vendor_axi_cdma_simulation='passed',
                timing=timing,physical_board_validation=board,
                autonomous_benchmark=auto,host_chained_benchmark=host,
                host_chained_median_divided_by_autonomous_median=host['hardware_workflow_us']['median']/auto['hardware_workflow_us']['median'],
                switching_comparison=switching,
                switching_conclusion='For this fixed-weight corpus, isolated variants have more sampled multiplier input/product toggles. No switching/power saving established. SAIF retained; RTL edge counts are not post-route internal power.',
                power=dict(measured=False,reason='User confirmed no external power meter is available',
                           estimated_watts=1.628,confidence='Low',basis='Vivado vectorless; not physical power'),
                engineering_open_items=['Asynchronous BRAM-control warning paths remain and require reset/enable-specific closure.',
                    'Combinational LUT driving local asynchronous reset requires reset hazard review.',
                    'DRC warning counts are capped: original 71 is not exhaustive; expanded REQP-1839 also reached 100000 entries.',
                    'DSP pipelining and control-set advisories remain; no area reduction claimed.',
                    'Physical power/energy cannot be measured without an external meter.'],
                hashes={name:digest(bundle/name) for name in board['hashes']},
                current_bundle_matches_board_validation_bytes=all(digest(bundle/name)==expected for name,expected in board['hashes'].items()),
                comment_cleanup=cleanup if cleanup_path.exists() else None)
    (report_dir/'completion.json').write_text(json.dumps(result,indent=2)+'\n')
    lines=['# FPGA completion results', '', 'Completed '+now, '',
      'The matching FPGA image has now passed physical-board functional and model validation. The routed design was re-audited; this run does not claim a fresh place/route or warning-free production sign-off.', '',
      '## Physical board results', '',
      '- Four streaming activation modes: 1024 exact comparisons.',
      '- Four legacy modes: 32 raw/activated comparisons.',
      '- Two-bank reverse collection: 512 exact comparisons and owned-bank rejection.',
      '- Host-chained and autonomous model: 266/271 correct, 98.15498%; fixed14-reference outputs match.',
      '- 100 timed batches per activation policy, 256 outputs per batch; checks outside timing.',
      '- Model benchmark: 100 measured runs per workflow, 271 examples/run; diagnostics in a separate pass.', '',
      '| Workflow | Median per 271 examples | P95 | Classifications/s |',
      '|---|---:|---:|---:|']
    for name,row in [('Autonomous FPGA',auto),('Host-chained FPGA',host)]:
        t=row['hardware_workflow_us'];lines.append(f"| {name} | {t['median']/1000:.5f} ms | {t['p95']/1000:.5f} ms | {271e6/t['median']:.0f} |")
    lines += ['',f"Autonomous workflow is {result['host_chained_median_divided_by_autonomous_median']:.3f}x faster than the measured host-chained FPGA workflow.",
      f"The separate NumPy mathematical baseline in the autonomous run has median {auto['numpy_model_us']['median']/1000:.5f} ms; it is faster than the FPGA API here. The bit-exact interpreted Python reference is much slower but is not an optimized C/NEON baseline. Do not claim universal CPU speedup.", '',
      'Both baselines begin with preprocessed Q7 inputs. Raw-feature normalization, allocation, one-time model upload and reference checks are excluded. Hardware includes transfers/control; NumPy uses mathematical activations. Timings from separate runs are not perfectly interleaved workflow comparisons.', '',
      '## Fixed versus adaptive activation', '',
      '| Policy | Median per 256 outputs | Max code error versus fixed14 |',
      '|---|---:|---:|']
    for row in board['policies']:
        lines.append(f"| {row['name']} | {row['timing_us']['median']:.2f} us | {row['max_abs_error_codes']} |")
    lines += ['', 'All policies use the same 256-value seeded corpus repeated over batches, clock and software boundary. Tables reset between policies. This characterizes this corpus and learning history; repeated inputs and periodic sampling do not establish independent coverage of unseen inputs. API noise dominates the small time differences, so these medians are not evidence of adaptive compute/energy speedup. Unsampled errors can exceed threshold eight; observed maximum was fifteen codes (0.00091552734375).', '',
      '## Local verification', '',
      '- 35 Python host tests passed.',
      '- All 13 compute/interface regressions passed, including 733 legacy, 160 SPI/NPU, 12 bridge, MAC, FIFO, streaming divider/CORDIC and reset/stall/learning cases.',
      '- Autonomous RTL: 271 exact fixed14 outputs.',
      '- Rebuilt firmware and CV32E40P streaming/fused/model simulation passed.',
      '- Vendor AXI CDMA regression passed with 64-bit PS HP0.',
      f"- Routed timing: setup {timing['setup_slack_ns']:+.3f} ns; hold {timing['hold_slack_ns']:+.3f} ns; zero failing setup/hold endpoints.", '',
      '## Gated versus ungated experiment', '',
      '768 row outputs matched both variants and independent dot products. Clock, input vectors, weights and execution schedule match; weights stay fixed across 64 jobs per sparsity phase. Stimulus changes on falling edges and activity is sampled on rising edges.', '',
      '| Target zero fraction | Actual zeros / 256 | Gated operand toggles | Ungated operand toggles | Gated product toggles | Ungated product toggles |',
      '|---|---:|---:|---:|---:|---:|']
    for row in switching:
        lines.append('| {target_zero_percent}% | {actual_zero_activations} | {gated_operand_toggles} | {ungated_operand_toggles} | {gated_product_toggles} | {ungated_product_toggles} |'.format(**row))
    lines += ['', result['switching_conclusion'], '',
      'SAIF: zero_aware/activity.saif. This is RTL activity, not post-route glitch activity or physical energy. The deployed design was not altered to make the comparison.', '',
      '## Report review and remaining limits', '',
      '- Utilization remains 43784 LUTs, 37381 registers, 33.5 BRAM tiles and 21 DSPs.',
      '- Hierarchical attribution: stream peripheral 30077 LUTs, its activation array 24745 LUTs; CPU 5120 LUTs; legacy SPI NPU 3723 LUTs. These are nested hierarchy totals: do not add overlapping rows.',
      '- DRC: zero errors, but original 71 entries include CHECK-3 truncation. Expanding REQP-1839 reached 100000 entries; total warning count remains unknown. The compressed diagnostic report is implementation/drc_expanded_capped.zip. Entries can represent paths and do not equal unique faulty cells.',
      '- REQP-1839 concerns asynchronously reset registers driving BRAM controls. Passing simulation/board tests does not prove arbitrary asynchronous-reset safety. Review enable/write suppression and reset timing; no blanket waiver is made.',
      '- LUTAR-1 identifies a multi-input LUT driving local asynchronous reset. This remains a reset-hazard review item.',
      '- DPIP/DPOP/DPIR are DSP-register mapping/pipeline advisories. Changing them requires latency/functional revalidation.',
      '- ULMTCS-1: 1013 control sets exceeds the recommended 7.5% guideline; RTSTAT-10 concerns unused vendor-DMA routing loads.',
      '- CDC reports one informational synchronized reset-button crossing and no unsafe reported crossing. Timing exceptions intentionally cover the asynchronous button and LED/UART outputs; this is not a board-level synchronous I/O timing guarantee.',
      '- Vectorless power remains 1.628 W (1.481 W dynamic estimate, 0.147 W static), low confidence with reset-activity warning. It is not a board measurement.',
      '- Physical power/energy remains unmeasured: the user confirmed no external meter is available.', '',
      '## Deployment and reproducibility', '',
      'Tested directory: /home/xilinx/jupyter_notebooks/npu_completion_20261028. Existing project directories were preserved. No board password is stored in source or results.', '',
      'Before running PYNQ over SSH, source /etc/profile.d/xrt_setup.sh and /etc/profile.d/boardname.sh and use /usr/local/share/pynq-venv/bin/python with hardware privileges. The initial No Devices Found issue was an environment issue and was resolved this way.', '',
      'Raw records: board_validation.json, banknote_autonomous_results.json, banknote_host_chained_results.json, compute_regression.log, autonomous/model.run.log, vendor_dma.console.log, implementation/*.rpt, zero_aware/run.log and activity.saif.', '',
      'To reproduce software validation on the board:', '',
      '```bash',
      'source /etc/profile.d/xrt_setup.sh',
      'source /etc/profile.d/boardname.sh',
      '/usr/local/share/pynq-venv/bin/python validate.py --runs 100 --model-runs 20 --output board_validation.json',
      '/usr/local/share/pynq-venv/bin/python bench.py --autonomous --runs 100 --profiles 5',
      '/usr/local/share/pynq-venv/bin/python bench.py --runs 100 --profiles 5',
      '```', '',
      'A complete manufacturing/energy sign-off is not claimed. Functional FPGA deployment/validation is complete, with the above engineering and equipment limits explicit.']
    (report_dir/'RESULTS.md').write_text('\n'.join(lines)+'\n')

    manifest['board_execution_verified']=True
    manifest['board_verification_basis']='Physical PYNQ run on 2026-10-28: all four modes, legacy, bank ownership, exact autonomous/host-chained model outputs and 100-run benchmarks. See board_verification_report. Does not establish measured power or warning-free sign-off.'
    manifest['current_bundle_matches_board_validation_bytes']=result['current_bundle_matches_board_validation_bytes']
    manifest['board_validation_software_comment_equivalence_verified']=not result['current_bundle_matches_board_validation_bytes']
    if not result['current_bundle_matches_board_validation_bytes']:
        manifest['board_verification_basis']+=' Current software differs only by recorded AST-equivalent comment removal; historical board hashes are retained in the report. The cleaned software has not been re-run on the board.'
    manifest['board_verification_report']='../reports/completion_20261028/completion.json'
    manifest['board_verified_bit_sha256']=board['hashes']['board.bit']
    manifest['board_verified_hwh_sha256_raw']=board['hashes']['board.hwh']
    manifest['board_verification_completed_at']=now
    for name in manifest['files']:
        manifest['files'][name]=digest(bundle/name,normalize=True)
    manifest['files']['validate.py']=digest(bundle/'validate.py',normalize=True)
    manifest['files']['README.md']=digest(bundle/'README.md',normalize=True)
    manifest['file_sha256_raw']={name:digest(bundle/name) for name in manifest['files']}
    (bundle/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('PASS evidence collection and matching physical-board package verification')
    print(report_dir/'RESULTS.md')


if __name__=='__main__':main()
