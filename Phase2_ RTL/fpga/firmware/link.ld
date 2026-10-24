OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
  ROM (rx) : ORIGIN = 0x00000000, LENGTH = 48K
  RAM (rw) : ORIGIN = 0x0000c000, LENGTH = 16K
}
SECTIONS {
  .vectors 0 : { KEEP(*(.vectors)) } > ROM
  .text 0x1000 : { KEEP(*(.init)) *(.text*) *(.rodata*) . = ALIGN(4); } > ROM
  .data : {
    _data_start = .; __global_pointer$ = . + 0x800;
    *(.sdata*) *(.data*) . = ALIGN(4); _data_end = .;
  } > RAM AT> ROM
  _data_load = LOADADDR(.data);
  .bss (NOLOAD) : {
    _bss_start = .; *(.sbss*) *(.bss*) *(COMMON) . = ALIGN(4); _bss_end = .;
  } > RAM
  _stack_top = ORIGIN(RAM) + LENGTH(RAM);
  ASSERT(_bss_end < _stack_top - 4096, "Firmware needs at least 4 KiB stack")
}
