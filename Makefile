DEFINES	:=	

ifneq ($(strip $(DISABLE_EXITLAUNCHTITLE_TYPE1)),)
	DEFINES	:=	$(DEFINES) -DDISABLE_EXITLAUNCHTITLE_TYPE1
endif

ifneq ($(strip $(DUMPMEMGPU)),)
	DEFINES	:=	$(DEFINES) -DDUMPMEMGPU
endif

ifneq ($(strip $(DUMPMEMGPU_AFTERPATCHES)),)
	DEFINES	:=	$(DEFINES) -DDUMPMEMGPU_AFTERPATCHES
endif

ifneq ($(strip $(DUMPMEMGPU_ADR)),)
	DEFINES	:=	$(DEFINES) -DDUMPMEMGPU_ADR=$(DUMPMEMGPU_ADR)
endif

ifneq ($(strip $(DUMPMEMGPU_SIZE)),)
	DEFINES	:=	$(DEFINES) -DDUMPMEMGPU_SIZE=$(DUMPMEMGPU_SIZE)
endif

ifneq ($(strip $(DUMP_AXIWRAM)),)
	DEFINES	:=	$(DEFINES) -DDUMP_AXIWRAM
endif

ifneq ($(strip $(DUMP_AXIWRAM_AFTERPATCHES)),)
	DEFINES	:=	$(DEFINES) -DDUMP_AXIWRAM_AFTERPATCHES
endif

ifneq ($(strip $(DUMP_ARM11BOOTROM)),)
	DEFINES	:=	$(DEFINES) -DDUMP_ARM11BOOTROM
endif

ifneq ($(strip $(NEW3DSTEST)),)
	DEFINES	:=	$(DEFINES) -DNEW3DSTEST
endif

CPCMD	:=	

ifneq ($(strip $(OUTPATH)),)
	CPCMD	:=	cp 3ds_arm11code.bin $(OUTPATH)
endif

all:
	arm-none-eabi-gcc -x assembler-with-cpp -nostartfiles -nostdlib $(DEFINES) -o 3ds_arm11code.elf 3ds_arm11code.s
	arm-none-eabi-objcopy -O binary 3ds_arm11code.elf 3ds_arm11code.bin
	$(CPCMD)

clean:
	rm -f 3ds_arm11code.elf 3ds_arm11code.bin

