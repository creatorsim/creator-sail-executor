#include "sail.h"
#include "rts.h"
#include "riscv_prelude.h"
#include "riscv_platform_impl.h"
#include "riscv_sail.h"
#ifndef LOCALSIM
  #include <emscripten.h>
#endif
#include <math.h>
#include <time.h>

#ifdef DEBUG_RESERVATION
#include <stdio.h>
#include <inttypes.h>
#define RESERVATION_DBG(args...) fprintf(stderr, args)
#else
#define RESERVATION_DBG(args...)
#endif

/* This file contains the definitions of the C externs of Sail model. */

static mach_bits reservation = 0;
static bool reservation_valid = false;

typedef struct {
  uint32_t low_double;
  uint32_t high_double;
} double_32;
double_32 double_to_split;
bool debug_mode = true;
int should_pause = -1;
bool first_it = true;
int int_keyboard = -1;
float f_keyboard = -1;
double d_keyboard = -1;
char c_keyboard;
char *s_keyboard;
bool force_exit = false;

bool sys_enable_rvc(unit u)
{
  return rv_enable_rvc;
}

bool sys_enable_next(unit u)
{
  return rv_enable_next;
}

bool sys_enable_fdext(unit u)
{
  return rv_enable_fdext;
}

bool sys_enable_svinval(unit u)
{
  return rv_enable_svinval;
}

bool sys_enable_zcb(unit u)
{
  return rv_enable_zcb;
}

bool sys_enable_zfinx(unit u)
{
  // printf("zfinx es verdadero? %d\n",rv_enable_zfinx);
  return rv_enable_zfinx;
}

bool sys_enable_writable_fiom(unit u)
{
  return rv_enable_writable_fiom;
}

bool sys_enable_vext(unit u)
{
  return rv_enable_vext;
}

bool sys_enable_bext(unit u)
{
  return rv_enable_bext;
}

uint64_t sys_pmp_count(unit u)
{
  return rv_pmp_count;
}

uint64_t sys_pmp_grain(unit u)
{
  return rv_pmp_grain;
}

bool sys_enable_writable_misa(unit u)
{
  return rv_enable_writable_misa;
}

bool plat_enable_dirty_update(unit u)
{
  return rv_enable_dirty_update;
}

bool plat_enable_misaligned_access(unit u)
{
  return rv_enable_misaligned;
}

bool plat_mtval_has_illegal_inst_bits(unit u)
{
  return rv_mtval_has_illegal_inst_bits;
}

mach_bits plat_ram_base(unit u)
{
  return rv_ram_base;
}

mach_bits plat_ram_size(unit u)
{
  return rv_ram_size;
}

mach_bits plat_rom_base(unit u)
{
  return rv_rom_base;
}

mach_bits plat_rom_size(unit u)
{
  return rv_rom_size;
}

// Provides entropy for the scalar cryptography extension.
mach_bits plat_get_16_random_bits(unit u)
{
  return rv_16_random_bits();
}

mach_bits plat_clint_base(unit u)
{
  return rv_clint_base;
}

mach_bits plat_clint_size(unit u)
{
  return rv_clint_size;
}

unit load_reservation(mach_bits addr)
{
  reservation = addr;
  reservation_valid = true;
  RESERVATION_DBG("reservation <- %0" PRIx64 "\n", reservation);
  return UNIT;
}

bool speculate_conditional(unit u)
{
  return true;
}

static mach_bits check_mask(void)
{
  return (zxlen_val == 32) ? 0x00000000FFFFFFFF : -1;
}

bool match_reservation(mach_bits addr)
{
  mach_bits mask = check_mask();
  bool ret = reservation_valid && (reservation & mask) == (addr & mask);
  RESERVATION_DBG("reservation(%c): %0" PRIx64 ", key=%0" PRIx64 ": %s\n",
                  reservation_valid ? 'v' : 'i', reservation, addr,
                  ret ? "ok" : "fail");
  return ret;
}

unit cancel_reservation(unit u)
{
  RESERVATION_DBG("reservation <- none\n");
  reservation_valid = false;
  return UNIT;
}

unit plat_term_write(mach_bits s)
{
  char c = s & 0xff;
  plat_term_write_impl(c);
  return UNIT;
}

void plat_insns_per_tick(sail_int *rop, unit u) { }

mach_bits plat_htif_tohost(unit u)
{
  return rv_htif_tohost;
}

unit memea(mach_bits len, sail_int n)
{
  return UNIT;
}


