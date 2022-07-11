
RISCVGNU?=riscv64-elf

CFLAGS?=-Os -fno-strict-aliasing -ffreestanding -fno-pic -fomit-frame-pointer -march=rv32imc -mabi=ilp32 -fno-stack-protector -mno-relax -fdata-sections -ffunction-sections

all :
	rm -f *.o
	$(RISCVGNU)-gcc $(CFLAGS) -c start.S  -o start.o
	$(RISCVGNU)-gcc $(CFLAGS) -c mch_nicc.c -o mch_nicc.o
	$(RISCVGNU)-ld --gc-sections -o mch_nicc.elf -T memmap *.o -m elf32lriscv
	$(RISCVGNU)-objdump -Mnumeric -D mch_nicc.elf > mch_nicc.list
	$(RISCVGNU)-objcopy mch_nicc.elf mch_nicc.bin -O binary

clean:
	rm -f *.o
	rm -f *.elf
	rm -f *.list
	rm -f *.dis

