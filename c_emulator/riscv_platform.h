#pragma once
#include "sail.h"

bool sys_enable_rvc(unit);
bool sys_enable_next(unit);
bool sys_enable_fdext(unit);
bool sys_enable_svinval(unit);
bool sys_enable_zcb(unit);
bool sys_enable_zfinx(unit);
bool sys_enable_writable_misa(unit);
bool sys_enable_writable_fiom(unit);
bool sys_enable_vext(unit);
bool sys_enable_bext(unit);

uint64_t sys_pmp_count(unit);
uint64_t sys_pmp_grain(unit);

bool plat_enable_dirty_update(unit);
bool plat_enable_misaligned_access(unit);
bool plat_mtval_has_illegal_inst_bits(unit);

mach_bits plat_ram_base(unit);
mach_bits plat_ram_size(unit);
bool within_phys_mem(mach_bits, sail_int);

mach_bits plat_rom_base(unit);
mach_bits plat_rom_size(unit);

// Provides entropy for the scalar cryptography extension.
mach_bits plat_get_16_random_bits(unit);

mach_bits plat_clint_base(unit);
mach_bits plat_clint_size(unit);

bool speculate_conditional(unit);
unit load_reservation(mach_bits);
bool match_reservation(mach_bits);
unit cancel_reservation(unit);

void plat_insns_per_tick(sail_int *rop, unit);

unit plat_term_write(mach_bits);
mach_bits plat_htif_tohost(unit);

unit memea(mach_bits, sail_int);
unit print_test_C(mach_bits argument, bool rt);
unit print_string_C(char* message);
unit send_error_c(unit);
uint8_t read_s(uint32_t);
uint32_t rand_num(uint16_t);
uint32_t crep(unit);
uint32_t which_cache_levels(unit);
uint32_t cache_sizes(uint8_t);
uint32_t cache_line_size(uint8_t);
uint32_t set_config(uint8_t);
uint32_t get_size_field(uint8_t, uint8_t);

#ifdef WEBSIM
    uint8_t isDirect(unit);
    uint32_t kind_of_cache(unit);
    void send_int_to_C(int);
    void send_float_to_C(float);
    void send_double_to_C(double);
    void send_char_to_C(char);
    void send_string_to_C(char*);
    uint32_t read_int_C(unit);
    uint32_t read_float_C(unit);
    uint32_t read_double_32C_low(unit);
    uint32_t read_double_32C_high(unit);
    uint64_t read_double_64C(unit);
    uint8_t read_char_C(unit);
    uint8_t read_string_C(uint8_t);
    void reanudar_ejecucion(int);
    bool is_machine_exec();
    uint32_t get_entry(int);
    bool kernel_sim();
    bool stepbystep(unit);
    unit printdou(uint64_t);
    unit print_fpreg(uint8_t, uint32_t, uint32_t);
    unit print_vreg(uint8_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
    unit print_memory(uint32_t, uint32_t, uint32_t);
#elif LOCALSIM
    // void send_int_to_C(int);
    // void send_float_to_C(float);
    // void send_double_to_C(double);
    // void send_char_to_C(char);
    // void send_string_to_C(char*);
    uint32_t kind_of_cache();
    uint32_t read_int_C();
    uint32_t read_float_C();
    uint32_t read_double_32C_low();
    uint32_t read_double_32C_high();
    uint64_t read_double_64C();
    uint8_t read_char_C();
    uint8_t read_string_C(uint8_t);
    void reanudar_ejecucion(int);
    bool is_machine_exec();
    uint32_t get_entry(int);
    bool kernel_sim();
    bool stepbystep(unit);
    unit printdou(uint64_t);
    unit print_fpreg(uint8_t, uint32_t, uint32_t);
    unit print_vreg(uint8_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t, uint32_t);
    unit print_memory(uint32_t, uint32_t, uint32_t);

#endif