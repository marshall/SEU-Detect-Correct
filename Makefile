TARGET:=FreeRTOS
TOOLCHAIN_ROOT = ~/stm/gcc-arm-none-eabi-4_9-2015q3
TOOLCHAIN_PATH:=$(TOOLCHAIN_ROOT)/bin
TOOLCHAIN_PREFIX:=arm-none-eabi

OPTLVL:=0
DBG:=-g

FREERTOS:=$(CURDIR)/FreeRTOS
STARTUP:=$(CURDIR)/hardware

INCLUDE=-I$(CURDIR)/hardware
INCLUDE+=-I$(FREERTOS)/include
INCLUDE+=-I$(FREERTOS)/portable/GCC/ARM_CM4F
INCLUDE+=-I$(CURDIR)/Libraries/CMSIS/Device/ST/STM32F4xx/Include
INCLUDE+=-I$(CURDIR)/Libraries/CMSIS/Include
INCLUDE+=-I$(CURDIR)/Libraries/STM32F4xx_StdPeriph_Driver/inc
INCLUDE+=-I$(CURDIR)/config
INCLUDE+=-Iseu/src

BUILD_DIR = $(CURDIR)/build
BIN_DIR = $(CURDIR)/binary
SEU_DIR = seu/
SEU_SRC_DIR = seu/src

ASRC=startup_stm32f4xx.s

vpath %.c $(CURDIR)/Libraries/STM32F4xx_StdPeriph_Driver/src \
	  $(CURDIR)/Libraries/syscall $(CURDIR)/hardware $(FREERTOS) \
	  $(FREERTOS)/portable/MemMang $(FREERTOS)/portable/GCC/ARM_CM4F

UNCHECKED_SRC =stm32f4xx_it.c #compiled without finstrument-function
SRC+=system_stm32f4xx.c
SRC+=main.c
SRC+=syscalls.c

SRC+=port.c
SRC+=list.c
SRC+=queue.c
SRC+=tasks.c
SRC+=event_groups.c
SRC+=timers.c
SRC+=heap_4.c

SRC+=stm32f4xx_syscfg.c
SRC+=misc.c
SRC+=stm32f4xx_adc.c
SRC+=stm32f4xx_dac.c
SRC+=stm32f4xx_dma.c
SRC+=stm32f4xx_exti.c
SRC+=stm32f4xx_flash.c
SRC+=stm32f4xx_gpio.c
SRC+=stm32f4xx_i2c.c
SRC+=stm32f4xx_rcc.c
SRC+=stm32f4xx_spi.c
SRC+=stm32f4xx_tim.c
SRC+=stm32f4xx_usart.c
SRC+=stm32f4xx_rng.c

CRC_SRCS = CRC_SRCS = util/CRC_Generator/crcmodel.c util/CRC_Generator/main.c

CDEFS=-DUSE_STDPERIPH_DRIVER
CDEFS+=-DSTM32F4XX
CDEFS+=-DHSE_VALUE=8000000
CDEFS+=-D__FPU_PRESENT=1
CDEFS+=-D__FPU_USED=1
CDEFS+=-DARM_MATH_CM4

MCUFLAGS=-mcpu=cortex-m4 -mthumb -mfloat-abi=hard
COMMONFLAGS=-O$(OPTLVL) $(DBG) -Wall -ffunction-sections -fdata-sections
CFLAGS=$(COMMONFLAGS) $(MCUFLAGS) $(INCLUDE) $(CDEFS) -falign-functions=32
LDLIBS=$(TOOLCHAIN_ROOT)/arm-none-eabi/lib/armv7e-m/fpu/libc.a $(TOOLCHAIN_ROOT)/arm-none-eabi/lib/armv7e-m/fpu/libm.a
LDFLAGS=$(COMMONFLAGS) -fno-exceptions -nostartfiles
SEUFLAG=-finstrument-functions

INITIAL_LINKERSCRIPT=-Tseu/initial_seu_link.ld
SECONDARY_LINKERSCRIPT=-Tseu/gen/secondary_seu_link.ld
HEADER_SRC=seu/gen/secondary_seu_headers.c 
HEADER_OBJ=build/secondary_seu_headers.o
TRACE_FILE = seu/src/trace_functions.c
TRACE_OBJ = build/trace_functions.o

