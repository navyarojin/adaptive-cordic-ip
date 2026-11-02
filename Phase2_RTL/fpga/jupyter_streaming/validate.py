"""Reproducible physical PYNQ validation; never substitutes mocks for board results.

Run with the PYNQ Python interpreter and hardware permissions. Reference checking
and telemetry collection are excluded from headline timing. Results retain the
exact overlay/software hashes and raw timing samples.
"""
import argparse
import hashlib
import json
import platform
import time
from pathlib import Path
import numpy as np
from bench import reference, stats
from client import activation_reference
from run import infer, infer_model


def hashes(folder):
    return {name: hashlib.sha256((folder / name).read_bytes()).hexdigest()
            for name in ('board.bit', 'board.hwh', 'client.py', 'stream.py',
                         'run.py', 'bench.py', 'model.json', 'validate.py')}


def open_npu(folder):
    from pynq import Overlay
    from stream import StreamingNPU
    npu = StreamingNPU(Overlay(str(folder / 'board.bit')), timeout=15)
    npu.wait_ready()
    if npu.lanes != 4 or npu.max_vectors != 64:
        raise RuntimeError('Expected four lanes and 64-vector banks')
    if npu.stream.read(0x34) & 0xFFFF0007 != 0x00010007:
        raise RuntimeError('Expected feature version 1 with fused/model support')
    npu.prepare_buffers()
    return npu


def fixed_reference(values, mode):
    return np.array([[activation_reference(int(v), mode, 14) for v in row]
                     for row in values], dtype=np.int32)


def wait_done(npu, bank):
    deadline = time.monotonic() + npu.timeout
    while not npu.stream.read(8) & (1 << (16 + bank)):
        npu._check_firmware()
        if time.monotonic() > deadline:
            raise TimeoutError('No completed bank')
        time.sleep(.0001)


def smoke(folder, values):
    npu = open_npu(folder)
    result = {'stream_modes': [], 'legacy_modes': [], 'two_banks': {}}
    try:
        for mode, name in enumerate(('tanh', 'sigmoid', 'relu', 'linear')):
            npu.submit(values, bank=mode % 2, tag=mode+1, mode=name,
                       min_iter=14, max_iter=14, full_iter=14, sample_rate=0)
            actual = npu.collect(mode % 2, check=True)
            if actual['passed'] is not True:
                raise AssertionError('Streaming mode mismatch: ' + name)
            result['stream_modes'].append({'mode': name, 'checked': int(values.size), 'passed': True})
            legacy = npu.run([[1,2,3,4],[-1,0,2,1],[2,1,0,-2],[0,3,-1,1]],
                             [2,0,-1,3], mode=name)
            if legacy['passed'] is not True:
                raise AssertionError('Legacy mode mismatch: ' + name)
            result['legacy_modes'].append({'mode': name, 'checked_raw_and_activated': 8, 'passed': True})
        for bank in (0, 1):
            npu.submit(values, bank=bank, tag=0x1100+bank, mode='tanh', sample_rate=0)
        try:
            npu.submit(values, bank=0, tag=0x2200)
        except RuntimeError:
            result['two_banks']['owned_bank_rejected'] = True
        else:
            raise AssertionError('Owned bank was accepted')
        for bank in (1, 0):
            r = npu.collect(bank, check=True)
            if r['passed'] is not True or r['tag'] != 0x1100+bank:
                raise AssertionError('Bank/tag mismatch')
        if npu.stream.read(8) & 0x30300:
            raise AssertionError('Banks not released')
        result['two_banks'].update(checked=512, reverse_collection_passed=True)
        result['firmware_status'] = npu.status()
    finally:
        npu.close()
    return result


