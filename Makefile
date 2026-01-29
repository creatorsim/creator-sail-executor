# Select architecture: RV32 or RV64.
ARCH ?= RV64# valor por defecto

ifeq ($(ARCHS),32)
  override ARCH := RV32
else ifeq ($(ARCHS),64)
  override ARCH := RV64
endif

# Set OPAMCLI to 2.0 to supress warnings about opam config var
export OPAMCLI := 2.0

ifeq ($(ARCH),RV32)
  SAIL_XLEN := riscv_xlen32.sail
else ifeq ($(ARCH),RV64)
  SAIL_XLEN := riscv_xlen64.sail
else
  $(error '$(ARCH)' is not a valid architecture, must be one of: RV32, RV64)
endif


SAIL_FLEN := riscv_flen_D.sail
SAIL_VLEN := riscv_vlen.sail

# Instruction sources, depending on target
SAIL_CHECK_SRCS = riscv_addr_checks_common.sail riscv_addr_checks.sail riscv_misa_ext.sail
SAIL_DEFAULT_INST = riscv_insts_base.sail creator_insts.sail riscv_insts_aext.sail riscv_insts_cext.sail riscv_insts_mext.sail riscv_insts_zicsr.sail riscv_insts_next.sail riscv_insts_hints.sail # 
SAIL_DEFAULT_INST += riscv_insts_fext.sail riscv_insts_cfext.sail
SAIL_DEFAULT_INST += riscv_insts_dext.sail riscv_insts_cdext.sail

SAIL_DEFAULT_INST += riscv_insts_svinval.sail

SAIL_DEFAULT_INST += riscv_insts_zba.sail
SAIL_DEFAULT_INST += riscv_insts_zbb.sail
SAIL_DEFAULT_INST += riscv_insts_zbc.sail
SAIL_DEFAULT_INST += riscv_insts_zbs.sail

SAIL_DEFAULT_INST += riscv_insts_zcb.sail

SAIL_DEFAULT_INST += riscv_insts_zfh.sail
# Zfa needs to be added after fext, dext and Zfh (as it needs
# definitions from those)
SAIL_DEFAULT_INST += riscv_insts_zfa.sail

SAIL_DEFAULT_INST += riscv_insts_zkn.sail
SAIL_DEFAULT_INST += riscv_insts_zks.sail

SAIL_DEFAULT_INST += riscv_insts_zbkb.sail
SAIL_DEFAULT_INST += riscv_insts_zbkx.sail

SAIL_DEFAULT_INST += riscv_insts_zicond.sail

SAIL_DEFAULT_INST += riscv_insts_vext_utils.sail
SAIL_DEFAULT_INST += riscv_insts_vext_fp_utils.sail
SAIL_DEFAULT_INST += riscv_insts_vext_vset.sail
SAIL_DEFAULT_INST += riscv_insts_vext_arith.sail

ifeq ($(ARCH), RV64)
	SAIL_DEFAULT_INST += riscv_insts_vext_fp.sail
else 
	SAIL_DEFAULT_INST += riscv_insts_vext_fp32.sail
endif

SAIL_DEFAULT_INST += riscv_insts_vext_mem.sail
SAIL_DEFAULT_INST += riscv_insts_vext_mask.sail
SAIL_DEFAULT_INST += riscv_insts_vext_vm.sail
SAIL_DEFAULT_INST += riscv_insts_vext_fp_vm.sail
SAIL_DEFAULT_INST += riscv_insts_vext_red.sail
SAIL_DEFAULT_INST += riscv_insts_vext_fp_red.sail

SAIL_SEQ_INST  = $(SAIL_DEFAULT_INST) riscv_jalr_seq.sail
SAIL_RMEM_INST = $(SAIL_DEFAULT_INST) riscv_jalr_rmem.sail riscv_insts_rmem.sail

SAIL_SEQ_INST_SRCS  = riscv_insts_begin.sail $(SAIL_SEQ_INST) riscv_insts_end.sail
SAIL_RMEM_INST_SRCS = riscv_insts_begin.sail $(SAIL_RMEM_INST) riscv_insts_end.sail