unit print_test_C(mach_bits argument, bool rt){
  if(rt == true){
    double result;
    memcpy(&result, &argument, sizeof(double));
    printf("ECALL DOUBLE: %lf\n", result);
  }
  else 
    printf("ECALL FLOAT: %f\n", *(float*)&argument);
    return UNIT;
}


unit print_string_C(char* message){
  printf("ECALL STRING: %s\n", message);
  return UNIT;
}

uint8_t read_s(uint32_t index){
  return (uint8_t)s_keyboard[index];
}

unit send_error_c(unit c){
    printf("err call_convenction\n");
  return UNIT; 
}

uint32_t rand_num(uint16_t a){
  
  uint32_t result = rand() % a;
  printf("Resultado: %d\n", result);
  return result;
}

uint32_t crep(unit c) {
  return crep_value;
}

uint32_t which_cache_levels(unit c) {
  uint32_t result = emscripten_run_script_int("document.app.$data.cache_type");
  printf("Type cache: %d\n", result);
  return result;
}

uint32_t cache_sizes(uint8_t val){
  // printf("Valor recibido %d\n", val);
  uint32_t result;
  switch(val){
    case 1:
      result = emscripten_run_script_int("document.app.$data.L1_size");
      printf("L1 size: %d\n", result);
    break;
    case 2:
      result = emscripten_run_script_int("document.app.$data.L1_I_size");
      printf("L1_I size: %d\n", result);
    break;
    case 3:
      result = emscripten_run_script_int("document.app.$data.L1_D_size");
      printf("L1_D size: %d\n", result);
    break;
    case 4:
      result = emscripten_run_script_int("document.app.$data.L2_size");
      printf("L2 size: %d\n", result);
    break;
    case 5:
      result = emscripten_run_script_int("document.app.$data.L2_I_size");
      printf("L2_I size: %d\n", result);
    break;
    case 6:
      result = emscripten_run_script_int("document.app.$data.L2_D_size");
      printf("L2_D size: %d\n", result);
    break;
  }
  return result;
}


uint32_t cache_line_size(uint8_t val) {
  uint32_t result; // = emscripten_run_script_int("document.app.$data.data_cache_block_size");
  switch(val){
    case 1:
      result = emscripten_run_script_int("document.app.$data.L1_size_block");
    break;
    case 2:
      result = emscripten_run_script_int("document.app.$data.L1_I_size_block");
    break;
    case 3:
      result = emscripten_run_script_int("document.app.$data.L1_D_size_block");
    break;
    case 4:
      result = emscripten_run_script_int("document.app.$data.L2_size_block");
    break;
    case 5:
      result = emscripten_run_script_int("document.app.$data.L2_I_size_block");
    break;
    case 6:
      result = emscripten_run_script_int("document.app.$data.L2_D_size_block");
    break;
  }
  return result;

}

uint32_t set_config(uint8_t val) {
  uint32_t result;
  switch(val){
    case 1: // Caso de que se envían el número de conjuntos
      result = emscripten_run_script_int("document.app.$data.L1_num_lines");
    break;
    case 2: // Caso de que se envían el número de líneas por conjunto
      result = emscripten_run_script_int("document.app.$data.L1_I_num_lines");
    break;
    case 3: // Caso de que se envían el número de líneas por conjunto
      result = emscripten_run_script_int("document.app.$data.L1_D_num_lines");
    break;
    case 4: // Caso de que se envían el número de líneas por conjunto
      result = emscripten_run_script_int("document.app.$data.L2_num_lines");
    break;
    case 5: // Caso de que se envían el número de líneas por conjunto
      result = emscripten_run_script_int("document.app.$data.L2_I_num_lines");
    break;
    case 6: // Caso de que se envían el número de líneas por conjunto
      result = emscripten_run_script_int("document.app.$data.L2_D_num_lines");
    break;
  }
  return result;
}

