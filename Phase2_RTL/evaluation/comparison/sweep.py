"""Reproducible RTL experiment; JSON results, raw simulator outputs, mathematical error.

python sweep.py --work <directory> --run
python sweep.py --work <directory> --analyse
No board, energy, or model-accuracy measurements are inferred from simulation.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
VECTORS, LANES, WARMUP = 2048, 4, 256
POLICIES = ('fixed14_s256', 'fixed14_s1', 'adaptive_s1_e0', 'adaptive_s32_e0',
            'adaptive_s32_e8', 'adaptive_s256_e8', 'frozen_seed_s32_e8')
SEEDS = (7, 23)
FIELDS = ('shared', 'case_id', 'mode', 'workload', 'policy', 'first_latency_cycles',
          'total_cycles', 'steady_output_window_cycles', 'input_stall_cycles',
          'reference_stall_cycles', 'selected_iterations_sum', 'selected_iterations_steady_sum',
          'reference_samples', 'fallbacks', 'sampled_max_residual_lsb')

def stimuli():
    result = []
    for distribution in ('full_range_uniform', 'central_gaussian', 'distribution_shift'):
        for seed in SEEDS:
            rng = np.random.default_rng(seed)
            if distribution == 'full_range_uniform':

                x = np.arange(VECTORS*LANES, dtype=np.int64)*64-262144
                rng.shuffle(x)
            elif distribution == 'central_gaussian':
                x = np.rint(rng.normal(0, 1, VECTORS*LANES)*16384).astype(np.int64)
            else:
                x = np.concatenate((rng.normal(0, .5, VECTORS*LANES//2),
                                    rng.normal(0, 3, VECTORS*LANES//2)))
                x = np.rint(x*16384).astype(np.int64)
            result.append(dict(distribution=distribution, seed=seed,
                               values=np.clip(x, -262144, 262143).astype(np.int32)))
    return result

def prepare(work):
    work.mkdir(parents=True, exist_ok=True)
    data = stimuli()
    (work/'stimulus.mem').write_text(''.join(f'{int(x)&0x7ffff:05x}\n' for row in data for x in row['values']))
    sources = [ROOT/line for line in (ROOT/'rtl/sources.f').read_text().splitlines() if line.strip()]
    sources.append(ROOT/'verification/tb_sweep.sv')
    manifest = dict(vectors=VECTORS, lanes=LANES, warmup_vectors=WARMUP,
                    policies=POLICIES, workloads=[{k:v for k,v in row.items() if k!='values'} for row in data],
                    clock_mhz=25, device='xc7z020clg400-1', numpy_version=np.__version__,
                    stimulus_sha256=hashlib.sha256((work/'stimulus.mem').read_bytes()).hexdigest(),
                    source_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
    (work/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    return sources

def run(work, vivado):
    sources = prepare(work)
    def call(tool, args, log):
        with (work/log).open('w') as output:
            result = subprocess.run([str(vivado/(tool+'.bat')), *map(str,args)], cwd=work,
                                    stdout=output, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError((work/log).read_text()[-5000:])
    call('xvlog', ['-sv', *sources], 'compile.log')
    for kind in ('shared', 'independent'):
        top = 'tb_eval_'+kind
        call('xelab', [top, '-s', top, '--timescale', '1ns/1ps'], kind+'.elaborate.log')
        call('xsim', [top, '-runall'], kind+'.run.log')
        text = (work/(kind+'.run.log')).read_text()
        if 'PASS controlled evaluation' not in text or 'Fatal:' in text or 'Error:' in text:
            raise RuntimeError(text[-5000:])
        print(kind+': 84 RTL cases completed', flush=True)

def error_metrics(actual, target):
    error = actual-target
    absolute = np.abs(error)
    return dict(mae=float(absolute.mean()), rmse=float(np.sqrt(np.mean(error*error))),
                max_abs=float(absolute.max()), p99_abs=float(np.quantile(absolute, .99)))

def analyse(work):
    sys.path.insert(0, str(ROOT/'fpga/jupyter'))
    from client import activation_reference
    data = stimuli()
    manifest = json.loads((work/'manifest.json').read_text())
    assert hashlib.sha256((work/'stimulus.mem').read_bytes()).hexdigest()==manifest['stimulus_sha256']
    for name, digest in manifest['source_sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest, 'RTL changed since run: '+name
    reference, mathematical = {}, {}
    for mode in range(2):
        cache = {}
        for i, row in enumerate(data):
            x = row['values']
            for value in np.unique(x):
                if int(value) not in cache:
                    cache[int(value)] = activation_reference(int(value), mode, 14)
            reference[mode,i] = np.array([cache[int(v)] for v in x], dtype=np.int32)
            real = x.astype(np.float64)/16384
            mathematical[mode,i] = np.tanh(real) if mode==0 else 1/(1+np.exp(-real))
    results = []
    for kind in ('shared', 'independent'):
        text = (work/(kind+'.run.log')).read_text()
        assert 'PASS controlled evaluation' in text and 'Fatal:' not in text
        raw = np.loadtxt(work/(kind+'.raw'), dtype=np.int32).reshape(84,VECTORS*LANES,4)
        metrics = [dict(zip(FIELDS,map(int,line.split(',')[1:]))) for line in text.splitlines() if line.startswith('EVAL,')]
        assert len(metrics)==84
        for row in metrics:
            case, mode, workload, policy = (row[k] for k in ('case_id','mode','workload','policy'))
            values = raw[case]
            assert np.all(values[:,0]==case)
            assert np.array_equal(values[:,1], np.repeat(np.arange(VECTORS),LANES))
            assert np.array_equal(values[:,2], np.tile(np.arange(LANES),VECTORS))
            actual = values[:,3]
            target = reference[mode,workload]
            if policy<3:
                assert np.array_equal(actual,target), f'Exact baseline mismatch {kind} {case}'
            row.update(architecture=kind, policy_name=POLICIES[policy], function=('tanh','sigmoid')[mode],
                       distribution=data[workload]['distribution'], seed=data[workload]['seed'],
                       outputs=VECTORS*LANES, steady_outputs=(VECTORS-WARMUP)*LANES)
            row['outputs_per_cycle'] = VECTORS*LANES/row['total_cycles']
            row['steady_outputs_per_cycle'] = (VECTORS-WARMUP)*LANES/row['steady_output_window_cycles']
            row['simulated_moutputs_per_s_at_25mhz'] = row['outputs_per_cycle']*25
            row['mean_selected_iterations'] = row['selected_iterations_sum']/(VECTORS*LANES)
            row['mean_selected_iterations_steady'] = row['selected_iterations_steady_sum']/((VECTORS-WARMUP)*LANES)
            row['mathematical_error'] = error_metrics(actual.astype(float)/16384,mathematical[mode,workload])
            row['fixed14_error_lsb'] = error_metrics(actual.astype(float),target.astype(float))
            row['outputs_exceeding_8lsb_vs_fixed14'] = int(np.count_nonzero(np.abs(actual-target)>8))
            row['steady_mathematical_error'] = error_metrics(actual[WARMUP*LANES:].astype(float)/16384,
                                                            mathematical[mode,workload][WARMUP*LANES:])
            results.append(row)
    (work/'results.json').write_text(json.dumps(results, indent=2)+'\n')
    lines = ['CONTROLLED RTL EVALUATION', '',
        'Scope: activation array only; 4 lanes; Q14; full reference=14 iterations.',
        '168 cases, 8192 outputs/case; six deterministic workloads; two functions.',
        'Shared and per-lane reference engines use identical inputs and control policies.',
        'All policies reset learning state. Full-run results include startup; steady window excludes first 256 vectors.',
        'Mathematical errors use float64 tanh/sigmoid at the quantized input, not a fixed-point implementation as truth.',
        'Full-domain input grid is stratified, not exhaustive. Gaussian cases are synthetic, not trained-model data.',
        'No board, routed timing, energy, or model-accuracy claim is made.',
        'Selected iteration count is an algorithmic statistic, not energy or physical pipeline latency.',
        'sample_rate=0 means interval 256. Stall counters may overlap.', '',
        'Aggregate below: equal-size cases; mean outputs/cycle; worst mathematical error across all cases.',
        'architecture policy                       out/cycle  mean_iter   math_MAE  math_max  max_ref_LSB  >8LSB_count']
    aggregate = []
    for kind in ('shared','independent'):
        for policy in POLICIES:
            selected = [r for r in results if r['architecture']==kind and r['policy_name']==policy]
            entry = dict(architecture=kind,policy=policy,
                outputs_per_cycle=float(np.mean([r['outputs_per_cycle'] for r in selected])),
                mean_iterations=float(np.mean([r['mean_selected_iterations'] for r in selected])),
                mathematical_mae=float(np.mean([r['mathematical_error']['mae'] for r in selected])),
                mathematical_max=max(r['mathematical_error']['max_abs'] for r in selected),
                max_fixed14_error_lsb=max(r['fixed14_error_lsb']['max_abs'] for r in selected),
                beyond_8lsb=sum(r['outputs_exceeding_8lsb_vs_fixed14'] for r in selected))
            aggregate.append(entry)
            lines.append(f"{kind:11} {policy:27} {entry['outputs_per_cycle']:8.3f} {entry['mean_iterations']:10.3f} "
                         f"{entry['mathematical_mae']:10.6g} {entry['mathematical_max']:9.6g} {entry['max_fixed14_error_lsb']:12.0f} {entry['beyond_8lsb']:12}")
    lines += ['', 'Per-function, per-distribution and per-seed measurements are in results.json.',
              'Area comparisons require matching synthesis reports from area.tcl.',
              'Adaptive shared/per-lane results need not be bit-identical: feedback updates arrive at different input positions when throughput differs.']
    (work/'summary.txt').write_text('\n'.join(lines)+'\n')
    (work/'summary.json').write_text(json.dumps(aggregate,indent=2)+'\n')
    print('\n'.join(lines),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--work',type=Path,required=True)
    parser.add_argument('--vivado',type=Path,default=Path('C:/Xilinx/Vivado/2023.2/bin'))
    parser.add_argument('--run',action='store_true')
    parser.add_argument('--analyse',action='store_true')
    args=parser.parse_args()
    work=args.work.resolve()
    if args.run:
        run(work,args.vivado)
    if args.analyse:
        analyse(work)
    if not args.run and not args.analyse:
        prepare(work)