# System and platform sources
SAIL_SYS_SRCS =  riscv_csr_map.sail
SAIL_SYS_SRCS += riscv_vext_control.sail    # helpers for the 'V' extension
SAIL_SYS_SRCS += riscv_next_regs.sail
SAIL_SYS_SRCS += riscv_softfloat_interface.sail riscv_fdext_regs.sail riscv_fdext_control.sail
SAIL_SYS_SRCS += riscv_char_mapping.sail
SAIL_SYS_SRCS += riscv_sys_exceptions.sail  # default basic helpers for exception handling
SAIL_SYS_SRCS += riscv_sync_exception.sail  # define the exception structure used in the model
SAIL_SYS_SRCS += riscv_next_control.sail    # helpers for the 'N' extension
SAIL_SYS_SRCS += riscv_csr_ext.sail         # access to CSR extensions
SAIL_SYS_SRCS += riscv_sys_control.sail     # general exception handling

# SAIL_RV32_VM_SRCS = riscv_vmem_sv32.sail riscv_vmem_rv32.sail
# SAIL_RV64_VM_SRCS = riscv_vmem_sv39.sail riscv_vmem_sv48.sail riscv_vmem_rv64.sail

# SAIL_VM_SRCS = riscv_pte.sail riscv_ptw.sail riscv_vmem_common.sail riscv_vmem_tlb.sail
# ifeq ($(ARCH),RV32)
# SAIL_VM_SRCS += $(SAIL_RV32_VM_SRCS)
# else
# SAIL_VM_SRCS += $(SAIL_RV64_VM_SRCS)
# endif

SAIL_VM_SRCS += riscv_vmem_common.sail
SAIL_VM_SRCS += riscv_vmem_pte.sail
SAIL_VM_SRCS += riscv_vmem_ptw.sail
SAIL_VM_SRCS += riscv_vmem_tlb.sail
SAIL_VM_SRCS += riscv_vmem.sail

# Non-instruction sources
PRELUDE = prelude.sail $(SAIL_XLEN) $(SAIL_FLEN) $(SAIL_VLEN) prelude_mem_metadata.sail prelude_mem.sail

SAIL_REGS_SRCS = riscv_reg_type.sail riscv_freg_type.sail riscv_regs.sail riscv_pc_access.sail riscv_sys_regs.sail
SAIL_REGS_SRCS += riscv_pmp_regs.sail riscv_pmp_control.sail
SAIL_REGS_SRCS += riscv_ext_regs.sail $(SAIL_CHECK_SRCS)
SAIL_REGS_SRCS += riscv_vreg_type.sail riscv_vext_regs.sail

SAIL_ARCH_SRCS = $(PRELUDE)
SAIL_ARCH_SRCS += riscv_types_common.sail riscv_types_ext.sail riscv_types.sail
SAIL_ARCH_SRCS += riscv_vmem_types.sail $(SAIL_REGS_SRCS) $(SAIL_SYS_SRCS) riscv_platform.sail
SAIL_ARCH_SRCS += riscv_mem.sail $(SAIL_VM_SRCS)
SAIL_ARCH_RVFI_SRCS = $(PRELUDE) rvfi_dii.sail riscv_types_common.sail riscv_types_ext.sail riscv_types.sail riscv_vmem_types.sail $(SAIL_REGS_SRCS) $(SAIL_SYS_SRCS) riscv_platform.sail riscv_mem.sail $(SAIL_VM_SRCS) riscv_types_kext.sail
SAIL_ARCH_SRCS += riscv_types_kext.sail    # Shared/common code for the cryptography extension.

SAIL_STEP_SRCS = riscv_step_common.sail riscv_step_ext.sail riscv_decode_ext.sail riscv_fetch.sail riscv_step.sail
RVFI_STEP_SRCS = riscv_step_common.sail riscv_step_rvfi.sail riscv_decode_ext.sail riscv_fetch_rvfi.sail riscv_step.sail