#ifdef RV32

  uint32_t get_size_field(uint8_t val, uint8_t a){ // a == 0 (tag), a == 1 (index), a == 2 (offset)
    uint32_t result = 0;
    if (emscripten_run_script_int("document.app.$data.isDirect") == 0) {
      switch(val) {
        case 1: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_size") / emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;
            printf("bits para tag:%d\n", result);
          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_size") / emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            
            printf("bits para index:%d\n", result);
          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            printf("bits para offset:%d\n", result);
          }

        break;
        case 2: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_size") / emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_size") / emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 3: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 4: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_size") / emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_size") / emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 5: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;
            
            // result = 32 - aux - (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 6: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;
            // result = 32 - aux - (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = 32 - aux - index;
            // result = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
      }
    } else {
      switch(val) {
        case 1: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;
            printf("bits para tag:%d\n", result);
          } else if (a == 1) {
            uint32_t auxr = ( emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            
            printf("bits para index:%d\n", result);
          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            printf("bits para offset:%d\n", result);
          }

        break;
        case 2: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 3: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 4: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 5: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;
            
            // result = 32 - aux - (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 6: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 32 - aux - index;
            // result = 32 - aux - (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = 32 - aux - index;
            // result = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
      }
      
    } 
    
    return result;
  }

#elif RV64 

  uint32_t get_size_field(uint8_t val, uint8_t a){ // a == 0 (tag), a == 1 (index), a == 2 (offset)
    uint32_t result = 0;
    if (emscripten_run_script_int("document.app.$data.isDirect") == 0) {
      switch(val) {
        case 1: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_size") / emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;
            printf("bits para tag:%d\n", result);
          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_size") / emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            
            printf("bits para index:%d\n", result);
          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            printf("bits para offset:%d\n", result);
          }

        break;
        case 2: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_size") / emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_size") / emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 3: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 4: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_size") / emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_size") / emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 5: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;
            
            // result = 64 - aux - (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 6: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;
            // result = 64 - aux - (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = 64 - aux - index;
            // result = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
      }
    } else {
      switch(val) {
        case 1: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;
            printf("bits para tag:%d\n", result);
          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            
            printf("bits para index:%d\n", result);
          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            printf("bits para offset:%d\n", result);
          }

        break;
        case 2: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_I_num_lines")) - 1;
            
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 3: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L1_D_size") / emscripten_run_script_int("document.app.$data.L1_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L1_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 4: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 5: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;
            
            // result = 64 - aux - (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = (emscripten_run_script_int("document.app.$data.L2_I_size") / emscripten_run_script_int("document.app.$data.L2_I_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_I_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
        case 6: 
          if (a == 0){
            int aux = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (aux == 32) aux = 2;
            else if (aux == 64) aux = 3;
            else if (aux == 128) aux = 4;
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            uint32_t index = 0;
            while (auxr > 0) {
              index++;
              auxr >>= 1;
            }
            result = 64 - aux - index;
            // result = 64 - aux - (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) + 1;

          } else if (a == 1) {
            uint32_t auxr = (emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;
            while (auxr > 0) {
              result++;
              auxr >>= 1;
            }
            // result = 64 - aux - index;
            // result = (emscripten_run_script_int("document.app.$data.L2_D_size") / emscripten_run_script_int("document.app.$data.L2_D_num_lines")) - 1;

          } else if (a == 2) {
            result = emscripten_run_script_int("document.app.$data.L2_D_size_block");
            if (result == 32) result = 2;
            else if (result == 64) result = 3;
            else if (result == 128) result = 4;
            
          }
          
        break;
      }

    }
    return result;
  }

#endif

