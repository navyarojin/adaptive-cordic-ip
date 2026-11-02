import hashlib
import json
import re
from pathlib import Path


board = Path(__file__).resolve().parents[1]
folder = board / 'reports/row_gating_20261029/compare/mac/transition_diagnostic'
sdf = (folder / 'timing.sdf').read_text()
instance = next(match for match in re.finditer(r'\(INSTANCE ([^)]+)\)', sdf)
                if match[1].replace('\\', '') == 'gated/values_o_reg[75]_i_51')
start = sdf.rfind('(CELL ', 0, instance.start())
depth = 0
for position in range(start, len(sdf)):
    if sdf[position] == '(':
        depth += 1
    elif sdf[position] == ')':
        depth -= 1
        if depth == 0:
            cell = sdf[start:position + 1].replace(instance[0], '(INSTANCE)')
            break
(folder / 'carry_reproducer.sdf').write_text(
    '(DELAYFILE (SDFVERSION "3.0") (DESIGN "CARRY4") (TIMESCALE 1ps)\n' + cell + '\n)\n')
ids = {}
values = {}
records = []
time = previous = None
for line in (folder / 'cell.vcd').open():
    fields = line.strip().split()
    if not fields:
        continue
    if fields[0] == '$var' and fields[4] in ['CI', 'CYINIT', 'DI', 'S']:
        ids[fields[3]] = fields[4]
    elif fields[0].startswith('#'):
        if time is not None and len(values) == 4 and values != previous:
            records.append((time, dict(values)))
            previous = dict(values)
        time = int(fields[0][1:])
    elif fields[0].startswith('b') and len(fields) > 1 and fields[1] in ids:
        values[ids[fields[1]]] = fields[0][1:]
    elif fields[0][0] in '01xz' and fields[0][1:] in ids:
        values[ids[fields[0][1:]]] = fields[0][0]
if len(values) == 4 and values != previous:
    records.append((time, dict(values)))
assert records and not any(set(value) - set('01') for _, row in records for value in row.values())
wave = []
previous = records[0][0]
for time, row in records:
    wave.append(f"    #{time - previous}; CI=1'b{row['CI']}; CYINIT=1'b{row['CYINIT']}; DI=4'b{row['DI'].zfill(4)}; S=4'b{row['S'].zfill(4)};")
    previous = time
source = '''`timescale 1ps/1ps
module tb_carry_reproducer;
  logic CI=0,CYINIT=0;
  logic [3:0] DI=0,S=0;
  wire [3:0] plain_co,plain_o,delay_co,delay_o;
  integer mismatches=0;
  CARRY4 plain(.CI,.CYINIT,.DI,.S,.CO(plain_co),.O(plain_o));
  CARRY4 delayed(.CI,.CYINIT,.DI,.S,.CO(delay_co),.O(delay_o));
  initial $sdf_annotate("SDFPATH",delayed);
  function automatic logic [7:0] truth(input logic ci,cy,input logic [3:0] di,s);
    logic c;logic [3:0] co,o;
    c=ci|cy;
    for(int bitnum=0;bitnum<4;bitnum++)begin
      o[bitnum]=s[bitnum]^c;c=s[bitnum] ? c : di[bitnum];co[bitnum]=c;
    end
    return {co,o};
  endfunction
  initial begin
    #200000;
    for(int vector=0;vector<1024;vector++)begin
      {CI,CYINIT,DI,S}=10'(vector);#5000;
      if({plain_co,plain_o}!==truth(CI,CYINIT,DI,S))$fatal(1,"Unannotated truth-table mismatch");
      if({delay_co,delay_o}!==truth(CI,CYINIT,DI,S))mismatches++;
    end
    $display("DIAGNOSTIC truth_vectors=1024 unannotated_mismatches=0 annotated_mismatches=%0d",mismatches);
    #10000;
WAVE
    #10000;
    if({plain_co,plain_o}!==truth(CI,CYINIT,DI,S))$fatal(1,"Unannotated waveform replay mismatch");
    $display("DIAGNOSTIC observed_waveform CI=%b CYINIT=%b DI=%b S=%b expected=%b annotated=%b",CI,CYINIT,DI,S,truth(CI,CYINIT,DI,S),{delay_co,delay_o});
    $finish;
  end
endmodule
'''.replace('SDFPATH', (folder / 'carry_reproducer.sdf').resolve().as_posix()).replace('WAVE', '\n'.join(wave))
(folder / 'tb_carry_reproducer.sv').write_text(source)
(folder / 'reproducer.json').write_text(json.dumps(dict(records=len(records),
    source_sdf_sha256=hashlib.sha256(sdf.encode()).hexdigest(),
    scope='Unmodified single-cell delays, independent truth table and recorded pin transitions. Diagnostic only; not passed SDF signoff.'), indent=2) + '\n')
print('Prepared single-cell reproducer:', len(records), 'pin updates')