SAIL_OTHER_SRCS     = $(SAIL_STEP_SRCS)
ifeq ($(ARCH),RV32)
SAIL_OTHER_COQ_SRCS = riscv_termination_common.sail riscv_termination_rv32.sail
else
SAIL_OTHER_COQ_SRCS = riscv_termination_common.sail riscv_termination_rv64.sail
endif

PRELUDE_SRCS   = $(addprefix model/,$(PRELUDE))
SAIL_SRCS      = $(addprefix model/,$(SAIL_ARCH_SRCS) $(SAIL_SEQ_INST_SRCS)  $(SAIL_OTHER_SRCS))
SAIL_RMEM_SRCS = $(addprefix model/,$(SAIL_ARCH_SRCS) $(SAIL_RMEM_INST_SRCS) $(SAIL_OTHER_SRCS))
SAIL_RVFI_SRCS = $(addprefix model/,$(SAIL_ARCH_RVFI_SRCS) $(SAIL_SEQ_INST_SRCS) $(RVFI_STEP_SRCS))
SAIL_COQ_SRCS  = $(addprefix model/,$(SAIL_ARCH_SRCS) $(SAIL_SEQ_INST_SRCS) $(SAIL_OTHER_COQ_SRCS))

PLATFORM_OCAML_SRCS = $(addprefix ocaml_emulator/,platform.ml platform_impl.ml softfloat.ml riscv_ocaml_sim.ml)

SAIL_FLAGS += -dno_cast
# SAIL_FLAGS += --all-warnings
# SAIL_FLAGS += -dmagic_hash
SAIL_DOC_FLAGS ?= -doc_embed plain

# Attempt to work with either sail from opam or built from repo in SAIL_DIR
ifneq ($(SAIL_DIR),)
# Use sail repo in SAIL_DIR
SAIL:=$(SAIL_DIR)/sail
export SAIL_DIR
EXPLICIT_COQ_SAIL=yes
else
# Use sail from opam package
SAIL_DIR:=$(shell OPAMCLI=$(OPAMCLI) opam config var sail:share)
SAIL:=sail
endif
SAIL_LIB_DIR:=$(SAIL_DIR)/lib
export SAIL_LIB_DIR
SAIL_SRC_DIR:=$(SAIL_DIR)/src

ifndef LEM_DIR
LEM_DIR:=$(shell OPAMCLI=$(OPAMCLI) opam config var lem:share)
endif
export LEM_DIR

C_WARNINGS ?=
#-Wall -Wextra -Wno-unused-label -Wno-unused-parameter -Wno-unused-but-set-variable -Wno-unused-function
C_INCS = $(addprefix c_emulator/,riscv_prelude.h riscv_platform_impl.h riscv_platform.h riscv_softfloat.h)
C_SRCS = $(addprefix c_emulator/,riscv_prelude.c riscv_platform_impl.c riscv_platform.c riscv_softfloat.c riscv_sim.c)

SOFTFLOAT_DIR    = c_emulator/SoftFloat-3e
SOFTFLOAT_INCDIR = $(SOFTFLOAT_DIR)/source/include
SOFTFLOAT_LIBDIR = $(SOFTFLOAT_DIR)/build/Linux-RISCV-GCC
SOFTFLOAT_FLAGS  = -I $(SOFTFLOAT_INCDIR)
SOFTFLOAT_LIBS   = $(SOFTFLOAT_LIBDIR)/softfloat.a
SOFTFLOAT_SPECIALIZE_TYPE = RISCV
	
ifeq ($(ARCH), RV32)
  ifeq ($(LOCAL), 0)
	GMP_LIBS = $(GMP_EM_DIR)/lib/libgmp.a
# 	GMP_EM_DIR = /home/juancarlos/newlibgmp
# 	GMP_EM_DIR = /home/juancarlos/Descargas/gmp-6.3.0/gmp-emscripten32
# 	GMP_LIBS = $(GMP_EM_DIR)/lib/libgmp.a
  else
  	GMP_FLAGS = $(shell pkg-config --cflags gmp)
  	GMP_LIBS = $(shell pkg-config --libs gmp || echo -lgmp)
  endif	