#ifdef WEBSIM

  uint8_t isDirect(){
    uint8_t result = emscripten_run_script_int("document.app.$data.isDirect");
    return result;
  }

  uint32_t kind_of_cache() {
    return check_cache;
  }
  
  EMSCRIPTEN_KEEPALIVE void send_int_to_C (int value) {
    int_keyboard = value;
    should_pause = 2;
  }

  EMSCRIPTEN_KEEPALIVE void send_float_to_C (float value){
    f_keyboard = value;
    should_pause = 2;
  }

  EMSCRIPTEN_KEEPALIVE void send_double_to_C (double value){
    d_keyboard = value;
    should_pause = 2;
  }

  EMSCRIPTEN_KEEPALIVE void send_char_to_C (char value) {
    c_keyboard = value;
    should_pause = 2;
  }

  EMSCRIPTEN_KEEPALIVE void send_string_to_C (char* value) {
    
    printf("String recibido: %s\n", value);
    if (s_keyboard)
      free(s_keyboard);

    s_keyboard = (char *)malloc(strlen(value) +1);
    if (s_keyboard == NULL) {
          printf("Error al asignar memoria\n");
          return;
      }
    strcpy(s_keyboard, value);
    should_pause = 2;
    
    printf("String almacenado: %s\n", value);
  }


  uint32_t read_int_C(unit c){
    
    while(should_pause != 2){ // Se realiza una espera activa hasta que el usuario haya introducido el valor correspondiente
      emscripten_sleep(100);
    }
    should_pause = -1; // Por ejemplo
    uint32_t result;
    memcpy(&result, &int_keyboard, sizeof(int));

    return result;
  }

  uint32_t read_float_C(unit c){
    while (should_pause != 2)
    {
      emscripten_sleep(100); // Espera activa hasta que se actualice la variable
      printf("Esperando un float\n");
    }
    uint64_t result;
    memcpy(&result, &f_keyboard, sizeof(float));
    should_pause = -1;
    return result;

  }

  uint32_t read_double_32C_low(unit c){
    while (should_pause != 2)
    {
      emscripten_sleep(100); // Espera activa hasta que el usuario pase el parámetro
    }
    
    uint32_t result;
    uint64_t aux;
    memcpy(&aux, &d_keyboard, sizeof(uint64_t));
    result = aux;
    return result;
  }

  uint32_t read_double_32C_high(unit c){
    uint32_t result;
    uint64_t aux;
    memcpy(&aux, &d_keyboard, sizeof(uint64_t));
    result = (uint32_t) (aux >> 32);
    return result;
  }

  uint64_t read_double_64C(unit c){
    while (should_pause != 2)
    {
      emscripten_sleep(100); // Espera activa hasta que el usuario pase el parámetro
      printf("Esperando un double\n");
    }
    
    uint64_t result;
    memcpy(&result, &d_keyboard, sizeof(double));
    should_pause = -1;
    printf("Double a enviar: %llx\n", result);
    return result;
  }

  uint8_t read_char_C(unit c){
    while(should_pause != 2){
      emscripten_sleep(100);
      printf("Esperando un char\n");
    }
    uint32_t result;
    memcpy(&result, &c_keyboard, sizeof(char));
    should_pause = -1;
    return result;
  }

  uint8_t read_string_C(uint8_t size_string){
    while (should_pause != 2)
    {
      emscripten_sleep(100);
    }
      should_pause = -1;
    return (uint8_t)s_keyboard[0];
  }


  EMSCRIPTEN_KEEPALIVE void reanudar_ejecucion(int value) {
    if(value == 5){

      // emscripten_force_exit(1);
      force_exit = true;
    }else {
      should_pause = emscripten_run_script_int("document.app.$data.execution_mode_run");
    }
  }

  bool is_machine_exec(void){
    int aux = emscripten_run_script_int("document.app.$data.c_sudo");
    return (aux == 1 ? true : false);
  }

  uint32_t get_entry(int a) {
    uint32_t default_entry = (zxlen_val == 32) ? 0x80000000u : 0x00000000u;
    // if (is_32bit_model())
    printf("Default entry: %08X \n", default_entry);
    // default instruction 00028293 es lo mismo que t0 = t0 + 0, los 12 bits mas significativos son el imm 
    uint32_t aux = emscripten_run_script_int("document.app.$data.entry_elf");
    printf("Entrada del programa %08X \n", aux);
    
    if(zxlen_val == 32){
      
      uint32_t result = aux - default_entry;
  
      if (result >= 0x1000u && a == 0){ // Redefinimos el lui
        uint32_t new_lui = result / 0x00001000u;
        result = 0x80000u + new_lui;
        result = (result * pow(2, 12)) + 0x000002b7u;
      } else if (result < 0x1000u && a == 0) { // Mantenemos el lui a 0x80000
        result = 0x800002b7u;
      } else if (result >= 0x1000u && a == 1) { // Calculamos el nuevo addi en base al salto del lui
        uint32_t new_addi = result / 0x00001000u;
        new_addi = result - (new_addi * pow(2,12));
        result = (new_addi * pow(2, 20)) + 0x00028293u;
      } else{ // Mantenemos el addi original
        result = (result * pow(2, 20)) + 0x00028293u;
      }

      return result;
    
    } else {

      uint32_t result = aux - default_entry;
      if (result >= 0x1000u && a == 0){ // Redefinimos el lui
        uint32_t new_lui = result / 0x00001000u;
        // result = 0x00000u + new_lui;
        result = (new_lui * pow(2, 12)) + 0x000002b7u;
      } else if (result < 0x1000u && a == 0) { // Mantenemos el lui a 0x0
        result = 0x000002b7u; //0x00000293u;
      } else if (result >= 0x1000u && a == 1) { // Calculamos el nuevo addi en base al salto del lui
        uint32_t new_addi = result / 0x00001000u;
        new_addi = result - (new_addi * pow(2,12));
        result = (new_addi * pow(2, 20)) + 0x00028293u;
      } else{ // Mantenemos el addi original
        result = (result * pow(2, 20)) + 0x00028293u;
      }
      return result;
    }
    // printf("Resultado primero: %08X \n", result);
    // printf("Resultado segundo: %08X \n", result);
  }

  bool kernel_sim(void){
    int aux = emscripten_run_script_int("document.app.$data.c_kernel");
    // printf("kernel?: %d\n", aux);
    return (aux == 1 ? true : false);
  }


  // Función de paso a paso
  bool stepbystep(unit a) {
      // printf("Estoy en debugeo\n");
    if (!first_it){
      // Leer el estado de la ejecución desde JavaScript
      debug_mode = emscripten_run_script_int("document.app.$data.execution_mode_run");
      bool is_next_breakpoint = emscripten_run_script_int("document.app.$data.is_breakpoint");
      
      // Verificar si se debe pausar
      if (debug_mode && (should_pause == -1 || should_pause == 1)) {
        while((should_pause == -1 && debug_mode)){
          if (force_exit){
            exit(1);
            emscripten_run_script("resetenvironment(1)");
          }
          emscripten_sleep(100);
        }
        debug_mode = should_pause;
      } else if (debug_mode == 0 && is_next_breakpoint){
        while((should_pause == -1 && debug_mode == 0)){
          if (force_exit){
            exit(1);
            emscripten_run_script("resetenvironment(1)");
          }
          emscripten_sleep(100);
        }
        debug_mode = should_pause;
      } else {
          debug_mode = false; // Salir del modo depuración
      }
    }
    else {
      bool isbreakpoint = emscripten_run_script_int("document.app.$data.is_breakpoint");
      debug_mode = emscripten_run_script_int("document.app.$data.execution_mode_run");
      if (isbreakpoint && debug_mode == 0){
        while(should_pause == -1){
          if (force_exit){
            exit(1);
            printf("Antes del reset\n");
            emscripten_run_script("resetenvironment(1)");
            printf("Post reset\n");
          }
          emscripten_sleep(100);
        }
        debug_mode = should_pause;
      }
      first_it = false;
    }
    should_pause = -1;
    return debug_mode;
  }

  unit printdou(uint64_t value){
    double result;
    memcpy(&result, &value, sizeof(double));
    printf("Hexa doble: %016llX \n", value);
    printf("Double 32bits: %f\n", result);
    return 0;
  }
  unit print_fpreg(uint8_t id, uint32_t h_value, uint32_t l_value){
    printf("f%d <- 0x%08X%08X \n", id, h_value,l_value);
    return 0;
  }

  unit print_vreg(uint8_t id, uint32_t a1, uint32_t a2,
                              uint32_t b1, uint32_t b2,
                              uint32_t c1, uint32_t c2,
                              uint32_t d1, uint32_t d2,
                              uint32_t e1, uint32_t e2,
                              uint32_t f1, uint32_t f2,
                              uint32_t g1, uint32_t g2,
                              uint32_t h1, uint32_t h2){
    
    printf("v%d <- 0x%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X\n", id, a1, a2, b1, b2, c1, c2, d1, d2, e1, e2, f1, f2, g1, g2, h1, h2);
    return 0;
  };
  unit print_memory(uint32_t addr, uint32_t valueh, uint32_t valuel){
    printf("mem[0x%08X] <- 0x%08X%08X \n", addr, valueh, valuel);
    return 0;
  }

