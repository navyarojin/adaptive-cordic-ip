"""Extract per-RTL-file scores, including provisional XCRG crash output.

No exclusions or coverage-closure claims are inferred from percentages.
"""
import argparse
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path

class Tables(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows, self.row, self.cell = [], [], None

    def handle_starttag(self, tag, attrs):
        if tag == 'tr':
            self.row = []
        elif tag == 'td':
            self.cell = ''

    def handle_data(self, value):
        if self.cell is not None:
            self.cell += value

    def handle_endtag(self, tag):
        if tag == 'td' and self.cell is not None:
            self.row.append(self.cell.strip())
            self.cell = None
        elif tag == 'tr':
            self.rows.append(self.row)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('html', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--reporter-complete', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    sources = (root/'asic/verification.f').read_text().splitlines()
    tables = Tables()
    tables.feed(args.html.read_text())
    rows = []
    for cells in tables.rows:
        if len(cells) not in (9, 10) or not cells[0].isdigit():
            continue
        name = next((s for s in sources if s and cells[1].replace('\\', '/').endswith('/'+s)), None)
        if name:
            missed = []
            detail = args.html.parent/f'file{cells[0]}.html'
            if detail.exists() and args.reporter_complete:
                for fragment in re.findall(r"<tr class='lineTableHoverRed'>(.*?)</tr>", detail.read_text(), re.S):
                    entry = Tables()
                    entry.feed('<tr>'+fragment+'</tr>')
                    if entry.rows and entry.rows[0] and entry.rows[0][0].isdigit():
                        missed.append(dict(line=int(entry.rows[0][0]), detail=entry.rows[0][1:]))
            rows.append(dict(file=name, statements=int(cells[6]), statement_percent=float(cells[4]),
                             branch_percent=float(cells[7]), condition_percent=float(cells[8]),
                             toggle_percent=float(cells[9]) if len(cells)==10 else None,
                             uncovered_entries=missed,
                             source_sha256=hashlib.sha256((root/name).read_bytes()).hexdigest()))
    if not rows:
        raise SystemExit('No RTL rows found: refusing an empty coverage result')
    statements = sum(row['statements'] for row in rows)
    covered = sum(round(row['statements']*row['statement_percent']/100) for row in rows)
    result = dict(tool='Vivado Simulator/XCRG 2023.2', reporter_completed=args.reporter_complete,
                  status='Measured; closure NOT established', exclusions_applied=[],
                  statement_total=statements, statement_covered=covered,
                  statement_percent=100*covered/statements if statements else None,
                  note='Per-file scores only. Testbench/UVM files excluded from this summary. '
                       'A missing detailed report means these scores are provisional; no waivers applied.',
                  rtl=rows)

    result['closure_review'] = {
        'scope': 'stream_mmio LANES=4; accelerator only, not CV32/full chip',
        'statement_candidates': [
            {'file': 'rtl/qual_stream.sv', 'lines': [124, 133],
             'reason': 'cfg.lut_reset is reset to zero in stream_mmio and has no MMIO write assignment; reset arm is unreachable through this top.'},
            {'file': 'rtl/act_array.sv', 'lines': [36, 37],
             'reason': 'Invalid-parameter fatal guard is false for the elaborated LANES=4.'},
            {'file': 'rtl/div_stream.sv', 'lines': [35, 36],
             'reason': 'Invalid-width fatal guard is false for the elaborated divider parameters.'}],
        'remaining_requirements': [
            'Review each uncovered branch/condition in the archived detailed HTML; statement candidates do not waive these metrics.',
            'Prove arithmetic saturation and zero-denominator reachability before any exclusion.',
            'Measure toggle coverage with a working reporter; missing toggle data is not a pass.',
            'Run Xcelium/IMC in the lab and review tool-specific exclusions before Cadence sign-off.'],
        'closure_complete': False}
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    for row in rows:
        print(row['file'], 'statement', row['statement_percent'], 'branch', row['branch_percent'])

if __name__ == '__main__':
    main()
