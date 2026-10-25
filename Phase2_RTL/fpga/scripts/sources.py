"""One explicit synthesis/simulation source inventory, excluding upstream BHV."""
from pathlib import Path
import sys

board=Path(__file__).resolve().parents[1]
root=board.parent
cpu=board/'rtl'
sources=[]
for line in (board/'scripts/cpu.flist').read_text().splitlines():
    if line.startswith('${DESIGN_RTL_DIR}/') and '/../' not in line:
        sources.append((cpu/line.split('${DESIGN_RTL_DIR}/')[1]).relative_to(root))
sources += [Path(s) for s in (root/'rtl/sources.f').read_text().splitlines() if s.strip()]
sources += [Path('fpga/rtl')/s for s in
            ['cv32e40p_clock_gate.sv','host_ram.sv','spi_master80.sv','uart_tx.sv',
             'soc.sv','host.sv']]
if __name__=='__main__':
    if len(sys.argv)>1:
        import shutil
        dest=Path(sys.argv[1]); dest.mkdir(parents=True,exist_ok=True)
        for source in sources:
            target=dest/source
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(root/source,target)
        (dest/'sources.f').write_text('\n'.join(str(s).replace('\\','/') for s in sources)+'\n')
    else:
        print('\n'.join(str(s).replace('\\','/') for s in sources))
