"""Train a reproducible Q7 4-4-1 application demo; never select using test data."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import sys
import urllib.request
import zipfile
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
URL='https://archive.ics.uci.edu/static/public/267/banknote%2Bauthentication.zip'

def rnd(x):
    return np.sign(x)*np.floor(np.abs(x)+.5)

def q(x,scale):
    return rnd(x*scale)/scale

def forward(p,x,quantized=True):
    w,b,v,c=p
    if quantized:
        x=q(x,128); w=q(w,128); v=q(v,128); b=q(b,16384); c=q(c,16384)
    hidden=np.tanh(x@w+b)
    h=np.clip(q(hidden,128),-1,127/128) if quantized else hidden
    logits=h@v+c
    prediction=1/(1+np.exp(-logits))
    return prediction,hidden,h

def score(p,x,y,quantized=True):
    prediction=forward(p,x,quantized)[0]
    loss=float(-np.mean(y*np.log(prediction+1e-12)+(1-y)*np.log(1-prediction+1e-12)))
    return loss,float(np.mean((prediction>=.5)==y))

def train(x,y,vx,vy,seed):
    rng=np.random.default_rng(seed)
    p=[rng.normal(0,.35,(4,4)),np.zeros(4),rng.normal(0,.35,(4,1)),np.zeros(1)]
    m=[np.zeros_like(a) for a in p]; vv=[np.zeros_like(a) for a in p]
    best_loss=float('inf'); best=None; step=0; best_epoch=0
    for epoch in range(1,1601):
        indices=rng.permutation(len(x))
        for start in range(0,len(x),64):
            ids=indices[start:start+64]; xx=q(x[ids],128); yy=y[ids]
            prob,hidden,h=forward(p,xx)
            dz=(prob-yy)/len(ids)
            dh=(dz@q(p[2],128).T)*(1-hidden**2)
            gradients=[xx.T@dh,dh.sum(axis=0),h.T@dz,dz.sum(axis=0)]
            step+=1
            for i,g in enumerate(gradients):
                m[i]=.9*m[i]+.1*g; vv[i]=.999*vv[i]+.001*g*g
                p[i]-=.01*(m[i]/(1-.9**step))/(np.sqrt(vv[i]/(1-.999**step))+1e-8)
                p[i]=np.clip(p[i],-127/128,127/128) if i in (0,2) else np.clip(p[i],-4,4)
        if epoch%20==0:
            loss,accuracy=score(p,vx,vy)
            if loss<best_loss:
                best_loss=loss; best=[a.copy() for a in p]; best_epoch=epoch
    return best,dict(seed=seed,epoch=best_epoch,validation_loss=best_loss,validation_accuracy=score(best,vx,vy)[1])

def prepare(work):
    work.mkdir(parents=True,exist_ok=True)
    (work/'trainer_used.py').write_bytes(Path(__file__).read_bytes())
    path=work/'data_banknote_authentication.txt'
    if not path.exists():
        data=urllib.request.urlopen(URL,timeout=60).read()
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            path.write_bytes(archive.read('data_banknote_authentication.txt'))
    raw=np.loadtxt(path,delimiter=',')
    assert raw.shape==(1372,5) and np.isfinite(raw).all() and set(raw[:,-1])=={0.,1.}

    _,ids=np.unique(raw,axis=0,return_index=True)
    ids=np.sort(ids); unique=raw[ids]
    assert len(np.unique(unique[:,:4],axis=0))==len(unique), 'Conflicting labels for identical features'
    rng=np.random.default_rng(20261014)
    groups=[[],[],[]]
    for label in (0,1):
        indices=np.flatnonzero(unique[:,-1]==label); rng.shuffle(indices)
        a=int(.6*len(indices)); b=a+int(.2*len(indices))
        for group,chunk in zip(groups,(indices[:a],indices[a:b],indices[b:])): group.extend(chunk)
    groups=[np.array(g,dtype=int) for g in groups]
    for g in groups: rng.shuffle(g)
    tr,va,te=groups
    mean=unique[tr,:4].mean(axis=0)
    scale=np.max(np.abs(unique[tr,:4]-mean),axis=0)/.95
    normalized=(unique[:,:4]-mean)/scale
    x=np.clip(normalized,-1,127/128); y=unique[:,-1:].copy()
    candidates=[]
    for seed in (7,23,41):
        p,selection=train(x[tr],y[tr],x[va],y[va],seed)
        candidates.append((p,selection)); print('Validation candidate:',selection,flush=True)
    p,selection=min(candidates,key=lambda item:item[1]['validation_loss'])
    w1=rnd(p[0]*128).astype(int).T; b1=rnd(p[1]*16384).astype(int)
    w2=np.zeros((4,4),dtype=int); w2[0]=rnd(p[2][:,0]*128).astype(int)
    b2=np.zeros(4,dtype=int); b2[0]=int(rnd(p[3][0]*16384))
    inputs=rnd(x[te]*128).astype(int)
    def packed(w): return [sum((int(w[r,c])&255)<<(8*c) for c in range(4)) for r in range(4)]
    words=[len(te),*packed(w1),*map(int,b1),*packed(w2),*map(int,b2)]
    (work/'model.mem').write_text(''.join(f'{v&0xffffffff:08x}\n' for v in words))
    (work/'inputs.mem').write_text(''.join(f'{int(v)&0xffffffff:08x}\n' for v in inputs.ravel()))
    model=dict(dataset='UCI Banknote Authentication',citation='Lohweg, V. (2012). Banknote Authentication. UCI Machine Learning Repository. https://doi.org/10.24432/C55P57',
        license='CC BY 4.0',url=URL,data_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        original_rows=1372,unique_rows=len(unique),duplicates_removed=1372-len(unique),
        split_seed=20261014,split_original_row_ids={name:ids[g].tolist() for name,g in zip(('train','validation','test'),groups)},
        architecture='4 inputs -> 4 tanh -> 1 sigmoid; output layer padded to 4 lanes',
        normalization_mean=mean.tolist(),normalization_scale=scale.tolist(),
        test_clipped_feature_values=int(np.count_nonzero(normalized[te]!=x[te])),
        candidates=[s for _,s in candidates],selected=selection,epochs_max=1600,
        selection_rule='Lowest validation binary cross entropy; test labels not used for selection',
        training='NumPy Adam; batch64; lr0.01; Q7 weights/hidden STE; Q14 bias; weight clipping +/-127/128',
        float_parameters=[a.tolist() for a in p],weights1=w1.tolist(),bias1=b1.tolist(),weights2=w2.tolist(),bias2=b2.tolist(),
        test_labels=y[te,0].astype(int).tolist(),test_inputs=inputs.tolist(),
        float_test_accuracy=score(p,x[te],y[te],False)[1],quantized_math_test_accuracy=score(p,x[te],y[te],True)[1],
        quantized_math_probabilities=forward(p,x[te],True)[0][:,0].tolist(),
        numpy_version=np.__version__,trainer_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (work/'model.json').write_text(json.dumps(model,indent=2)+'\n')
    print('Selected validation model:',selection,flush=True)
    print('Rows:',[len(g) for g in groups], 'Float test:',model['float_test_accuracy'],
          'Quantized math test:',model['quantized_math_test_accuracy'],flush=True)

def analyse(work):
    sys.path.insert(0,str(ROOT/'fpga/jupyter_streaming'))
    from client import activation_reference
    from sweep import POLICIES
    model=json.loads((work/'model.json').read_text())
    labels=np.array(model['test_labels']); n=len(labels)
    inputs=np.array(model['test_inputs'],dtype=np.int64)
    sums=inputs@np.array(model['weights1'],dtype=np.int64).T+model['bias1']
    sums=np.clip(sums,-262144,262143)
    hidden=np.array([[activation_reference(int(v),0,14) for v in row] for row in sums])
    hidden=np.clip(rnd(hidden/128),-128,127).astype(np.int64)
    logits=hidden@np.array(model['weights2'],dtype=np.int64).T+model['bias2']
    fixed=np.array([activation_reference(int(v),1,14) for v in np.clip(logits[:,0],-262144,262143)])
    data=np.loadtxt(work/'model.raw',dtype=np.int64).reshape(7,n,3)
    results=[]
    for policy in range(7):
        assert np.all(data[policy,:,0]==policy) and np.array_equal(data[policy,:,1],np.arange(n))
        actual=data[policy,:,2]
        if policy<3: assert np.array_equal(actual,fixed), 'Fixed/reference sampled RTL differs from Python model'
        predictions=(actual>=8192).astype(int)
        confusion=[[int(np.count_nonzero((labels==r)&(predictions==c))) for c in (0,1)] for r in (0,1)]
        hits=int(np.count_nonzero(predictions==labels)); proportion=hits/n; z=1.96
        center=(proportion+z*z/(2*n))/(1+z*z/n)
        half=z*np.sqrt(proportion*(1-proportion)/n+z*z/(4*n*n))/(1+z*z/n)
        results.append(dict(policy=POLICIES[policy],samples=n,correct=hits,accuracy=proportion,
            wilson95=[float(center-half),float(center+half)],confusion=confusion,
            changed_predictions_vs_fixed14=int(np.count_nonzero(predictions!=(fixed>=8192))),
            probability_mae_vs_fixed14=float(np.mean(np.abs(actual-fixed))/16384),
            probability_max_vs_fixed14=float(np.max(np.abs(actual-fixed))/16384)))
    text=(work/'model.run.log').read_text()
    assert 'PASS banknote model' in text and 'Fatal:' not in text
    for line in text.splitlines():
        if line.startswith('MODEL_CYCLES,'):
            _,policy,cycles=line.split(','); results[int(policy)]['sum_kernel_cycles']=int(cycles)
    (work/'app.json').write_text(json.dumps(results,indent=2)+'\n')
    lines=['BANKNOTE APPLICATION DEMONSTRATION',model['citation'],'License: '+model['license'],
        f"Rows: {model['original_rows']} original; {model['unique_rows']} after deduplication.",
        'Training/validation/test separation and train-only normalization are recorded in model.json.',
        f"Float test accuracy: {model['float_test_accuracy']:.6f}",
        f"Quantized mathematical test accuracy: {model['quantized_math_test_accuracy']:.6f}",
        'RTL uses real fused job engine, 64-vector batches, tanh then sigmoid.',
        'Inter-layer Q14->Q7 conversion is testbench/host work; no autonomous two-layer hardware scheduler.',
        'Test labels are held out. This small feature-based classification task is not large-model validation.',
        'Cycles sum kernel input-to-last-output windows; exclude host transfers, quantization, CPU and DMA.',
        'policy                       correct/total accuracy  changed vs fixed14  kernel cycles']
    for row in results:
        lines.append(f"{row['policy']:28} {row['correct']:3}/{n:<3} {row['accuracy']:.6f} {row['changed_predictions_vs_fixed14']:18} {row['sum_kernel_cycles']:14}")
    (work/'application_summary.txt').write_text('\n'.join(lines)+'\n')
    print('\n'.join(lines))

def autonomous_vectors(work):
    """Export frozen inputs and exact fixed14 golden output without retraining."""
    import shutil
    sys.path.insert(0, str(ROOT/'fpga/jupyter_streaming'))
    from bench import reference
    source=ROOT/'evaluation/data'
    model=json.loads((source/'model.json').read_text())
    work.mkdir(parents=True,exist_ok=True)
    for name in ('model.mem','inputs.mem'):
        shutil.copyfile(source/name,work/name)
    output=reference(model['test_inputs'],model)[1][:,0]
    (work/'gold.mem').write_text(''.join(f'{int(v)&0xffffffff:08x}\n' for v in output))
    print('Frozen autonomous model test vectors:',work)

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--work',type=Path,required=True)
    parser.add_argument('--analyse',action='store_true'); parser.add_argument('--autonomous-vectors',action='store_true'); args=parser.parse_args()
    if args.autonomous_vectors: autonomous_vectors(args.work.resolve())
    elif args.analyse: analyse(args.work.resolve())
    else: prepare(args.work.resolve())