else
  ifeq ($(LOCAL), 0)
	GMP_LIBS = $(GMP_EM_DIR)/lib/libgmp.a
# 	GMP_EM_DIR = /home/juancarlos/newlibgmp
  else
	GMP_FLAGS = $(shell pkg-config --cflags gmp)
	GMP_LIBS = $(shell pkg-config --libs gmp || echo -lgmp)
  endif	
endif

# ZLIB_EM_DIR = /home/juancarlos/Descargas/zlib-1.3.1/zlib-emscripten
# ZLIB_LIBS = $(ZLIB_EM_DIR)/lib/libz.a

# GMP_FLAGS = $(shell pkg-config --cflags gmp)
# N.B. GMP does not have pkg-config metadata on Ubuntu 18.04 so default to -lgmp
# GMP_LIBS = $(shell pkg-config --libs gmp || echo -lgmp)

ifeq ($(LOCAL), 1)
ZLIB_FLAGS = $(shell pkg-config --cflags zlib)
ZLIB_LIBS = $(shell pkg-config --libs zlib)
else
EM_FLAGS = -s USE_ZLIB=1
endif

ifeq ($(LOCAL), 0)
C_FLAGS = -I $(GMP_EM_DIR)/include  $(EM_FLAGS) -I $(SAIL_LIB_DIR) -I c_emulator $(GMP_FLAGS) $(ZLIB_FLAGS) $(SOFTFLOAT_FLAGS)
C_LIBS  =  $(SOFTFLOAT_LIBS) $(GMP_LIBS) 
else
C_FLAGS = -I $(SAIL_LIB_DIR) -I c_emulator $(GMP_FLAGS) $(ZLIB_FLAGS) $(SOFTFLOAT_FLAGS)
C_LIBS  = $(GMP_LIBS) $(ZLIB_LIBS) $(SOFTFLOAT_LIBS)
endif

# The C simulator can be built to be linked against Spike for tandem-verification.
# This needs the C bindings to Spike from https://github.com/SRI-CSL/l3riscv
# TV_SPIKE_DIR in the environment should point to the top-level dir of the L3
# RISC-V, containing the built C bindings to Spike.
# RISCV should be defined if TV_SPIKE_DIR is.
ifneq (,$(TV_SPIKE_DIR))
C_FLAGS += -I $(TV_SPIKE_DIR)/src/cpp -DENABLE_SPIKE
C_LIBS  += -L $(TV_SPIKE_DIR) -ltv_spike -Wl,-rpath=$(TV_SPIKE_DIR)
C_LIBS  += -L $(RISCV)/lib -lfesvr -lriscv -Wl,-rpath=$(RISCV)/lib
endif

# SAIL_FLAGS = -dtc_verbose 4

ifneq (,$(COVERAGE))
C_FLAGS += --coverage -O1
SAIL_FLAGS += -Oconstant_fold
else
C_FLAGS += -O3 -flto=auto
endif

ifneq (,$(SAILCOV))
ALL_BRANCHES = generated_definitions/c/all_branches
C_FLAGS += -DSAILCOV
SAIL_FLAGS += -c_coverage $(ALL_BRANCHES) -c_include sail_coverage.h
C_LIBS += $(SAIL_LIB_DIR)/coverage/libsail_coverage.a -lm -lpthread -ldl
endif



ifeq ($(ARCH),RV32)
  C_FLAGS += -DRV32
else ifeq ($(ARCH),RV64)
  C_FLAGS += -DRV64
else
  $(error '$(ARCH)' is not a valid architecture, must be one of: RV32, RV64)
endif

ifeq ($(LOCAL),1)
# 	SAIL_XLEN += riscv_xlocal.sail
	C_FLAGS += -DLOCALSIM
else ifeq ($(LOCAL),0)
	C_FLAGS += -DWEBSIM
# 	SAIL_XLEN += riscv_xweb.sail
endif