def policy_run(folder, values, name, config, runs, warmups):

    npu = open_npu(folder)
    expected = fixed_reference(values, 0)
    samples, submits, collects, errors, counters = [], [], [], [], []
    try:
        for repeat in range(warmups + runs):
            bank = repeat % 2
            start = time.perf_counter_ns()
            npu.submit(values, bank=bank, tag=repeat+1, mode='tanh', **config)
            submitted = time.perf_counter_ns()
            actual = npu.collect(bank, check=False)['actual']
            end = time.perf_counter_ns()

            difference = np.abs(actual.astype(np.int64) - expected.astype(np.int64))
            if config['min_iter'] == 14 or (config['sample_rate'] == 1 and config['threshold'] == 0):
                np.testing.assert_array_equal(actual, expected)
            if repeat >= warmups:
                samples.append((end-start)/1000)
                submits.append((submitted-start)/1000)
                collects.append((end-submitted)/1000)
                errors.extend(difference.ravel().tolist())

        npu.submit(values, bank=0, tag=0x7000, mode='tanh', **config)
        wait_done(npu, 0)
        counters = npu.hardware_counters(0)
        actual = npu.collect(0, check=False)['actual']
        telemetry = []
        for lane in range(4):
            address = 0x100 + lane * 0x20
            telemetry.append(dict(lane=lane, samples=npu.stream.read(address),
                                  max_residual=npu.stream.read(address+8),
                                  fallbacks=npu.stream.read(address+4),
                                  flags=npu.stream.read(address+12)))
    finally:
        npu.close()
    timing = stats(samples)
    return dict(name=name, policy=config, runs=runs, warmups=warmups,
                outputs_per_batch=int(values.size), timing_us=timing,
                submit_us=stats(submits), collect_us=stats(collects), raw_us=samples,
                outputs_per_second_from_median=values.size*1e6/timing['median'],
                checked_outputs=runs*int(values.size),
                max_abs_error_codes=int(max(errors)), mean_abs_error_codes=float(np.mean(errors)),
                max_abs_error_real=max(errors)/16384,
                differs_from_fixed14=int(np.count_nonzero(errors)),
                diagnostic_hardware_counters=counters, cumulative_lane_telemetry=telemetry,
                scope='Physical board activation API: submit through collect/release; reference checks and diagnostic counters outside timing. Adaptive errors characterize this corpus only, not a universal bound. No energy claim.')


def row_gating_run(folder):
    npu = open_npu(folder)
    rng = np.random.RandomState(20261029)
    values = rng.randint(-128, 128, size=(16, 4)).astype(np.int32)
    values[0] = [-128, 127, 0, -1]
    cases = []
    try:
        for mode, name in enumerate(('tanh', 'sigmoid', 'relu', 'linear')):
            for pair in range(8):
                for bank in (0, 1):
                    mask = pair * 2 + bank
                    weights = rng.randint(-128, 128, size=(4, 4)).astype(np.int32)
                    for row in range(4):
                        if not mask & (1 << row):
                            weights[row] = 0
                    bias = [819, -819, 2147483647, -2147483648]
                    npu.submit(values, bank=bank, tag=0x5000 + mode*16 + mask,
                               weights=weights, bias=bias, right_shift=mask*2,
                               mode=name, min_iter=14, max_iter=14, full_iter=14,
                               sample_rate=0)
                for bank in (1, 0):
                    mask = pair * 2 + bank
                    result = npu.collect(bank, check=True)
                    if result['passed'] is not True or result['tag'] != 0x5000 + mode*16 + mask:
                        raise AssertionError('Row-mask/bias/queued-weight mismatch')
                    cases.append(dict(mode=name, row_mask=mask, bank=bank,
                                      checked_outputs=int(values.size), passed=True))
    finally:
        npu.close()
    return dict(cases=cases, checked_outputs=sum(c['checked_outputs'] for c in cases),
                scope='All sixteen row masks, nonzero/extreme biases, shifts, four activation modes, queued changing weights and reverse bank collection.')