#elif LOCALSIM

  uint32_t kind_of_cache() {
    return check_cache;
  }

  uint32_t read_int_C(){
    int a;
    scanf("%d", &a);
    return (uint32_t)a;
  }

  uint32_t read_float_C(){
    float a;
    scanf("%f", &a);
    uint32_t result;
    memcpy(&result, &a, sizeof(float));
    return result;
  }

  uint32_t read_double_32C_low(){
    float a;
    scanf("%f", &a);
    uint32_t result;
    memcpy(&result, &a, sizeof(float));
    return result;
  }

  uint32_t read_double_32C_high(){
    float a;
    scanf("%f", &a);
    uint32_t result;
    memcpy(&result, &a, sizeof(float));
    return result;
  }

  uint64_t read_double_64C(){
    double a;
    scanf("%lf", &a);
    uint64_t result;
    memcpy(&result, &a, sizeof(double));
    return result;
  }

  uint8_t read_char_C(){
    char a;
    scanf(" %c", &a);
    uint32_t result;
    memcpy(&result, &a, sizeof(char));
    return result;
  }

  uint8_t read_string_C(uint8_t size_string){
    char a[size_string];
    scanf("%s", a);
    s_keyboard = (char *)malloc(size_string + 1);
    strcpy(s_keyboard, a); 
    return (uint8_t)a[0];
  }


  void reanudar_ejecucion(int value) {
    return;
  }

  bool is_machine_exec(void){

    return (sudo == 1 ? true: false);
  }

  uint32_t get_entry(int a) {

    uint32_t default_entry = (zxlen_val == 32) ? 0x80000000u : 0x00000000u;
    // if (is_32bit_model())
    printf("Default entry: %08X \n", default_entry);
    // default instruction 00028293 es lo mismo que t0 = t0 + 0, los 12 bits mas significativos son el imm 
    uint32_t aux = default_entry;
    if (creator_entry != aux)
      aux = creator_entry;

    printf("Entrada del programa %08X \n", aux);
    
    if(zxlen_val == 32){
      
      uint32_t result = aux - default_entry;
  
      if (result >= 0x1000u && a == 0){ // Redefinimos el lui
        uint32_t new_lui = result / 0x00001000u;
        result = 0x80000u + new_lui;
        result = (result * pow(2, 12)) + 0x000002b7u;
      } else if (result < 0x1000u && a == 0) { // Mantenemos el lui a 0x80000
        result = 0x800002b7u;
      } else if (result >= 0x1000u && a == 1) { // Calculamos el nuevo addi en base al salto del lui
        uint32_t new_addi = result / 0x00001000u;
        new_addi = result - (new_addi * pow(2,12));
        result = (new_addi * pow(2, 20)) + 0x00028293u;
      } else{ // Mantenemos el addi original
        result = (result * pow(2, 20)) + 0x00028293u;
      }

      return result;
    
    } else {

      uint32_t result = aux - default_entry;
      if (result >= 0x1000u && a == 0){ // Redefinimos el lui
        uint32_t new_lui = result / 0x00001000u;
        // result = 0x00000u + new_lui;
        result = (new_lui * pow(2, 12)) + 0x000002b7u;
      } else if (result < 0x1000u && a == 0) { // Mantenemos el lui a 0x0
        result = 0x000002b7u; //0x00000293u;
      } else if (result >= 0x1000u && a == 1) { // Calculamos el nuevo addi en base al salto del lui
        uint32_t new_addi = result / 0x00001000u;
        new_addi = result - (new_addi * pow(2,12));
        result = (new_addi * pow(2, 20)) + 0x00028293u;
      } else{ // Mantenemos el addi original
        result = (result * pow(2, 20)) + 0x00028293u;
      }
      return result;
    }

    
  }

  bool kernel_sim(void){
    
    return (kernel == 1 ? true: false);
  }


  // Función de paso a paso
  bool stepbystep(unit a) {
    if (!debug_mode)
      return false;
    else {
      uint32_t debug;
      scanf("%d", &debug);
      debug_mode = (debug != 0);
      return debug_mode;
    }
  }

  unit printdou(uint64_t value){
    double result;
    memcpy(&result, &value, sizeof(double));
    printf("Hexa doble: %016lX \n", value);
    printf("Double 32bits: %f\n", result);
    return 0;
  }
  unit print_fpreg(uint8_t id, uint32_t h_value, uint32_t l_value){
    printf("f%d <- 0x%08X%08X \n", id, h_value,l_value);
    return 0;
  }

  unit print_vreg(uint8_t id, uint32_t a1, uint32_t a2,
                              uint32_t b1, uint32_t b2,
                              uint32_t c1, uint32_t c2,
                              uint32_t d1, uint32_t d2,
                              uint32_t e1, uint32_t e2,
                              uint32_t f1, uint32_t f2,
                              uint32_t g1, uint32_t g2,
                              uint32_t h1, uint32_t h2){
    
    printf("v%d <- 0x%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X%08X\n", id, a1, a2, b1, b2, c1, c2, d1, d2, e1, e2, f1, f2, g1, g2, h1, h2);
    return 0;
  };
  unit print_memory(uint32_t addr, uint32_t valueh, uint32_t valuel){
    printf("mem[0x%08X] <- 0x%08X%08X \n", addr, valueh, valuel);
    return 0;
  }
#endif