RISCV_EXTRAS_LEM_FILES = riscv_extras.lem mem_metadata.lem riscv_extras_fdext.lem
RISCV_EXTRAS_LEM = $(addprefix handwritten_support/,$(RISCV_EXTRAS_LEM_FILES))

.PHONY:

all: c_emulator/riscv_sim_$(ARCH).js
.PHONY: all

# the following ensures empty sail-generated .c files don't hang around and
# break future builds if sail exits badly
.DELETE_ON_ERROR: generated_definitions/c/%.c

check: $(SAIL_SRCS) model/main.sail Makefile
	$(SAIL) $(SAIL_FLAGS) $(SAIL_SRCS) model/main.sail

interpret: $(SAIL_SRCS) model/main.sail
	$(SAIL) -i $(SAIL_FLAGS) $(SAIL_SRCS) model/main.sail

sail_doc/riscv_$(ARCH).json: $(SAIL_SRCS) model/main.sail
	$(SAIL) -doc -doc_bundle riscv_$(ARCH).json -o sail_doc $(SAIL_FLAGS) $(SAIL_DOC_FLAGS) $(SAIL_SRCS) model/main.sail

riscv.smt_model: $(SAIL_SRCS)
	$(SAIL) -smt_serialize $(SAIL_FLAGS) $(SAIL_SRCS) -o riscv

cgen: $(SAIL_SRCS) model/main.sail
	$(SAIL) -cgen $(SAIL_FLAGS) $(SAIL_SRCS) model/main.sail


c_preserve_fns=-c_preserve _set_Misa_C

generated_definitions/c/riscv_model_$(ARCH).c: $(SAIL_SRCS) model/main.sail Makefile
	mkdir -p generated_definitions/c
	$(SAIL) $(SAIL_FLAGS) $(c_preserve_fns) -O -Oconstant_fold -memo_z3 -c -c_include riscv_prelude.h -c_include riscv_platform.h -c_no_main $(SAIL_SRCS) model/main.sail -o $(basename $@)

$(SOFTFLOAT_LIBS):
ifeq ($(ARCH),RV64)
  ifeq ($(LOCAL),1)
	$(MAKE) SPECIALIZE_TYPE=$(SOFTFLOAT_SPECIALIZE_TYPE) -C $(SOFTFLOAT_LIBDIR) BITS=64 LOCAL=1
  else
	$(MAKE) SPECIALIZE_TYPE=$(SOFTFLOAT_SPECIALIZE_TYPE) -C $(SOFTFLOAT_LIBDIR) BITS=64 LOCAL=0
  endif
else
  ifeq ($(LOCAL),1)
	$(MAKE) SPECIALIZE_TYPE=$(SOFTFLOAT_SPECIALIZE_TYPE) -C $(SOFTFLOAT_LIBDIR) BITS=32 LOCAL=1
  else
	$(MAKE) SPECIALIZE_TYPE=$(SOFTFLOAT_SPECIALIZE_TYPE) -C $(SOFTFLOAT_LIBDIR) BITS=32 LOCAL=0
  endif
endif

# convenience target
.PHONY: csim
csim: c_emulator/riscv_sim_$(ARCH).js

