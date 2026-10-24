"""Assemble verified RTL, synthesis and application results; render scientific figures."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[2]

def resource(path,label):
    match=re.search(r'\|\s*'+re.escape(label)+r'\*?\s*\|\s*([\d,]+)',path.read_text())
    if not match: raise ValueError('Missing '+label+' in '+str(path))
    return int(match.group(1).replace(',',''))

def main(args):
    out=args.out.resolve(); out.mkdir(parents=True,exist_ok=True)
    sweep=args.sweep.resolve(); modeldir=args.model.resolve(); synth=args.resources.resolve(); fixed=args.fixed.resolve()
    aggregate=json.loads((sweep/'summary.json').read_text())
    details=json.loads((sweep/'results.json').read_text())
    app=json.loads((modeldir/'app.json').read_text())
    model=json.loads((modeldir/'model.json').read_text())
    assert len(details)==168 and len(app)==7
    fixedlog=(fixed/'fixed.run.log').read_text()
    assert 'PASS fixed-only baseline' in fixedlog and 'Fatal:' not in fixedlog
    fixed_metrics=[list(map(int,line.split(',')[1:])) for line in fixedlog.splitlines() if line.startswith('FIXED_EVAL,')]
    assert len(fixed_metrics)==12 and all(row[2:]==[93,2141,1792] for row in fixed_metrics)
    resources={}
    for kind in ('fixed','shared','independent'):
        path=synth/(("indep" if kind=="independent" else kind)+'_area.rpt')
        resources[kind]={k:resource(path,label) for k,label in [('lut','Slice LUTs'),('ff','Slice Registers'),('dsp','DSPs')]}
        shutil.copyfile(path,out/path.name)
        shutil.copyfile(synth/(("indep" if kind=="independent" else kind)+'_time.rpt'),out/(("indep" if kind=="independent" else kind)+'_time.rpt'))
    def get(kind,policy): return next(r for r in aggregate if r['architecture']==kind and r['policy']==policy)
    sf=get('shared','fixed14_s256'); independent=get('independent','fixed14_s256')
    area_saving=100*(1-resources['shared']['lut']/resources['independent']['lut'])
    throughput_loss=100*(1-sf['outputs_per_cycle']/independent['outputs_per_cycle'])
    extra_vs_fixed=100*(resources['shared']['lut']/resources['fixed']['lut']-1)
    report=[
        'CONTROLLED EVALUATION: FINDINGS AND LIMITS',
        '',
        'Conclusion: reference sharing demonstrates an area/throughput trade-off inside the adaptive-capable design.',
        'The present adaptive design does NOT demonstrate an advantage over a lean fixed14 implementation in measured area, throughput or mathematical accuracy.',
        'Lower selected iteration counts do not establish lower energy or shorter fixed-pipeline latency.',
        '',
        'EXPERIMENT',
        '168 adaptive-capable array cases: 2 reference architectures x 7 policies x 2 functions x 3 distributions x 2 seeds.',
        '12 additional fixed-only array cases; total 1,474,560 checked array outputs.',
        '4 lanes, signed19 Q14 inputs, signed16 Q14 outputs, full-reference budget14, 2048 vectors/case.',
        'Inputs: stratified full signed range, central Gaussian, and Gaussian distribution shift; seeds7/23.',
        'Learning is reset per case. Cold-inclusive and post-256-vector windows are both recorded.',
        'Same stimuli, output ordering, control policies, FPGA target xc7z020clg400-1 and 40ns clock constraint.',
        'Synthesis is out of context, not routed; resource estimates exclude CV32, DMA, buffering and the fused MAC.',
        'Fixed-only baseline has compile-time 14 iterations and no adaptive/reference capability; the other designs retain runtime adaptation.',
        '',
        'AREA AND THROUGHPUT (fixed14 execution; sampling interval256 in adaptive-capable designs)',
        'architecture          LUT       FF     DSP   outputs/cycle (includes initial fill)',
    ]
    for kind,rate in [('fixed',8192/2141),('shared',sf['outputs_per_cycle']),('independent',independent['outputs_per_cycle'])]:
        r=resources[kind]
        report.append(f"{kind:16} {r['lut']:8} {r['ff']:8} {r['dsp']:7} {rate:14.6f}")
    report += [
        f'Reference sharing saves {area_saving:.2f}% LUTs vs per-lane references, with {throughput_loss:.2f}% lower cold-inclusive throughput at interval256.',
        'That particular comparison produces identical fixed14 outputs; it is a valid conditional area/throughput result.',
        f'Shared adaptive-capable hardware uses {extra_vs_fixed:.2f}% more LUTs than the fixed-only baseline and has lower throughput.',
        'At sampling interval1, the shared path serializes reference requests; see the full policy table and plot.',
        '',
        'NUMERICAL ACCURACY',
        'Float64 mathematical tanh/sigmoid at the quantized input are the accuracy targets; fixed14 RTL is separately used for implementation checks.',
        'Global errors include unsampled outputs, not just the controller residual counters.',
        'An error threshold of 8 LSB is NOT a bound on every output.',
    ]
    for policy in ('fixed14_s256','adaptive_s1_e0','adaptive_s32_e0','adaptive_s32_e8','adaptive_s256_e8','frozen_seed_s32_e8'):
        r=get('shared',policy)
        report.append(f"{policy}: mean iterations={r['mean_iterations']:.3f}; mean mathematical MAE={r['mathematical_mae']:.8g}; "
                      f"worst mathematical error={r['mathematical_max']:.8g}; worst deviation from fixed14={r['max_fixed14_error_lsb']:.0f} LSB; "
                      f"outputs beyond8LSB={r['beyond_8lsb']} / 98304.")
    report += [
        'The fixed14 mathematical error is not zero. Exact agreement with fixed14 must not be described as exact mathematical activation.',
        'Selected iterations are summed on accepted inputs. They are not counts of clock cycles, switched gates, or joules.',
        'Shared/per-lane learning trajectories can differ because feedback arrives at different input positions under stalls.',
        '',
        'REAL DATASET APPLICATION',
        model['citation'],
        'Dataset license: CC BY 4.0. Original dataset and its hash are included in the evidence archive.',
        f"1372 rows; {model['duplicates_removed']} duplicate rows removed before splitting; {model['unique_rows']} unique rows.",
        'Stratified split: '+', '.join(f"{name}={len(ids)}" for name,ids in model['split_original_row_ids'].items())+'.',
        'Train-only normalization; seeds7/23/41; checkpoint/seed chosen by validation loss; no test-set model selection.',
        'Network: 4 inputs -> 4 tanh -> 1 sigmoid, Q7 weights/inputs/hidden outputs, Q14 bias, output layer padded to four lanes.',
        'Actual fused RTL executes both layers in batches of up to64; inter-layer requantization is performed by the testbench/host.',
        f"Float and quantized mathematical test accuracy: {100*model['float_test_accuracy']:.3f}% and {100*model['quantized_math_test_accuracy']:.3f}%.",
    ]
    for r in app:
        report.append(f"{r['policy']}: {r['correct']}/{r['samples']} correct ({100*r['accuracy']:.3f}%); "
                      f"changed predictions vs fixed14={r['changed_predictions_vs_fixed14']}; "
                      f"sum of kernel windows={r['sum_kernel_cycles']} cycles.")
    report += [
        f"Fixed14 accuracy Wilson95 interval: [{100*app[0]['wilson95'][0]:.2f}%, {100*app[0]['wilson95'][1]:.2f}%].",
        'Identical predictions on271 held-out samples are an observation, not proof of equivalence on other data.',
        'Kernel-cycle sums exclude host transfers, CPU/DMA, job setup and inter-layer conversion; they are not end-to-end inference latency.',
        '',
        'PUBLICATION ASSESSMENT',
        'Supported: verified implementation, conditional reference-sharing trade-off, and small real-dataset application validation.',
        'Unsupported: state-of-the-art superiority; energy efficiency; hard global error bounds from sampled residuals; large-model performance.',
        'Current fixed-only baseline dominates the adaptive-capable design on the measured area/throughput/accuracy dimensions.',
        'To establish an adaptive advantage, measure workload-annotated switching/board energy or redesign iteration-dependent work so it produces a real benefit.',
        'A second larger representative workload and routed board measurements are still needed for a stronger paper.',
        '',
        'REPRODUCIBILITY',
        'See reproduce.txt for commands; manifest.json for source/stimulus hashes; model.json for split IDs, normalization, training selection and weights.',
        'results.json contains every workload/seed/function result; app.json contains paired prediction changes and confidence intervals.',
        'evidence.zip contains raw RTL outputs/logs, stimuli, exact training-script snapshot, dataset, and RTL/source snapshots.',
        'No deployed bitstream or HWH was changed by this evaluation.'
    ]
    (out/'evaluation.txt').write_text('\n'.join(report)+'\n')
    for name in ('manifest.json','results.json','summary.json','summary.txt'):
        shutil.copyfile(sweep/name,out/name)
    for name in ('model.json','model.mem','inputs.mem','app.json','application_summary.txt'):
        shutil.copyfile(modeldir/name,out/name)
    (out/'resources.json').write_text(json.dumps(resources,indent=2)+'\n')
    reproduce='''Run from the project root with Python+NumPy and Vivado 2023.2 installed.
Use fresh work directories to preserve existing evidence.

python "Phase2_ RTL/evaluation/comparison/sweep.py" --work <sweep-work> --run --analyse
vivado -mode batch -source "Phase2_ RTL/fpga/scripts/area.tcl" -tclargs <resource-work>
vivado -mode batch -source "Phase2_ RTL/fpga/scripts/fixed.tcl" -tclargs <resource-work>

Fixed-only simulation: copy sweep-work/stimulus.mem to a fresh fixed-work directory.
Compile div_stream.sv, act_stream.sv, ref.sv,
fixed.sv and tb_fixed.sv with xvlog -sv.
Elaborate tb_fixed_evaluation with xelab --timescale 1ns/1ps and run xsim -runall;
save stdout as fixed-work/fixed.run.log.

python "Phase2_ RTL/evaluation/comparison/model.py" --work <model-work>
& "Phase2_ RTL/evaluation/comparison/run.ps1" -Work <model-work>
python "Phase2_ RTL/evaluation/comparison/model.py" --work <model-work> --analyse
python "Phase2_ RTL/evaluation/comparison/report.py" --sweep <sweep-work> --model <model-work> --resources <resource-work> --fixed <fixed-work> --out <report-directory>
Plotting requires matplotlib. Optional --plot-deps points to an isolated installation.

The downloaded dataset is CC BY4.0; cite Lohweg (2012), DOI10.24432/C55P57.
No external pretrained weights are used: the compatible small model is trained reproducibly.
The final trainer text corrects a report label; trainer_used.py preserves the exact source used for training.
'''
    (out/'reproduce.txt').write_text(reproduce)
    with zipfile.ZipFile(out/'evidence.zip','w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
        for directory,names,prefix in [
            (sweep,['stimulus.mem','shared.raw','independent.raw','shared.run.log','independent.run.log'],'sweep'),
            (modeldir,['model.raw','model.run.log','data_banknote_authentication.txt','trainer_used.py'],'application'),
            (fixed,['fixed.run.log'],'fixed')]:
            for name in names: archive.write(directory/name,prefix+'/'+name)
        manifest=json.loads((sweep/'manifest.json').read_text())
        for name in manifest['source_sha256']: archive.write(ROOT/name,'source/'+name)
        for name in ('evaluation/comparison/sweep.py','evaluation/comparison/model.py',
                     'evaluation/comparison/fixed.sv','fpga/sim/tb_fixed.sv',
                     'fpga/sim/tb_model.sv','fpga/jupyter_streaming/client.py',
                     'fpga/scripts/area.tcl','fpga/scripts/fixed.tcl',
                     'evaluation/comparison/run.ps1','evaluation/comparison/report.py'):
            archive.write(ROOT/name,'source/'+name)
    if args.plot_deps: sys.path.insert(0,str(args.plot_deps.resolve()))
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    fig,axs=plt.subplots(2,2,figsize=(15,10),layout='constrained')
    colors=['#47677f','#d08836','#7861a5']
    kinds=['fixed','shared','independent']
    axs[0,0].bar(['Fixed-only','Shared reference','Per-lane reference'],[resources[k]['lut'] for k in kinds],color=colors)
    axs[0,0].set(title='Matched FPGA synthesis: array LUT use',ylabel='LUTs (out-of-context synthesis)')
    for i,k in enumerate(kinds): axs[0,0].text(i,resources[k]['lut']+500,f"{resources[k]['lut']:,}",ha='center')
    axs[0,0].set_ylim(0,44000)
    labels=['Fixed /256','Fixed /1','Adapt /1 e0','Adapt /32 e0','Adapt /32 e8','Adapt /256 e8','Frozen /32 e8']
    policies=[r['policy'] for r in aggregate if r['architecture']=='shared']
    positions=np.arange(7)
    for offset,kind,color in [(-.18,'shared',colors[1]),(.18,'independent',colors[2])]:
        axs[0,1].bar(positions+offset,[get(kind,p)['outputs_per_cycle'] for p in policies],width=.36,label=kind,color=color)
    axs[0,1].axhline(8192/2141,color=colors[0],ls='--',label='Fixed-only')
    axs[0,1].set_xticks(positions,labels,rotation=25,ha='right')
    axs[0,1].set(title='RTL throughput: full 2,048-vector windows',ylabel='Activation outputs / clock cycle')
    axs[0,1].legend(fontsize=9)
    shared=[get('shared',p) for p in policies]
    axs[1,0].bar(positions,[r['mathematical_max'] for r in shared],color=colors[1])
    axs[1,0].axhline(shared[0]['mathematical_max'],color=colors[0],ls='--',label='Fixed14 worst error')
    axs[1,0].set_xticks(positions,labels,rotation=25,ha='right')
    axs[1,0].set(title='Shared-reference worst mathematical error',ylabel='Max absolute tanh/sigmoid error')
    axs[1,0].legend(fontsize=9)
    axs[1,1].bar(positions,[r['sum_kernel_cycles'] for r in app],color=colors[1])
    axs[1,1].set_xticks(positions,labels,rotation=25,ha='right')
    axs[1,1].set(title='Banknote application: 266/271 correct for every policy',ylabel='Sum of kernel cycles over 271 test inputs')
    fig.suptitle('Controlled evaluation: sharing saves area; adaptation has no proven speed or energy advantage',fontsize=14)
    fig.supxlabel('/N: reference interval; e: sampled residual threshold in Q14 LSB. Simulation/synthesis only; no board or power measurements.',fontsize=9)
    fig.savefig(out/'tradeoffs.png',dpi=180)
    fig.savefig(out/'tradeoffs.svg')
    plt.close(fig)
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file() and p.name!='artifact_sha256.json'}
    (out/'artifact_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
    print(out/'evaluation.txt')
    print(f'Sharing: LUT reduction {area_saving:.2f}%; throughput loss {throughput_loss:.2f}%; LUT overhead vs fixed {extra_vs_fixed:.2f}%')

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ('sweep','model','resources','fixed','out'): p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--plot-deps',type=Path)
    main(p.parse_args())
