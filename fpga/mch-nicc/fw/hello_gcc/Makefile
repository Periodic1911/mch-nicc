
RISCVGNU?=riscv64-elf

CFLAGS?=-Os -fno-strict-aliasing -ffreestanding -fno-pic -fomit-frame-pointer -march=rv32imc -mabi=ilp32 -fno-stack-protector -mno-relax -fdata-sections -ffunction-sections

all :
	rm -f *.o
	$(RISCVGNU)-gcc $(CFLAGS) -c start.S  -o start.o
	$(RISCVGNU)-gcc $(CFLAGS) -c hello_gcc.c -o hello_gcc.o
	$(RISCVGNU)-ld --gc-sections -o hello_gcc.elf -T memmap *.o -m elf32lriscv
	$(RISCVGNU)-objdump -Mnumeric -D hello_gcc.elf > hello_gcc.list
	$(RISCVGNU)-objcopy hello_gcc.elf hello_gcc.bin -O binary

clean:
	rm -f *.o
	rm -f *.elf
	rm -f *.list
	rm -f *.dis