def model_run(folder, runs, warmups):
    model = json.loads((folder/'model.json').read_text())
    values = np.asarray(model['test_inputs'], dtype=np.int32)
    labels = np.asarray(model['test_labels'], dtype=np.int32)
    expected = reference(values, model)[1][:, 0]
    result = {}
    for name, function in (('host_chained', infer), ('autonomous', infer_model)):
        npu = open_npu(folder)
        timings = []
        actual = None
        try:
            if name == 'autonomous':
                npu.load_model(model)
            for repeat in range(warmups+runs):
                start = time.perf_counter_ns()
                actual = function(npu, values, model, check=False)
                elapsed = (time.perf_counter_ns()-start)/1000
                np.testing.assert_array_equal(actual, expected)
                if repeat >= warmups:
                    timings.append(elapsed)
        finally:
            npu.close()
        timing = stats(timings)
        correct = int(np.count_nonzero((actual>=8192)==labels))
        result[name] = dict(samples=len(values), correct=correct, accuracy=correct/len(values),
                            timing_us=timing, raw_us=timings, runs=runs,
                            exact_checked_outputs=runs*len(values),
                            classifications_per_second=len(values)*1e6/timing['median'])


    cpu_times = []
    for repeat in range(warmups+runs):
        start=time.perf_counter_ns()
        actual=reference(values,model)[1][:,0]
        elapsed=(time.perf_counter_ns()-start)/1000
        np.testing.assert_array_equal(actual,expected)
        if repeat>=warmups:cpu_times.append(elapsed)
    result['cpu_fixed14_python'] = dict(timing_us=stats(cpu_times),raw_us=cpu_times,
        implementation='Python integer fixed14 CORDIC reference; not an optimized C/NEON baseline')
    cpu_median=result['cpu_fixed14_python']['timing_us']['median']
    for name in ('host_chained','autonomous'):
        result[name]['cpu_python_median_divided_by_fpga_median']=cpu_median/result[name]['timing_us']['median']
    result['scope']='Same preprocessed Q7 test rows to Q14 probabilities. Excludes normalization, allocation, one-time model load and checks; includes both layers and transfers/control in FPGA workflows. Python baseline is bit-exact but interpreted, not an optimized CPU performance ceiling.'
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--runs',type=int,default=100);p.add_argument('--warmups',type=int,default=5)
    p.add_argument('--model-runs',type=int,default=20);p.add_argument('--output',default='board_validation.json')
    a=p.parse_args()
    if min(a.runs,a.model_runs)<1 or a.warmups<0:p.error('Invalid counts')
    folder=Path(__file__).resolve().parent
    rng=np.random.RandomState(20261028)
    values=rng.randint(-131072,131073,size=(64,4)).astype(np.int32)
    report=dict(started_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
                execution='physical_pynq',platform=platform.platform(),hashes=hashes(folder),
                corpus_seed=20261028,corpus_sha256=hashlib.sha256(values.tobytes()).hexdigest())
    output=Path(a.output)
    def save():output.write_text(json.dumps(report,indent=2)+'\n')
    try:
        report['smoke']=smoke(folder,values);save();print('PASS four modes, legacy modes and two-bank ownership',flush=True)
        report['row_gating']=row_gating_run(folder);save();print('PASS all row masks, bias bypass, queued weight changes and four activation modes',flush=True)
        policies=[('fixed14',dict(min_iter=14,max_iter=14,full_iter=14,threshold=0,sample_rate=0,freeze=True)),
                  ('adaptive_every_input',dict(min_iter=6,max_iter=14,full_iter=14,threshold=0,sample_rate=1)),
                  ('adaptive_interval32',dict(min_iter=6,max_iter=14,full_iter=14,threshold=8,sample_rate=32)),
                  ('adaptive_interval256',dict(min_iter=6,max_iter=14,full_iter=14,threshold=8,sample_rate=0))]
        report['policies']=[]
        for name,cfg in policies:
            r=policy_run(folder,values,name,cfg,a.runs,a.warmups);report['policies'].append(r);save()
            print('PASS policy %s median %.2f us, max error %d codes'%(name,r['timing_us']['median'],r['max_abs_error_codes']),flush=True)
        report['models']=model_run(folder,a.model_runs,a.warmups);save()
        print('PASS host-chained and autonomous models against exact reference',flush=True)

        report['power_measurement']=dict(status='not_measured',reason='No calibrated rail/current measurement supplied; switching estimates are separate from physical power.')
        report['status']='passed'
    except Exception as exc:
        report['status']='failed';report['error']=str(exc);save();raise
    finally:
        report['completed_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime());save()
    print('Saved '+str(output),flush=True)


if __name__=='__main__':main()
