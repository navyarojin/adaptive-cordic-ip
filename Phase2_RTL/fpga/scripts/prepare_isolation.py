import argparse
import hashlib
import json
import shutil
from pathlib import Path

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args()
    board=Path(__file__).resolve().parents[1]
    source=board.parent/'rtl/systolic_cfg.sv'
    text=source.read_text()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    a="(valid_in && activation_in != 0) ? activation_in : '0"
    w="(valid_in && activation_in != 0) ? weights_q[r][c] : '0"
    assert text.count(a)==text.count(w)==1
    ungated=text.replace('module zero_aware_systolic_npu_param','module ungated_systolic_npu_param').replace(a,'activation_in').replace(w,'weights_q[r][c]')
    retained=ungated.replace('module ungated_systolic_npu_param','module retained_systolic_npu_param')
    marker="if (clear_i) begin a_pipe[r][c]<='0; partial_q[r][c]<='0; valid_q[r][c]<=0; end"
    assert marker in retained
    retained=retained.replace(marker,"if (clear_i) begin partial_q[r][c]<='0; valid_q[r][c]<=0; end")
    for name,data in [('legacy.sv',text),('plain.sv',ungated),('retained.sv',retained)]:
        (out/name).write_text(data)
    for name in ['zero_hold.sv','zero_dual_hold.sv','tb_isolation.sv']:
        shutil.copy2(board/'experiments'/name,out/name)
    size_test=(board.parent/'verification/tb_systolic.sv').read_text()
    for stem,target in [('hold','zero_hold'),('dual','zero_dual_hold')]:
        data=size_test.replace('module tb_systolic_param',f'module tb_{stem}_sizes')
        data=data.replace('zero_aware_systolic_npu_param',f'{target}_systolic_npu_param')
        (out/f'tb_{stem}_sizes.sv').write_text(data)
    monitors=[]
    for index,name in enumerate(['legacy','plain','retained','isolated','dual']):
        monitors.append(f'''for(genvar r=0;r<4;r++)begin: m{index}_r
  for(genvar c=0;c<4;c++)begin: m_c
    logic [15:0] previous_operands,previous_product;
    longint input_count[0:7],product_count[0:7];
    integer di,dp;
    initial for(int p=0;p<8;p++)begin input_count[p]=0;product_count[p]=0;end
    assign pe_operand_toggles[{index}][r][c]=input_count[case_id];
    assign pe_product_toggles[{index}][r][c]=product_count[case_id];
    always @(posedge clk)begin
      if(rst_n && measure)begin
        di=$countones({{{name}.row[r].pe[c].gated_activation,{name}.row[r].pe[c].gated_weight}}^previous_operands);
        dp=$countones({name}.row[r].pe[c].product^previous_product);
        input_count[case_id]=input_count[case_id]+di;
        product_count[case_id]=product_count[case_id]+dp;
      end
      previous_operands={{{name}.row[r].pe[c].gated_activation,{name}.row[r].pe[c].gated_weight}};
      previous_product={name}.row[r].pe[c].product;
    end
  end
end
''')
    (out/'isolation_monitors.svh').write_text(''.join(monitors))
    (out/'all.tcl').write_text('run all\nexit\n')
    for case in range(8):
        case_dir=out/f'case_{case}';case_dir.mkdir(exist_ok=True)
        (case_dir/'activity.tcl').write_text(f'open_saif {{{(case_dir/"activity.saif").as_posix()}}}\nlog_saif [get_objects -r /tb_isolation/*]\nrun all\nclose_saif\nexit\n')
    (out/'provenance.json').write_text(json.dumps(dict(source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),clock_mhz=25,seeds_per_case=4,jobs_per_seed=128,cases=[dict(id=p*4+s,profile='fixed_weights' if p==0 else 'changing_weights',target_zero_percent=z)for p in range(2)for s,z in enumerate([0,50,90,100])],variants=['legacy_force_zero','ungated','ungated_retained','nonzero_activation_hold','dual_operand_hold'],prototype_sha256={name:hashlib.sha256((out/name).read_bytes()).hexdigest()for name in ['zero_hold.sv','zero_dual_hold.sv']},scope='Experimental legacy MAC alternatives. Production source and deployed bitstream remain unchanged.'),indent=2)+'\n')
    print(out)

if __name__=='__main__':main()
