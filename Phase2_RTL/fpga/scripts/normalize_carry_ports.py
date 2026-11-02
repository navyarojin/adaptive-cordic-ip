import argparse
import hashlib
import json
import re
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument('--kind', choices=['mac', 'legacy'], default='legacy')
args = parser.parse_args()
board = Path(__file__).resolve().parents[1]
folder = board / 'reports/row_gating_20261029/flat_compare' / args.kind
original = (folder / 'timing.v').read_text()
assert '__sim_carry_port_' not in original
replacements = []
insertions = []
connections = []
counter = 0


def module_body(match):
    global counter
    header, body, ending = match.groups()
    declarations = []
    assignments = []

    def carry_instance(cell):
        global counter
        instance, ports = cell.groups()
        index = counter
        counter += 1

        def port(connection):
            name, expression = connection.groups()
            if not expression.strip():
                return connection[0]
            alias = f'__sim_carry_port_{index}_{name}'
            declarations.append(f'  wire [3:0] {alias};\n')
            assignments.append(f'  assign {expression.strip()} = {alias};\n')
            connections.append(dict(instance=instance.strip(), port=name,
                                    original_expression=expression, alias=alias))
            return f'.{name}({alias})'

        rewritten = re.sub(r'\.(CO|O)\((.*?)\)(?=,|\s*$)', port, ports, flags=re.S)
        result = f'CARRY4 {instance}({rewritten});'
        replacements.append((result, cell[0]))
        return result

    body = re.sub(r'\bCARRY4\s+(.*?)\((.*?)\);', carry_instance, body, flags=re.S)
    declared = ''.join(declarations)
    assigned = ''.join(assignments)
    if declared:
        insertions.extend([declared, assigned])
    return header + declared + body + assigned + ending


normalized = re.sub(r'(module\s+\S+\s*.*?;\n)(.*?)(endmodule)', module_body, original, flags=re.S)
assert counter > 100
restored = normalized
for inserted in insertions:
    assert restored.count(inserted) == 1
    restored = restored.replace(inserted, '', 1)
for after, before in replacements:
    assert restored.count(after) == 1
    restored = restored.replace(after, before, 1)
assert restored == original
assert original.count('$sdf_annotate(') == normalized.count('$sdf_annotate(') == 1
target = folder / 'bus_ports'
target.mkdir(exist_ok=True)
(target / 'timing.v').write_text(normalized)
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
record = dict(scope='Simulation-only identity wire aliases at CARRY4 output ports. No added primitive, register, clock, timing-check waiver, or SDF change.',
              carry_instances=counter, aliases=len(connections), inverse_transform_recovers_original=True,
              original_netlist_sha256=digest(folder / 'timing.v'),
              normalized_netlist_sha256=digest(target / 'timing.v'),
              unchanged_native_sdf_sha256=digest(folder / 'timing.sdf'), connections=connections)
(target / 'connection_audit.json').write_text(json.dumps(record, indent=2) + '\n')
print('PASS reversible identity-connection audit:', counter, 'CARRY4 instances;', len(connections), 'output buses')