c_emulator/riscv_sim_RV64: generated_definitions/c/riscv_model_RV64.c $(C_INCS) $(C_SRCS) $(SOFTFLOAT_LIBS) Makefile
ifeq ($(LOCAL),0)
	emcc -sENVIRONMENT=web -s ASYNCIFY -s NO_EXIT_RUNTIME=1 \
			-s DEFAULT_LIBRARY_FUNCS_TO_INCLUDE='["emscripten_run_script","emscripten_run_script_int","emscripten_cancel_main_loop","emscripten_sleep", "emscripten_force_exit"]' \
			-s INITIAL_MEMORY=64MB -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1 -sMEMORY64=1 -s MODULARIZE=1 -s EXPORT_ES6=1 \
			-s EXPORTED_FUNCTIONS="['_free','_malloc','_reanudar_ejecucion','_main', "_send_int_to_C", "_send_float_to_C", "_send_double_to_C", "_send_char_to_C", "_send_string_to_C"]" \
			-s EXPORTED_RUNTIME_METHODS="['FS','ccall','callMain','stringToUTF8','lengthBytesUTF8','run']" -O3 \
			$(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@.js
# 	emcc -sENVIRONMENT=web -s ASYNCIFY -s NO_EXIT_RUNTIME=1 \
# 		-s DEFAULT_LIBRARY_FUNCS_TO_INCLUDE='["emscripten_run_script","emscripten_run_script_int","emscripten_cancel_main_loop","emscripten_sleep", "emscripten_force_exit"]' \
# 		-s INITIAL_MEMORY=64MB -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1 -sMEMORY64=1 \
# 		-s EXPORTED_FUNCTIONS="['_free','_malloc','_reanudar_ejecucion','_main', "_send_int_to_C", "_send_float_to_C", "_send_double_to_C", "_send_char_to_C", "_send_string_to_C"]" \
# 		-s EXPORTED_RUNTIME_METHODS="['ccall','callMain']" -O3 \
# 		$(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@.js
else 
	$(CC) -g $(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@
endif


c_emulator/riscv_sim_RV32: generated_definitions/c/riscv_model_RV32.c $(C_INCS) $(C_SRCS) $(SOFTFLOAT_LIBS) Makefile
ifeq ($(LOCAL),0)
	emcc -sENVIRONMENT=web -s ASYNCIFY -s EXIT_RUNTIME=0 -s NO_EXIT_RUNTIME=1 \
		-s WASM_BIGINT=1 \
		-s DEFAULT_LIBRARY_FUNCS_TO_INCLUDE='["emscripten_run_script","emscripten_run_script_int","emscripten_cancel_main_loop","emscripten_sleep","emscripten_force_exit"]' \
		-s INITIAL_MEMORY=64MB -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1 -sMEMORY64=0 -s MODULARIZE=1 -s EXPORT_ES6=1 \
		-s EXPORTED_FUNCTIONS='["_reanudar_ejecucion","_main","_send_int_to_C","_send_float_to_C","_send_double_to_C","_send_char_to_C","_send_string_to_C"]' \
		-s EXPORTED_RUNTIME_METHODS="['FS','ccall','callMain','stringToUTF8','lengthBytesUTF8']" -O3 \
		--cache $(EM_CACHE) $(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@.js
# 	emcc -sENVIRONMENT=web -s ASYNCIFY -s EXIT_RUNTIME=0 -s NO_EXIT_RUNTIME=1 \
		-s WASM_BIGINT=1 \
		-s DEFAULT_LIBRARY_FUNCS_TO_INCLUDE='["emscripten_run_script","emscripten_run_script_int","emscripten_cancel_main_loop","emscripten_sleep","emscripten_force_exit"]' \
		-s INITIAL_MEMORY=64MB -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1 -sMEMORY64=0 \
		-s EXPORTED_FUNCTIONS='["_reanudar_ejecucion","_main","_send_int_to_C","_send_float_to_C","_send_double_to_C","_send_char_to_C","_send_string_to_C"]' \
		-s EXPORTED_RUNTIME_METHODS="['ccall','callMain']" -O3 \
		--cache $(EM_CACHE) $(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@.js
else
	$(CC) -g $(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@
endif
# 		echo "Trying to creato a Web simulator in LOCAL environment. Please use LOCAL=0 in make arguments.";


#
#	PARA EL CASO DE GENERAR EL SIMULADOR DE 32 BITS EN WASM64
#
# c_emulator/riscv_sim_RV32: generated_definitions/c/riscv_model_RV32.c $(C_INCS) $(C_SRCS) $(SOFTFLOAT_LIBS) Makefile
# ifeq ($(LOCAL),0)
# 	emcc -sENVIRONMENT=web -s ASYNCIFY -s NO_EXIT_RUNTIME=1 \
# 			-s DEFAULT_LIBRARY_FUNCS_TO_INCLUDE='["emscripten_run_script","emscripten_run_script_int","emscripten_cancel_main_loop","emscripten_sleep", "emscripten_force_exit"]' \
# 			-s INITIAL_MEMORY=64MB -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1 -sMEMORY64=1 -s MODULARIZE=1 -s EXPORT_ES6=1 \
# 			-s EXPORTED_FUNCTIONS="['_free','_malloc','_reanudar_ejecucion','_main', "_send_int_to_C", "_send_float_to_C", "_send_double_to_C", "_send_char_to_C", "_send_string_to_C"]" \
# 			-s EXPORTED_RUNTIME_METHODS="['FS','ccall','callMain','stringToUTF8','lengthBytesUTF8','run']" -O3 \
# 			$(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@.js
# # 	emcc -sENVIRONMENT=web -s ASYNCIFY -s EXIT_RUNTIME=0 -s NO_EXIT_RUNTIME=1 \
# 		-s WASM_BIGINT=1 \
# 		-s DEFAULT_LIBRARY_FUNCS_TO_INCLUDE='["emscripten_run_script","emscripten_run_script_int","emscripten_cancel_main_loop","emscripten_sleep","emscripten_force_exit"]' \
# 		-s INITIAL_MEMORY=64MB -s ASSERTIONS=1 -s ALLOW_MEMORY_GROWTH=1 -sMEMORY64=0 \
# 		-s EXPORTED_FUNCTIONS='["_reanudar_ejecucion","_main","_send_int_to_C","_send_float_to_C","_send_double_to_C","_send_char_to_C","_send_string_to_C"]' \
# 		-s EXPORTED_RUNTIME_METHODS="['ccall','callMain']" -O3 \
# 		--cache $(EM_CACHE) $(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@.js
# else
# 	$(CC) -g $(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@
# endif




# -s EXPORT_NAME="RVModule" -s MODULARIZE=1


# ifeq ($(LOCAL), 1)	
# 	c_emulator/riscv_sim_$(ARCH).c: generated_definitions/c/riscv_model_$(ARCH).c $(C_INCS) $(C_SRCS) $(SOFTFLOAT_LIBS) Makefile
# 		$(CC) -g $(C_WARNINGS) $(C_FLAGS) $< $(C_SRCS) $(SAIL_LIB_DIR)/*.c $(C_LIBS) -o $@
# endif


	# -s EXPORT_NAME="RVModule" -s MODULARIZE=1 --cache $(EM_CACHE) -s EXIT_RUNTIME=0 

FORCE:

clean:
	-rm -rf generated_definitions/ocaml/* generated_definitions/c/* generated_definitions/latex/*
	-rm -rf generated_definitions/lem/* generated_definitions/isabelle/* generated_definitions/hol4/* generated_definitions/coq/*
	-rm -rf generated_definitions/for-rmem/*
	-$(MAKE) -C $(SOFTFLOAT_LIBDIR) clean
	-rm -f c_emulator/riscv_sim_RV32.* c_emulator/riscv_sim_RV64.*  c_emulator/riscv_rvfi_RV32.* c_emulator/riscv_rvfi_RV64.*
	-rm -rf ocaml_emulator/_sbuild ocaml_emulator/_build ocaml_emulator/riscv_ocaml_sim_RV32 ocaml_emulator/riscv_ocaml_sim_RV64 ocaml_emulator/tracecmp
	-rm -f *.gcno *.gcda
	-rm -f z3_problems
	-Holmake cleanAll
	-rm -f handwritten_support/riscv_extras.vo handwritten_support/riscv_extras.vos handwritten_support/riscv_extras.vok handwritten_support/riscv_extras.glob handwritten_support/.riscv_extras.aux
	-rm -f handwritten_support/mem_metadata.vo handwritten_support/mem_metadata.vos handwritten_support/mem_metadata.vok handwritten_support/mem_metadata.glob handwritten_support/.mem_metadata.aux
	-rm -f sail_doc/riscv_RV32.json
	-rm -f sail_doc/riscv_RV64.json
	ocamlbuild -clean
