import csv
import hashlib
import json
import re
import shutil
from pathlib import Path


board = Path(__file__).resolve().parents[1]
report = board / 'reports/row_gating_20261029/compare'
mapping = list(csv.DictReader((report / 'register_activity_map.csv').open()))
statistics = {}
for profile in ['actual', 'dense', 'masks', 'idle']:
    folder = report / 'mac' / f'rtl_{profile}'
    original = (folder / 'activity.saif').read_text()
    lines = original.splitlines(keepends=True)
    scopes = []
    blocks = {}
    for index, line in enumerate(lines):
        instance = re.match(r'^(\s*)\(INSTANCE\s+(\S+)\s*$', line)
        if instance:
            indent, name = len(instance[1]), instance[2]
            scopes = [(depth, label) for depth, label in scopes if depth < indent]
            scopes.append((indent, name))
        if line.strip() == '(NET' and scopes[-1][1] in ['gated', 'ungated']:
            stop = index + 1
            while lines[stop].strip() != ')':
                stop += 1
            nets = {}
            for entry in lines[index + 1:stop]:
                match = re.match(r'\s*\((\S+) (\(T0 .*\))\s*$', entry)
                if match:
                    nets[re.sub(r'\\(.)', r'\1', match[1])] = match[2]
            blocks[scopes[-1][1]] = dict(stop=stop, nets=nets, extra={})
    assert set(blocks) == {'gated', 'ungated'}
    matched = conflicts = 0
    rejected = set()
    for row in mapping:
        scope, source = row['rtl_signal'].split('/', 1)
        target_scope, target = row['routed_signal'].split('/', 1)
        assert scope == target_scope
        block = blocks[scope]
        value = block['nets'].get(source)
        if value is None or target in rejected:
            continue
        existing = block['nets'].get(target, block['extra'].get(target))
        if existing is not None and existing != value:
            block['extra'].pop(target, None)
            rejected.add(target)
            conflicts += 1
            continue
        if target not in block['nets']:
            block['extra'][target] = value
            matched += 1
    assert matched > 500, (profile, matched)
    for block in sorted(blocks.values(), key=lambda block: block['stop'], reverse=True):
        entries = []
        for name, value in sorted(block['extra'].items()):
            escaped = re.sub(r'([\[\]()\\])', r'\\\1', name)
            entries.append(f'               ({escaped} {value}\n')
        lines[block['stop']:block['stop']] = entries
    mapped = folder / 'activity_mapped.saif'
    mapped.write_text(''.join(lines))
    old = folder / 'ports_only_estimate'
    old.mkdir(exist_ok=True)
    for name in ['power.rpt', 'power.xml', 'advisory.rpt', 'annotation.txt']:
        if (folder / name).exists() and not (old / name).exists():
            shutil.copy2(folder / name, old / name)
    statistics[profile] = dict(added_register_nets=matched, conflicting_aliases_skipped=conflicts,
                               source_sha256=hashlib.sha256((folder / 'activity.saif').read_bytes()).hexdigest(),
                               mapped_sha256=hashlib.sha256(mapped.read_bytes()).hexdigest())
(report / 'register_activity_mapping.json').write_text(json.dumps(dict(
    method='Exact original register-bit cell names mapped to their routed Q nets. Activity values copied without alteration; conflicting aliases omitted.',
    profiles=statistics), indent=2) + '\n')
print('PASS mapped checked register activity:', statistics)