CC=$(TOOLCHAIN_PREFIX)-gcc
LD=$(TOOLCHAIN_PREFIX)-gcc
OBJCOPY=$(TOOLCHAIN_PREFIX)-objcopy
AS=$(TOOLCHAIN_PREFIX)-as
AR=$(TOOLCHAIN_PREFIX)-ar
GDB=$(TOOLCHAIN_PREFIX)-gdb

GCC=gcc #Standard Desktop GCC

READELF = arm-none-eabi-readelf
PYTHON = python

OBJ = $(SRC:%.c=$(BUILD_DIR)/%.o)

all: FINAL_COMPILATION 

utils:
	@$(GCC) $(CRC_SRCS) -o crcGenerator

$(BUILD_DIR)/%.o: %.c
	@echo [CC] $(notdir $<)
	@$(CC) $(CFLAGS) $(SEUFLAG) $< -c -o $@

UNCHECKED_OBJS: $(OBJ)
	@$(CC) $(CFLAGS) hardware/stm32f4xx_it.c -c -o build/stm32f4xx_it.o
	@$(CC) $(CFLAGS) $(TRACE_FILE) -c -o $(TRACE_OBJ)

INITIAL_COMPILATION: UNCHECKED_OBJS
	@echo "[AS] $(ASRC)"
	@$(AS) -o $(ASRC:%.s=$(BUILD_DIR)/%.o) $(STARTUP)/$(ASRC)
	@echo [LD] $(TARGET).elf
	@$(CC) -o $(BIN_DIR)/initial$(TARGET).elf $(INITIAL_LINKERSCRIPT) $(LDFLAGS) $(OBJ) $(TRACE_OBJ) $(ASRC:%.s=$(BUILD_DIR)/%.o) $(LDLIBS)

INITIAL_PROFILER: INITIAL_COMPILATION
	@echo "Starting Initial Profiler"
	@$(READELF) -s --wide $(BIN_DIR)/initial$(TARGET).elf | grep "FUNC" | awk '{print $$2 " " $$3 " " $$8}' > seu/gen/addressDump.data
	@$(PYTHON) seu/initial_profiler.py
	@$(CC) $(CFLAGS) -c $(HEADER_SRC) -o $(HEADER_OBJ)
	@echo "initial Profiler Completed"

SECONDARY_COMPILATION: INITIAL_PROFILER
	@echo "Starting Secondary Complilation"
	@$(CC) -o $(BIN_DIR)/secondary$(TARGET).elf $(SECONDARY_LINKERSCRIPT) $(LDFLAGS) $(OBJ) $(TRACE_OBJ) $(HEADER_OBJ) $(ASRC:%.s=$(BUILD_DIR)/%.o) $(LDLIBS)
	@echo "Secondary Complilation Completed"

SECONDARY_PROFILER: SECONDARY_COMPILATION
	@echo "Starting Secondary Profiler"
	@rm $(HEADER_OBJ)
	@$(READELF) -x .text $(BIN_DIR)/secondary$(TARGET).elf | sed '3q;d' | awk '{print $$1}' > seu/gen/startAddr.data
	@$(READELF) -x .text $(BIN_DIR)/secondary$(TARGET).elf | awk '{print $$2 $$3 $$4 $$5}' > seu/gen/textHexDump.hex
	@$(READELF) -s $(BIN_DIR)/secondary$(TARGET).elf | grep "FUNC" | awk '{print $$2 " " $$3 " " $$8}' > seu/gen/addressDump.data
	@$(PYTHON) seu/secondary_profiler.py
	@$(CC) $(CFLAGS) -c $(HEADER_SRC) -o $(HEADER_OBJ)
	@echo "Secondary Profiler Complete"

FINAL_COMPILATION: SECONDARY_PROFILER
	@$(CC) -o $(BIN_DIR)/final$(TARGET).elf $(SECONDARY_LINKERSCRIPT) $(LDFLAGS)  $(OBJ) $(TRACE_OBJ) $(HEADER_OBJ) $(ASRC:%.s=$(BUILD_DIR)/%.o) $(LDLIBS)
	@echo "\nfinal link complete: binary/final$(TARGET).elf"

.PHONY: clean

clean:
	@echo [RM] OBJ
	@rm -f $(OBJ)
	@rm -f build/*.o
	@rm -f binary/*.elf
	@rm -f seu/gen/*
	@rm -f $(ASRC:%.s=$(BUILD_DIR)/%.o)
	@echo [RM] BIN
	@rm -f $(BIN_DIR)/$(TARGET).elf
