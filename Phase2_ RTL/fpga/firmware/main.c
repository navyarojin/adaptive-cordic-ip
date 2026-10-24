#include <stdint.h>
#include "golden.h"
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define SPI(a) REG(0x10000000u+(a))
#define SYS(a) REG(0x10001000u+(a))
#define MB(a) REG(0x10002000u+(a))
#define STREAM(a) REG(0x10003000u+(a))
#define TIMEOUT 2500000u
static volatile uint32_t irq_seen;
static uint32_t checks;
static volatile uint32_t initialized_data = 0x12345678;

static void putc_uart(char c) {
  uint32_t begin=SYS(8);
  while (SYS(0x14)&1) if ((uint32_t)(SYS(8)-begin)>TIMEOUT) return;
  SYS(0x10)=(uint32_t)c;
}
static void puts_uart(const char *s) { while (*s) putc_uart(*s++); }
static void hex_uart(uint32_t v) {
  for (int i=7;i>=0;i--) putc_uart("0123456789ABCDEF"[(v>>(i*4))&15]);
}
__attribute__((noreturn)) static void fail(uint32_t code) {
  __asm__ volatile("csrw mie, zero");
  SYS(4)=code; SYS(0)=0xdead0001;
  puts_uart("FAIL "); hex_uart(code); puts_uart("\r\n");
  for (;;) __asm__ volatile("nop");
}
__attribute__((interrupt("machine"))) void trap_handler(void) {
  uint32_t cause;
  __asm__ volatile("csrr %0, mcause":"=r"(cause));
  if (cause==0x8000000bu) {

    __asm__ volatile("csrc mie, %0"::"r"(1u<<11));
    irq_seen++;
  } else fail(0xe0000000u | cause);
}
static void check(int ok,uint32_t code) { if (!ok) fail(code); checks++; }
static uint32_t rx0,rx1,rx2;
static void frame(uint32_t hi,uint32_t mid,uint32_t lo) {
  uint32_t begin=SYS(8);
  while (SPI(0x10)&1) if ((uint32_t)(SYS(8)-begin)>TIMEOUT) fail(0x100);
  SPI(0)=lo; SPI(4)=mid; SPI(8)=hi; SPI(0x0c)=1;
  do {
    uint32_t s=SPI(0x10);
    if (s&4) fail(0x101);
    if (!(s&1) && (s&2)) break;
    if ((uint32_t)(SYS(8)-begin)>TIMEOUT) fail(0x102);
  } while (1);
  rx0=SPI(0x14); rx1=SPI(0x18); rx2=SPI(0x1c);
}
static uint32_t access_npu(unsigned op,uint32_t addr,uint32_t data,unsigned be,unsigned error) {
  frame((op<<8)|be,addr,data);
  uint32_t begin=SYS(8);
  for (;;) {
    frame(0,0,0);
    unsigned status=rx2>>8;
    if (status==2 || status==0x82) {
      if ((status==0x82)!=error) fail(0x200|op);
      return ((rx2&255)<<24)|(rx1>>8);
    }
    if ((uint32_t)(SYS(8)-begin)>TIMEOUT) fail(0x210|op);
  }
}
static void apb(unsigned a,uint32_t v) { (void)access_npu(2,a,v,15,0); }
static void data_write(unsigned a,uint32_t v) { (void)access_npu(4,a,v,15,0); }
static uint32_t data_read(unsigned a) { return access_npu(3,a,0,15,0); }
static void configure(unsigned mode,unsigned min,unsigned max,unsigned threshold) {
  apb(0,0); apb(0x14,threshold); apb(0x18,1); apb(0x1c,0);
  apb(0x20,min); apb(0x24,max); apb(0x28,14); apb(0x2c,1);
  apb(0x30,1); apb(0x34,0); apb(0x38,1); apb(0,(mode<<1)|1);
  check(access_npu(1,0,0,15,0)==((mode<<1)|1),0x300|mode);
}
#ifdef JUPYTER
static void serve(void) {
  uint32_t completed=MB(0);
  MB(0x100)=completed;
  MB(0x104)=1;
  for (;;) {
    uint32_t sequence=MB(0);
    if (sequence==completed) continue;
    MB(0x104)=2;
    uint32_t command=MB(4),mode=MB(8),shift=MB(12);
    uint32_t minimum=MB(16),maximum=MB(20),threshold=MB(24),sample=MB(28),full=MB(0x70);
#ifdef STREAMING
    if (command>=2 && command<=7) {
      uint32_t begin=SYS(8),error=0,bank=MB(0x74),count=MB(0x78),tag=MB(0x7c);
      if (STREAM(0)!=0x53545231u) error=6;
      else if (command==6) {
        if ((STREAM(0x34)&0xffff0004u)!=0x00010004u) error=6;
        else if (STREAM(8)&0x300u) error=7;
        else {
          STREAM(0x3c)=0;
          for(uint32_t r=0;r<16;r++) STREAM(0x400+4*r)=MB(0x90+4*r);
          STREAM(0x3c)=1;
        }
      } else if(command==7) {
        if ((STREAM(0x34)&0xffff0004u)!=0x00010004u || !STREAM(0x3c)) error=6;
        else if(bank>1 || count==0 || count>64 || tag>65535) error=1;
        else {
          STREAM(0x0c)=0xffffffffu;
          STREAM(0x20)=1;
          STREAM(0x38)=3;
          STREAM(0x10)=(tag<<16)|(count<<8)|bank;
          __asm__ volatile("fence rw,rw":::"memory");
          STREAM(0x14)=1;
          __asm__ volatile("fence rw,rw":::"memory");
          if(STREAM(0x0c)) error=7;
        }
      } else if (command==2 || command==5) {
        if (bank>1 || count==0 || count>64 || tag>65535 || mode>3 ||
            minimum<6 || maximum<minimum || full<maximum || full>16 ||
            sample>255 || threshold>65535 || MB(0x80)>65535 || MB(0x84)>65535 ||
            MB(0x88)>65535 || MB(0x8c)>1 || (command==5 && shift>31)) error=1;
        else if (command==5 && (STREAM(0x34)&0xffff0002u)!=0x00010002u) error=6;
        else {
          STREAM(0x0c)=0xffffffffu;
          STREAM(0x20)=(mode<<1)|1;
          STREAM(0x24)=(full<<16)|(maximum<<8)|minimum;
          STREAM(0x28)=(sample<<16)|threshold;
          STREAM(0x2c)=(MB(0x84)<<16)|MB(0x80);
          STREAM(0x30)=(MB(0x8c)<<16)|MB(0x88);

          if ((STREAM(0x34)>>16)==1) STREAM(0x38)=command==5 ? (shift<<8)|1u : 0;
          if (command==5) {
            for (uint32_t r=0;r<4;r++) {
              STREAM(0x40+4*r)=MB(0x90+4*r);
              STREAM(0x50+4*r)=MB(0xa0+4*r);
            }
          }
          STREAM(0x10)=(tag<<16)|(count<<8)|bank;
          __asm__ volatile("fence rw,rw":::"memory");
          STREAM(0x14)=1;
          __asm__ volatile("fence rw,rw":::"memory");
          if (STREAM(0x0c)) error=7;
        }
      } else if (command==3) {
        if (bank>1) error=1;
        else STREAM(0x18)=0x100u|bank;
      }
      MB(0x108)=error;
      MB(0x140)=error ? 0:1;
      MB(0x144)=SYS(8)-begin;
      MB(0x154)=STREAM(8);
      MB(0x158)=STREAM(0x1c);
      MB(0x104)=error ? 4:3;
      __asm__ volatile("fence rw,rw":::"memory");
      MB(0x100)=sequence;
      completed=sequence;
      continue;
    }
#endif
    int w[16],a[4];
    uint32_t error=0,checked=0;
    for (int i=0;i<16;i++) { w[i]=(int32_t)MB(0x20+4*i); if (w[i]<-128 || w[i]>127) error=2; }
    for (int i=0;i<4;i++) { a[i]=(int32_t)MB(0x60+4*i); if (a[i]<-128 || a[i]>127) error=2; }
    if (command!=1 || mode>3 || shift>31 || minimum<6 || maximum<minimum ||
        full<maximum || full>16 || sample>255 || threshold>65535) error=1;
    uint32_t begin=SYS(8);
    if (!error) {
      configure(mode,minimum,maximum,threshold);
      apb(0x28,full); apb(0x18,sample);
      for (int i=0;i<16;i++) data_write(4*i,(uint32_t)w[i]);
      for (int i=0;i<4;i++) data_write(0x40+4*i,(uint32_t)a[i]);
      data_write(0x104,shift); data_write(0x108,1);
      irq_seen=0;
      __asm__ volatile("csrs mie, %0"::"r"(1u<<11));
      data_write(0x100,1);
      uint32_t wait_begin=SYS(8);
      while (!irq_seen) if ((uint32_t)(SYS(8)-wait_begin)>TIMEOUT) fail(0x800);
      for (int r=0;r<4;r++) {
        int sum=0;
        for (int c=0;c<4;c++) sum+=w[r*4+c]*a[c];
        int raw=(int32_t)data_read(0x90+4*r);
        MB(0x120+4*r)=(uint32_t)raw;
        MB(0x130+4*r)=data_read(0x80+4*r);
        if (raw==sum) checked++; else error=3;
      }
      MB(0x148)=access_npu(1,8,0,15,0);
      MB(0x14c)=access_npu(1,12,0,15,0);
      MB(0x150)=access_npu(1,16,0,15,0);
      data_write(0x100,2);
      if (irq_seen==1 && SYS(12)==0) checked++; else error=4;
    }
    MB(0x108)=error;
    MB(0x140)=checked;
    MB(0x144)=SYS(8)-begin;
    MB(0x104)=error ? 4:3;
    __asm__ volatile("fence rw,rw":::"memory");
    MB(0x100)=sequence;
    completed=sequence;
  }
}
#endif
int main(void) {
#ifdef JUPYTER
  MB(0x104)=0;
#endif
  SYS(0)=1; puts_uart("CV32E40P / PYNQ-Z2 NPU self-test\r\n");
  check(initialized_data==0x12345678,0x400);
  initialized_data=0;
  volatile union { uint32_t word; uint16_t halves[2]; uint8_t bytes[4]; } memory;
  memory.word=0;
  for (unsigned i=0;i<4;i++) memory.bytes[i]=(uint8_t)(0x11*(i+1));
  check(memory.word==0x44332211,0x401);
  memory.halves[0]=0xabcd;
  check(memory.word==0x4433abcd,0x402);
  SPI(0x20)=8;
  __asm__ volatile("csrs mstatus, %0"::"r"(8u));
  for (unsigned mode=0;mode<4;mode++) for (unsigned pattern=0;pattern<4;pattern++) {
    SYS(4)=(mode<<8)|pattern;
    configure(mode,14,14,512);
    int w[16],a[4];
    for (int i=0;i<16;i++) {
      w[i]=pattern==3 ? (i%2 ? -128:127) : i%7-3;
      data_write(i*4,(uint32_t)w[i]);
    }
    for (int i=0;i<4;i++) {
      a[i]=pattern==0 ? 0 : pattern==1 ? i+1 : pattern==2 ? (i%2 ? -(i+1):0) : (i%2 ? -128:127);
      data_write(0x40+i*4,(uint32_t)a[i]);
    }
    data_write(0x104,pattern==3 ? 4:0);
    data_write(0x108,1);
    irq_seen=0;
    __asm__ volatile("csrs mie, %0"::"r"(1u<<11));
    data_write(0x100,1);
    uint32_t begin=SYS(8);
    while (!irq_seen) if ((uint32_t)(SYS(8)-begin)>TIMEOUT) fail(0x500|(mode<<4)|pattern);
    check((data_read(0x100)&3)==2,0x510);
    check(irq_seen==1,0x511);
    for (int r=0;r<4;r++) {
      int sum=0;
      for (int c=0;c<4;c++) sum+=w[r*4+c]*a[c];
      check((int32_t)data_read(0x90+r*4)==sum,0x600|(mode<<8)|(pattern<<4)|r);
      check((int32_t)data_read(0x80+r*4)==golden[mode][pattern][r],0x1000|(mode<<8)|(pattern<<4)|r);
    }
    data_write(0x100,2);
    check(SYS(0x0c)==0,0x512);
  }
  configure(0,6,10,0);
  data_write(0x200,FALLBACK_X);
  uint32_t begin=SYS(8);
  while (data_read(0x100)&1)
    if ((uint32_t)(SYS(8)-begin)>TIMEOUT) fail(0x708);
  check((int32_t)data_read(0x204)==FALLBACK_Y,0x700);
  check(access_npu(1,0x10,0,15,0)>0,0x701);
  check(access_npu(0xff,0,0,15,1)==1,0x702);
  check(access_npu(3,1,0,15,1)==2,0x703);
  check(access_npu(2,0,0,1,1)==3,0x704);
  check(access_npu(1,0xfc,0,15,1)==4,0x705);
  data_write(0,0x55);
  (void)access_npu(4,0,0xaa,14,0);
  check(data_read(0)==0x55,0x706);
  check(SYS(0x18)==0,0x707);
  __asm__ volatile("csrw mie, zero");
  puts_uart("PASS checks=0x"); hex_uart(checks); puts_uart("\r\n");
  SYS(4)=checks; SYS(0)=0x600d600d;
#ifdef JUPYTER
  serve();
#endif
  for (;;) __asm__ volatile("nop");
}
