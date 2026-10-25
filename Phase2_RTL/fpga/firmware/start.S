.section .vectors,"ax"
.option norvc
.rept 32
  j trap_handler
.endr

.section .init,"ax"
.globl _start
_start:
  csrw mie, zero
  csrw mstatus, zero
  la sp, _stack_top
  .option push
  .option norelax
  la gp, __global_pointer$
  .option pop
  li t0, 1
  csrw mtvec, t0
  la t0, _data_load
  la t1, _data_start
  la t2, _data_end
1:
  bgeu t1, t2, 2f
  lw t3, 0(t0)
  sw t3, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  j 1b
2:
  la t1, _bss_start
  la t2, _bss_end
3:
  bgeu t1, t2, 4f
  sw zero, 0(t1)
  addi t1, t1, 4
  j 3b
4:
  call main
5:
  j 5b
