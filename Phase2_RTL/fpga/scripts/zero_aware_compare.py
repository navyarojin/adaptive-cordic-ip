"""Prepare a matched PE operand-isolation experiment without changing deployed RTL.

The ungated module is an explicitly recorded transformation of the maintained
source. Counts are clock-edge sampled multiplier operand/product toggles, not
transistor switching, watts or measured energy. SAIF records simulator activity.
"""
import argparse
import hashlib
import json
from pathlib import Path

TB=r'''
`timescale 1ns/1ps
module tb_zero_aware;
  logic clk=0, rst_n=0, clear_i=0, load_weights_i=0, in_valid_i=0;
  logic signed [127:0] weights_i;
  logic signed [31:0] activations_i;
  wire ready_g,ready_u,valid_g,valid_u;
  wire signed [95:0] result_g,result_u;
  integer phase=0;
  logic measure=0;
  logic [31:0] seed=32'd20261028;
  integer zeros,checks;
  integer sparsity;
  longint gated_inputs[0:2],ungated_inputs[0:2],gated_products[0:2],ungated_products[0:2];
  always #20 clk=~clk;
  zero_aware_systolic_npu_param gated(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,.ready_o(ready_g),.out_valid_o(valid_g),.accumulations_o(result_g));
  ungated_systolic_npu_param ungated(.clk,.rst_n,.clear_i,.load_weights_i,.weights_i,.in_valid_i,.activations_i,.ready_o(ready_u),.out_valid_o(valid_u),.accumulations_o(result_u));
  function automatic logic [31:0] next_random;
    seed=32'd1664525*seed+32'd1013904223;
    return seed;
  endfunction
  for(genvar r=0;r<4;r++) begin:monitor_row
    for(genvar c=0;c<4;c++) begin:monitor_pe
      logic [15:0] pg,pu,mg,mu;
      integer gi,ui,gp,up;
      always @(posedge clk) begin
        if(rst_n && measure) begin
          gi=$countones({gated.row[r].pe[c].gated_activation,gated.row[r].pe[c].gated_weight}^pg);
          ui=$countones({ungated.row[r].pe[c].gated_activation,ungated.row[r].pe[c].gated_weight}^pu);
          gp=$countones(gated.row[r].pe[c].product^mg);
          up=$countones(ungated.row[r].pe[c].product^mu);
          gated_inputs[phase]=gated_inputs[phase]+gi;
          ungated_inputs[phase]=ungated_inputs[phase]+ui;
          gated_products[phase]=gated_products[phase]+gp;
          ungated_products[phase]=ungated_products[phase]+up;
        end
        pg={gated.row[r].pe[c].gated_activation,gated.row[r].pe[c].gated_weight};
        pu={ungated.row[r].pe[c].gated_activation,ungated.row[r].pe[c].gated_weight};
        mg=gated.row[r].pe[c].product;mu=ungated.row[r].pe[c].product;
      end
    end
  end
  initial begin
    weights_i=0;activations_i=0;checks=0;
    for(integer p=0;p<3;p++) begin gated_inputs[p]=0;ungated_inputs[p]=0;gated_products[p]=0;ungated_products[p]=0;end
    repeat(4) @(negedge clk);rst_n=1;
    for(integer p=0;p<3;p++) begin
      phase=p;zeros=0;sparsity=p==0?0:(p==1?50:90);
      @(negedge clk);measure=0;clear_i=1;
      @(negedge clk);clear_i=0;load_weights_i=1;
      for(integer j=0;j<16;j++) weights_i[j*8+:8]=8'(next_random());
      @(negedge clk);load_weights_i=0;
      for(integer job=0;job<64;job++) begin
        @(negedge clk);clear_i=1;measure=1;
        @(negedge clk);clear_i=0;
        for(integer j=0;j<4;j++) begin
          if(next_random()%100<sparsity) begin activations_i[j*8+:8]=0;zeros++;end
          else begin activations_i[j*8+:8]=8'(next_random());if(activations_i[j*8+:8]==0) zeros++;end
        end
        if(!ready_g || !ready_u) $fatal(1,"Not ready");
        in_valid_i=1;
        @(negedge clk);in_valid_i=0;
        wait(valid_g);@(negedge clk);
        if(!valid_u || result_g!==result_u) $fatal(1,"Gated/ungated outputs differ");
        for(integer r=0;r<4;r++) begin
          automatic integer expected=0;
          for(integer c=0;c<4;c++) expected+=$signed(weights_i[(r*4+c)*8+:8])*$signed(activations_i[c*8+:8]);
          if($signed(result_g[r*24+:24])!=expected) $fatal(1,"Independent dot product differs");
          checks++;
        end
      end
      @(negedge clk);measure=0;
      $display("SWITCHING,%0d,%0d,%0d,%0d,%0d,%0d,%0d",sparsity,zeros,256,gated_inputs[p],ungated_inputs[p],gated_products[p],ungated_products[p]);
    end
    $display("PASS zero-aware baseline: %0d row outputs equal ungated and independent integer dot products; same clock, weights, inputs, schedule",checks);
    $finish;
  end
  initial begin repeat(20000) @(posedge clk);$fatal(1,"Timeout");end
endmodule
'''

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    root=Path(__file__).resolve().parents[2]
    source=root/'rtl/systolic_cfg.sv';text=source.read_text()
    old_a="(valid_in && activation_in != 0) ? activation_in : '0"
    old_w="(valid_in && activation_in != 0) ? weights_q[r][c] : '0"
    if text.count(old_a)!=1 or text.count(old_w)!=1:raise RuntimeError('Operand-isolation source changed; review transformation')
    ungated=text.replace('module zero_aware_systolic_npu_param','module ungated_systolic_npu_param').replace(old_a,'activation_in').replace(old_w,'weights_q[r][c]')
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    (out/'gated.sv').write_text(text);(out/'ungated.sv').write_text(ungated);(out/'tb_zero_aware.sv').write_text(TB)
    (out/'activity.tcl').write_text('open_saif activity.saif\nlog_saif [get_objects -r /tb_zero_aware/*]\nrun all\nclose_saif\nexit\n')
    (out/'provenance.json').write_text(json.dumps(dict(source=str(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),transformation='Remove both multiplier operand MUXes; retain valid/register/control/accumulation schedule',clock_mhz=25,jobs_per_sparsity=64,seed=20261028,scope='Clock-edge sampled multiplier input/product toggles; SAIF from RTL simulation; not measured power or full-system energy'),indent=2)+'\n')
    print(out)
if __name__=='__main__':main()
