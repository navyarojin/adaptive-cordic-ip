import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np


board=Path(__file__).resolve().parents[1]
root=board.parent
work=board/'work_row_compare'
work.mkdir(exist_ok=True)
sys.path.insert(0,str(board/'jupyter_streaming'))
from client import activation_reference

model=json.loads((board/'jupyter_streaming/model.json').read_text())
inputs=np.asarray(model['test_inputs'],dtype=np.int64)
sums=np.clip(inputs@np.asarray(model['weights1'],dtype=np.int64).T+model['bias1'],-262144,262143)
hidden=np.asarray([[activation_reference(int(v),0,14) for v in row] for row in sums],dtype=np.int64)
hidden=np.clip(np.sign(hidden)*((np.abs(hidden)+64)//128),-128,127)


def pack(values,width):
    return sum((int(v)&((1<<width)-1))<<(i*width) for i,v in enumerate(np.asarray(values).reshape(-1)))


records=[]
for start in range(0,len(inputs),64):
    count=min(64,len(inputs)-start)
    for layer,values in [(1,inputs),(2,hidden)]:
        for index in range(count):
            records.append((pack(values[start+index],8),pack(model[f'weights{layer}'],8),
                            pack(model[f'bias{layer}'],32),int(index==count-1)))
assert len(records)==542
for index,name,width in [(0,'acts',8),(1,'weights',32),(2,'bias',32),(3,'ends',1)]:
    (work/f'{name}.mem').write_text(''.join(f'{record[index]:0{width}x}\n' for record in records))
for name in ['mac_row_compare.sv','tb_mac_row_compare.sv']:
    shutil.copy2(board/'experiments'/name,work/name)
legacy=work/'legacy'
legacy.mkdir(exist_ok=True)
subprocess.run([sys.executable,str(board/'scripts/prepare_isolation.py'),'--out',str(legacy)],check=True)
text=(legacy/'tb_isolation.sv').read_text()
first=text.index('  zero_aware_systolic_npu_param legacy(')
last=text.index('  function automatic logic [31:0] random_value;')
text=text[:first]+'''  legacy_compare suite(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,
    .ready_o(ready),.out_valid_o(valid),.accumulations_o({result[4],result[3],result[2],result[1],result[0]}));
'''+text[last:]
(legacy/'tb_legacy_compare.sv').write_text('`define PHY_NETLIST\n'+text)
names=[('zero_aware','legacy'),('ungated','plain'),('retained','retained'),('zero_hold','isolated'),('zero_dual_hold','dual')]
parts=['''module legacy_compare(
 input wire clk,rst_n,clear_i,load_weights_i,in_valid_i,
 input wire [127:0] weights_i,
 input wire [31:0] activations_i,
 output wire [4:0] ready_o,out_valid_o,
 output wire [479:0] accumulations_o
);
 wire core_clk;
 BUFG clock_buffer(.I(clk),.O(core_clk));
''']
for index,(module,instance) in enumerate(names):
    parts.append(f''' (* KEEP_HIERARCHY="yes" *) {module}_systolic_npu_param {instance}(
 .clk(core_clk),.rst_n,.clear_i,.load_weights_i,.in_valid_i,.weights_i,.activations_i,
 .ready_o(ready_o[{index}]),.out_valid_o(out_valid_o[{index}]),.accumulations_o(accumulations_o[{index*96}+:96]));
''')
parts.append('endmodule\n')
(legacy/'legacy_compare.sv').write_text(''.join(parts))
files=[root/'rtl/mac.sv',root/'rtl/jobs.sv']+list(work.glob('*.mem'))
provenance=dict(records=len(records),batch_sizes=[64,64,64,64,15],inter_job_idle_clocks=104,
                layer1_input_zeros=int(np.count_nonzero(inputs==0)),layer2_input_zeros=int(np.count_nonzero(hidden==0)),
                sha256={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
                scope='MAC-only replay of real model operands and directed synthetic stress. Clocked common-wrapper SDF exports; no hand-merged delay files.')
(work/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
flat=board/'work_row_flat'
flat.mkdir(exist_ok=True)
for name in ['acts.mem','weights.mem','bias.mem','ends.mem','tb_mac_row_compare.sv']:
    shutil.copy2(work/name,flat/name)
for source,target in [(work/'mac_row_compare.sv',flat/'mac_row_compare.sv'),
                      (legacy/'legacy_compare.sv',flat/'legacy_compare.sv')]:
    body=source.read_text()
    assert 'KEEP_HIERARCHY="yes"' in body
    target.write_text(body.replace('KEEP_HIERARCHY="yes"','KEEP_HIERARCHY="no"'))
shutil.copy2(legacy/'tb_legacy_compare.sv',flat/'tb_legacy_compare.sv')
print(work)
