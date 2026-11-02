from pathlib import Path
import sys
data=Path(sys.argv[1]).read_bytes()
if len(data)>65536:
    raise SystemExit('Firmware image exceeds 64 KiB')
data=data.ljust(65536,b'\0')
Path(sys.argv[2]).write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n'
                                  for i in range(0,len(data),4)))
