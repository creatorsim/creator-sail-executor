/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Platform-specific definitions, and basic MMIO devices. */

/* Current constraints on this implementation are:
   - it cannot access memory directly, but instead provides definitions for the physical memory model
   - it can access system register state, needed to manipulate interrupt bits
   - it relies on externs to get platform address information and doesn't hardcode them
*/


val print_registers : unit -> unit
register force_debug_divergence : bool = false

function print_registers() = {

  // INT-REGISTERS
  print_endline("INT/CTRL Registers");
  
  // print_reg("PC: " ^ BitStr());
  print_reg("x0/zero: " ^ BitStr(rX(0))  ^ " x1/ra: " ^ BitStr(rX(1))   ^ " x2/sp: " ^ BitStr(rX(2))    ^ " x3/gp: " ^ BitStr(rX(3)));
  print_reg("x4/tp: " ^ BitStr(rX(4))    ^ " x5/t0: " ^ BitStr(rX(5))   ^ " x6/t1: " ^ BitStr(rX(6))    ^ " x7/t2: " ^ BitStr(rX(7)));
  print_reg("x8/fp/s0: " ^ BitStr(rX(8)) ^ " x9/s1: " ^ BitStr(rX(9))   ^ " x10/a0: " ^ BitStr(rX(10))  ^ " x11/a1: " ^ BitStr(rX(11)));
  print_reg("x12/a2: " ^ BitStr(rX(12))  ^ " x13/a3: " ^ BitStr(rX(13)) ^ " x14/a4: " ^ BitStr(rX(14))  ^ " x15/a5: " ^ BitStr(rX(15)));
  print_reg("x16/a6: " ^ BitStr(rX(16))  ^ " x17/a7: " ^ BitStr(rX(17)) ^ " x18/s2: " ^ BitStr(rX(18))  ^ " x19/s3: " ^ BitStr(rX(19)));
  print_reg("x20/s4: " ^ BitStr(rX(20))  ^ " x21/s5: " ^ BitStr(rX(21)) ^ " x22/s6: " ^ BitStr(rX(22))  ^ " x23/s7: " ^ BitStr(rX(23)));
  print_reg("x24/s8: " ^ BitStr(rX(24))  ^ " x25/s9: " ^ BitStr(rX(25)) ^ " x26/s10: " ^ BitStr(rX(26)) ^ " x27/s11: " ^ BitStr(rX(27)));
  print_reg("x28/t3: " ^ BitStr(rX(28))  ^ " x29/t4: " ^ BitStr(rX(29)) ^ " x30/t5: " ^ BitStr(rX(30))  ^ " x31/t6: " ^ BitStr(rX(31)));
  
  if (sys_enable_fdext()) then {
    // FP-REGISTERS
    print_endline("FP Registers");
    
    print_reg("f0/ft0: " ^ BitStr(rF(0))    ^ " f1/ft1: " ^ BitStr(rF(1))   ^ " f2/sp: " ^ BitStr(rF(2))      ^ " f3/ft3: "   ^ BitStr(rF(3)));
    print_reg("f4/ft4: " ^ BitStr(rF(4))    ^ " f5/ft5: " ^ BitStr(rF(5))   ^ " f6/ft6: " ^ BitStr(rF(6))     ^ " f7/ft7: "   ^ BitStr(rF(7)));
    print_reg("f8/fs0: " ^ BitStr(rF(8))    ^ " f9/fs1: " ^ BitStr(rF(9))   ^ " f10/fa0: " ^ BitStr(rF(10))   ^ " f11/fa1: "  ^ BitStr(rF(11)));
    print_reg("f12/fa2: " ^ BitStr(rF(12))  ^ " f13/fa3: " ^ BitStr(rF(13)) ^ " f14/fa4: " ^ BitStr(rF(14))   ^ " f15/fa5: "  ^ BitStr(rF(15)));
    print_reg("f16/fa6: " ^ BitStr(rF(16))  ^ " f17/fa7: " ^ BitStr(rF(17)) ^ " f18/fs2: " ^ BitStr(rF(18))   ^ " f19/fs3: "  ^ BitStr(rF(19)));
    print_reg("f20/fs4: " ^ BitStr(rF(20))  ^ " f21/fs5: " ^ BitStr(rF(21)) ^ " f22/fs6: " ^ BitStr(rF(22))   ^ " f23/fs7: "  ^ BitStr(rF(23)));
    print_reg("f24/fs8: " ^ BitStr(rF(24))  ^ " f25/fs9: " ^ BitStr(rF(25)) ^ " f26/fs10: " ^ BitStr(rF(26))  ^ " f27/fs11: "  ^ BitStr(rF(27)));
    print_reg("f28/ft8: " ^ BitStr(rF(28))  ^ " f29/ft9: " ^ BitStr(rF(29)) ^ " f30/ft10: " ^ BitStr(rF(30))  ^ " f31/ft11: " ^ BitStr(rF(31)));
  };
  if (sys_enable_vext()) then {
    // VEC-REGISTERS
    print_endline("VEC Registers");
    
    print_reg("v0: " ^ BitStr(rV(0)[511..0]));    print_reg(" v1: " ^ BitStr(rV(1)[511..0])); print_reg(" v2: " ^ BitStr(rV(2)[511..0]));    print_reg(" v3: "   ^ BitStr(rV(3)[511..0]));
    print_reg("v4: " ^ BitStr(rV(4)[511..0]));  print_reg(" v5: " ^ BitStr(rV(5)[511..0])); print_reg(" v6: " ^ BitStr(rV(6)[511..0]));    print_reg(" v7: "   ^ BitStr(rV(7)[511..0]));
    print_reg("v8: " ^ BitStr(rV(8)[511..0]));  print_reg(" v9: " ^ BitStr(rV(9)[511..0])); print_reg(" v10: " ^ BitStr(rV(10)[511..0]));    print_reg(" v11: "  ^ BitStr(rV(11)[511..0]));
    print_reg("v12: " ^ BitStr(rV(12)[511..0]));  print_reg(" v13: " ^ BitStr(rV(13)[511..0])); print_reg(" v14: " ^ BitStr(rV(14)[511..0]));    print_reg(" v15: "  ^ BitStr(rV(15)[511..0]));
    print_reg("v16: " ^ BitStr(rV(16)[511..0]));  print_reg(" v17: " ^ BitStr(rV(17)[511..0])); print_reg(" v18: " ^ BitStr(rV(18)[511..0]));    print_reg(" v19: "  ^ BitStr(rV(19)[511..0]));
    print_reg("v20: " ^ BitStr(rV(20)[511..0]));  print_reg(" v21: " ^ BitStr(rV(21)[511..0])); print_reg(" v22: " ^ BitStr(rV(22)[511..0]));    print_reg(" v23: "  ^ BitStr(rV(23)[511..0]));
    print_reg("v24: " ^ BitStr(rV(24)[511..0]));  print_reg(" v25: " ^ BitStr(rV(25)[511..0])); print_reg(" v26: " ^ BitStr(rV(26)[511..0]));    print_reg(" v27: "  ^ BitStr(rV(27)[511..0]));
    print_reg("v28: " ^ BitStr(rV(28)[511..0]));  print_reg(" v29: " ^ BitStr(rV(29)[511..0])); print_reg(" v30: " ^ BitStr(rV(30)[511..0]));    print_reg(" v31: " ^ BitStr(rV(31)[511..0]));
  };
  // CSR-REGISTERS
}


val elf_tohost = {
  ocaml: "Elf_loader.elf_tohost",
  interpreter: "Elf_loader.elf_tohost",
  c: "elf_tohost"
} :  unit -> int

val elf_entry = {
  ocaml: "Elf_loader.elf_entry",
  interpreter: "Elf_loader.elf_entry",
  c: "elf_entry"
} : unit -> int

/* Main memory */
val plat_ram_base = {c: "plat_ram_base", ocaml: "Platform.dram_base", interpreter: "Platform.dram_base", lem: "plat_ram_base"} : unit -> xlenbits
val plat_ram_size = {c: "plat_ram_size", ocaml: "Platform.dram_size", interpreter: "Platform.dram_size", lem: "plat_ram_size"} : unit -> xlenbits

/* whether the MMU should update dirty bits in PTEs */
val plat_enable_dirty_update = {ocaml: "Platform.enable_dirty_update",
                                interpreter: "Platform.enable_dirty_update",
                                c: "plat_enable_dirty_update",
                                lem: "plat_enable_dirty_update"} : unit -> bool

/* whether the platform supports misaligned accesses without trapping to M-mode. if false,
 * misaligned loads/stores are trapped to Machine mode.
 */
val plat_enable_misaligned_access = {ocaml: "Platform.enable_misaligned_access",
                                     interpreter: "Platform.enable_misaligned_access",
                                     c: "plat_enable_misaligned_access",
                                     lem: "plat_enable_misaligned_access"} : unit -> bool

/* whether mtval stores the bits of a faulting instruction on illegal instruction exceptions */
val plat_mtval_has_illegal_inst_bits = {ocaml: "Platform.mtval_has_illegal_inst_bits",
                                        interpreter: "Platform.mtval_has_illegal_inst_bits",
                                        c: "plat_mtval_has_illegal_inst_bits",
                                        lem: "plat_mtval_has_illegal_inst_bits"} : unit -> bool

/* ROM holding reset vector and device-tree DTB */
val plat_rom_base   = {ocaml: "Platform.rom_base", interpreter: "Platform.rom_base", c: "plat_rom_base", lem: "plat_rom_base"} : unit -> xlenbits
val plat_rom_size   = {ocaml: "Platform.rom_size", interpreter: "Platform.rom_size", c: "plat_rom_size", lem: "plat_rom_size"} : unit -> xlenbits

/* Location of clock-interface, which should match with the spec in the DTB */
val plat_clint_base = {ocaml: "Platform.clint_base", interpreter: "Platform.clint_base", c: "plat_clint_base", lem: "plat_clint_base"} : unit -> xlenbits
val plat_clint_size = {ocaml: "Platform.clint_size", interpreter: "Platform.clint_size", c: "plat_clint_size", lem: "plat_clint_size"} : unit -> xlenbits

/* Location of HTIF ports */
val plat_htif_tohost = {ocaml: "Platform.htif_tohost", c: "plat_htif_tohost", lem: "plat_htif_tohost"} : unit -> xlenbits
function plat_htif_tohost () = to_bits(sizeof(xlen), elf_tohost ())
// todo: fromhost

val phys_mem_segments : unit -> list((xlenbits, xlenbits))
function phys_mem_segments() =
  (plat_rom_base (), plat_rom_size ()) ::
  (plat_ram_base (), plat_ram_size ()) ::
  [||]

/* Physical memory map predicates */

function within_phys_mem forall 'n, 'n <= max_mem_access. (addr : xlenbits, width : int('n)) -> bool = {
  /* To avoid overflow issues when physical memory extends to the end
   * of the addressable range, we need to perform address bound checks
   * on unsigned unbounded integers.
   */
  let addr_int     = unsigned(addr);
  let ram_base_int = unsigned(plat_ram_base ());
  let rom_base_int = unsigned(plat_rom_base ());
  let ram_size_int = unsigned(plat_ram_size ());
  let rom_size_int = unsigned(plat_rom_size ());

  /* todo: iterate over segment list */
  if      (  ram_base_int <= addr_int
           & (addr_int + sizeof('n)) <= (ram_base_int + ram_size_int))
  then    true
  else if (  rom_base_int <= addr_int
           & (addr_int + sizeof('n)) <= (rom_base_int + rom_size_int))
  then    true
  else {
    print_platform("within_phys_mem: " ^ BitStr(addr) ^ " not within phys-mem:");
    print_platform("  plat_rom_base: " ^ BitStr(plat_rom_base ()));
    print_platform("  plat_rom_size: " ^ BitStr(plat_rom_size ()));
    print_platform("  plat_ram_base: " ^ BitStr(plat_ram_base ()));
    print_platform("  plat_ram_size: " ^ BitStr(plat_ram_size ()));
    false
  }
}

function within_clint forall 'n, 0 < 'n <= max_mem_access . (addr : xlenbits, width : int('n)) -> bool = {
  /* To avoid overflow issues when physical memory extends to the end
   * of the addressable range, we need to perform address bound checks
   * on unsigned unbounded integers.
   */
  let addr_int       = unsigned(addr);
  let clint_base_int = unsigned(plat_clint_base ());
  let clint_size_int = unsigned(plat_clint_size ());
    clint_base_int <= addr_int
  & (addr_int + sizeof('n)) <= (clint_base_int + clint_size_int)
}

function within_htif_writable forall 'n, 0 < 'n <= max_mem_access . (addr : xlenbits, width : int('n)) -> bool =
    plat_htif_tohost() == addr | (plat_htif_tohost() + 4 == addr & width == 4)

function within_htif_readable forall 'n, 0 < 'n <= max_mem_access . (addr : xlenbits, width : int('n)) -> bool =
    plat_htif_tohost() == addr | (plat_htif_tohost() + 4 == addr & width == 4)

/* CLINT (Core Local Interruptor), based on Spike. */

val plat_insns_per_tick = {ocaml: "Platform.insns_per_tick", interpreter: "Platform.insns_per_tick", c: "plat_insns_per_tick", lem: "plat_insns_per_tick"} : unit -> int

// assumes a single hart, since this typically is a vector of per-hart registers.
register mtimecmp : bits(64)  // memory-mapped internal clint register.

/* CLINT memory-mapped IO */

/* relative address map:
 *
 * 0000 msip hart 0         -- memory-mapped software interrupt
 * 0004 msip hart 1
 * 4000 mtimecmp hart 0 lo  -- memory-mapped timer thresholds
 * 4004 mtimecmp hart 0 hi
 * 4008 mtimecmp hart 1 lo
 * 400c mtimecmp hart 1 hi
 * bff8 mtime lo            -- memory-mapped clocktimer value
 * bffc mtime hi
 */

let MSIP_BASE        : xlenbits = zero_extend(0x00000)
let MTIMECMP_BASE    : xlenbits = zero_extend(0x04000)
let MTIMECMP_BASE_HI : xlenbits = zero_extend(0x04004)
let MTIME_BASE       : xlenbits = zero_extend(0x0bff8)
let MTIME_BASE_HI    : xlenbits = zero_extend(0x0bffc)

val clint_load : forall 'n, 'n > 0. (AccessType(ext_access_type), xlenbits, int('n)) -> MemoryOpResult(bits(8 * 'n))
function clint_load(t, addr, width) = {
  let addr = addr - plat_clint_base ();
  /* FIXME: For now, only allow exact aligned access. */
  if addr == MSIP_BASE & ('n == 8 | 'n == 4)
  then {
    if   get_config_print_platform()
    then print_platform("clint[" ^ BitStr(addr) ^ "] -> " ^ BitStr(mip[MSI]));
    MemValue(sail_zero_extend(mip[MSI], sizeof(8 * 'n)))
  }
  else if addr == MTIMECMP_BASE & ('n == 4)
  then {
    if   get_config_print_platform()
    then print_platform("clint<4>[" ^ BitStr(addr) ^ "] -> " ^ BitStr(mtimecmp[31..0]));
    /* FIXME: Redundant zero_extend currently required by Lem backend */
    MemValue(sail_zero_extend(mtimecmp[31..0], 32))
  }
  else if addr == MTIMECMP_BASE & ('n == 8)
  then {
    if   get_config_print_platform()
    then print_platform("clint<8>[" ^ BitStr(addr) ^ "] -> " ^ BitStr(mtimecmp));
    /* FIXME: Redundant zero_extend currently required by Lem backend */
    MemValue(sail_zero_extend(mtimecmp, 64))
  }
  else if addr == MTIMECMP_BASE_HI & ('n == 4)
  then {
    if   get_config_print_platform()
    then print_platform("clint-hi<4>[" ^ BitStr(addr) ^ "] -> " ^ BitStr(mtimecmp[63..32]));
    /* FIXME: Redundant zero_extend currently required by Lem backend */
    MemValue(sail_zero_extend(mtimecmp[63..32], 32))
  }
  else if addr == MTIME_BASE & ('n == 4)
  then {
    if   get_config_print_platform()
    then print_platform("clint[" ^ BitStr(addr) ^ "] -> " ^ BitStr(mtime));
    MemValue(sail_zero_extend(mtime[31..0], 32))
  }
  else if addr == MTIME_BASE & ('n == 8)
  then {
    if   get_config_print_platform()
    then print_platform("clint[" ^ BitStr(addr) ^ "] -> " ^ BitStr(mtime));
    MemValue(sail_zero_extend(mtime, 64))
  }
  else if addr == MTIME_BASE_HI & ('n == 4)
  then {
    if   get_config_print_platform()
    then print_platform("clint[" ^ BitStr(addr) ^ "] -> " ^ BitStr(mtime));
    MemValue(sail_zero_extend(mtime[63..32], 32))
  }
  else {
    if   get_config_print_platform()
    then print_platform("clint[" ^ BitStr(addr) ^ "] -> <not-mapped>");
    match t {
      Execute()  => MemException(E_Fetch_Access_Fault()),
      Read(Data) => MemException(E_Load_Access_Fault()),
      _          => MemException(E_SAMO_Access_Fault())
    }
  }
}

function clint_dispatch() -> unit = {
  if   get_config_print_platform()
  then {print_platform("clint::tick mtime <- " ^ BitStr(mtime));
        if (unsigned(mtime) % 10 == 0 & unsigned(mtime) > 0) then{force_debug_divergence = true;};
  };
  mip[MTI] = 0b0;
  if mtimecmp <=_u mtime then {
    if   get_config_print_platform()
    then print_platform(" clint timer pending at mtime " ^ BitStr(mtime));
    mip[MTI] = 0b1
  }
}

/* The rreg effect is due to checking mtime. */
val clint_store: forall 'n, 'n > 0. (xlenbits, int('n), bits(8 * 'n)) -> MemoryOpResult(bool)
function clint_store(addr, width, data) = {
  let addr = addr - plat_clint_base ();
  if addr == MSIP_BASE & ('n == 8 | 'n == 4) then {
    if   get_config_print_platform()
    then print_platform("clint[" ^ BitStr(addr) ^ "] <- " ^ BitStr(data) ^ " (mip.MSI <- " ^ BitStr(data[0]) ^ ")");
    mip[MSI] = [data[0]];
    clint_dispatch();
    MemValue(true)
  } else if addr == MTIMECMP_BASE & 'n == 8 then {
    if   get_config_print_platform()
    then print_platform("clint<8>[" ^ BitStr(addr) ^ "] <- " ^ BitStr(data) ^ " (mtimecmp)");
    mtimecmp = sail_zero_extend(data, 64); /* FIXME: Redundant zero_extend currently required by Lem backend */
    clint_dispatch();
    MemValue(true)
  } else if addr == MTIMECMP_BASE & 'n == 4 then {
    if   get_config_print_platform()
    then print_platform("clint<4>[" ^ BitStr(addr) ^ "] <- " ^ BitStr(data) ^ " (mtimecmp)");
    mtimecmp = vector_update_subrange(mtimecmp, 31, 0, sail_zero_extend(data, 32));  /* FIXME: Redundant zero_extend currently required by Lem backend */
    clint_dispatch();
    MemValue(true)
  } else if addr == MTIMECMP_BASE_HI & 'n == 4 then {
    if   get_config_print_platform()
    then print_platform("clint<4>[" ^ BitStr(addr) ^ "] <- " ^ BitStr(data) ^ " (mtimecmp)");
    mtimecmp = vector_update_subrange(mtimecmp, 63, 32, sail_zero_extend(data, 32)); /* FIXME: Redundant zero_extend currently required by Lem backend */
    clint_dispatch();
    MemValue(true)
  } else {
    if   get_config_print_platform()
    then print_platform("clint[" ^ BitStr(addr) ^ "] <- " ^ BitStr(data) ^ " (<unmapped>)");
    MemException(E_SAMO_Access_Fault())
  }
}

val tick_clock : unit -> unit
function tick_clock() = {
  if   mcountinhibit[CY] == 0b0
  then mcycle = mcycle + 1;

  mtime  = mtime  + 1;
  clint_dispatch()
}

/* Basic terminal character I/O. */

val plat_term_write = {ocaml: "Platform.term_write", c: "plat_term_write", lem: "plat_term_write"} : bits(8) -> unit
val plat_term_read  = {ocaml: "Platform.term_read",  c: "plat_term_read", lem: "plat_term_read"}  : unit -> bits(8)

/* Spike's HTIF device interface, which multiplexes the above MMIO devices. */

bitfield htif_cmd : bits(64) = {
  device  : 63 .. 56,
  cmd     : 55 .. 48,
  payload : 47 .. 0
}

register htif_tohost : bits(64)
register htif_done   : bool
register htif_exit_code : bits(64)

/* Applications sometimes write the lower 32-bit payload bytes without
   writing the control bytes; this is seen in the riscv-tests suite.
   However, processing the payload bytes too early could miss a
   subsequent write to the control bytes.  As a workaround, if the
   payload is written a few times with the same value, without an
   intervening write to the control bytes, we process the whole htif
   command anyway.  */

register htif_cmd_write : bit
register htif_payload_writes : bits(4)

/* Once a htif command has been processed, the port is reset. */
function reset_htif () -> unit = {
  htif_cmd_write = bitzero;
  htif_payload_writes = 0x0;
  htif_tohost = zero_extend(0b0);
}

/* Since the htif tohost port is only available at a single address,
 * we'll assume here that physical memory model has correctly
 * dispatched the address.
 */

val htif_load : forall 'n, 'n > 0. (AccessType(ext_access_type), xlenbits, int('n)) -> MemoryOpResult(bits(8 * 'n))
function htif_load(t, paddr, width) = {
  if   get_config_print_platform()
  then print_platform("htif[" ^ BitStr(paddr) ^ "] -> " ^ BitStr(htif_tohost));
  /* FIXME: For now, only allow the expected access widths. */
  if      width == 8 & (paddr == plat_htif_tohost())
  then    MemValue(sail_zero_extend(htif_tohost, 64))         /* FIXME: Redundant zero_extend currently required by Lem backend */
  else if width == 4 & paddr == plat_htif_tohost()
  then    MemValue(sail_zero_extend(htif_tohost[31..0], 32))  /* FIXME: Redundant zero_extend currently required by Lem backend */
  else if width == 4 & paddr == plat_htif_tohost() + 4
  then    MemValue(sail_zero_extend(htif_tohost[63..32], 32)) /* FIXME: Redundant zero_extend currently required by Lem backend */
  else match t {
    Execute()  => MemException(E_Fetch_Access_Fault()),
    Read(Data) => MemException(E_Load_Access_Fault()),
    _          => MemException(E_SAMO_Access_Fault())
  }
}

/* The rreg,wreg effects are an artifact of using 'register' to implement device state. */
val htif_store: forall 'n, 0 < 'n <= 8. (xlenbits, int('n), bits(8 * 'n)) -> MemoryOpResult(bool)
function htif_store(paddr, width, data) = {
  if   get_config_print_platform()
  then print_platform("htif[" ^ BitStr(paddr) ^ "] <- " ^ BitStr(data));
  /* Store the written value so that we can ack it later. */
  if      width == 8
  then    { htif_cmd_write = bitone;
            htif_payload_writes = htif_payload_writes + 1;
            htif_tohost = zero_extend(data) }
  else if width == 4 & paddr == plat_htif_tohost()
  then    { if   data == htif_tohost[31 .. 0]
            then htif_payload_writes = htif_payload_writes + 1
            else htif_payload_writes = 0x1;
            htif_tohost = vector_update_subrange(htif_tohost, 31, 0, data) }
  else if width == 4 & paddr == plat_htif_tohost() + 4
  then    { if   data[15 .. 0] == htif_tohost[47 .. 32]
            then htif_payload_writes = htif_payload_writes + 1
            else htif_payload_writes = 0x1;
            htif_cmd_write = bitone;
            htif_tohost = vector_update_subrange(htif_tohost, 63, 32, data) }
  /* unaligned command writes are not supported and will not be detected */
  else    { htif_tohost = zero_extend(data) };

  /* Execute if there were repeated writes of the same payload without
   * a cmd (e.g. in riscv-tests), or we have a complete htif command.
   */
  if   (((htif_cmd_write == bitone) & (unsigned(htif_payload_writes) > 0))
        | (unsigned(htif_payload_writes) > 2))
  then {
    let cmd = Mk_htif_cmd(htif_tohost);
    match cmd[device] {
      0x00 => { /* syscall-proxy */
        if   get_config_print_platform()
        then print_platform("htif-syscall-proxy cmd: " ^ BitStr(cmd[payload]));
        if   cmd[payload][0] == bitone
        then {
             htif_done = true;
             htif_exit_code = (sail_zero_extend(cmd[payload], 64) >> 1)
        }
        else ()
      },
      0x01 => { /* terminal */
        if   get_config_print_platform()
        then print_platform("htif-term cmd: " ^ BitStr(cmd[payload]));
        match cmd[cmd] {
          0x00 => /* TODO: terminal input handling */ (),
          0x01 => plat_term_write(cmd[payload][7..0]),
          c    => print("Unknown term cmd: " ^ BitStr(c))
        };
        /* reset to ack */
        reset_htif()
      },
      d => print("htif-???? cmd: " ^ BitStr(data))
    }
  };
  print_registers();
  MemValue(true)
}

val htif_tick : unit -> unit
function htif_tick() = {
  if   get_config_print_platform()
  then print_platform("htif::tick " ^ BitStr(htif_tohost));
  htif_tohost = htif_tohost /* prevent this function being optimized out */
}

/* Top-level MMIO dispatch */
$ifndef RVFI_DII
function within_mmio_readable forall 'n, 0 < 'n <= max_mem_access . (addr : xlenbits, width : int('n)) -> bool =
  within_clint(addr, width) | (within_htif_readable(addr, width) & 1 <= 'n)
$else
function within_mmio_readable forall 'n, 0 < 'n <= max_mem_access . (addr : xlenbits, width : int('n)) -> bool = false
$endif

$ifndef RVFI_DII
function within_mmio_writable forall 'n, 0 < 'n <= max_mem_access . (addr : xlenbits, width : int('n)) -> bool =
  within_clint(addr, width) | (within_htif_writable(addr, width) & 'n <= 8)
$else
function within_mmio_writable forall 'n, 0 < 'n <= max_mem_access . (addr : xlenbits, width : int('n)) -> bool = false
$endif

function mmio_read forall 'n, 0 < 'n <= max_mem_access . (t : AccessType(ext_access_type), paddr : xlenbits, width : int('n)) -> MemoryOpResult(bits(8 * 'n)) =
  if   within_clint(paddr, width)
  then clint_load(t, paddr, width)
  else if within_htif_readable(paddr, width) & (1 <= 'n)
  then htif_load(t, paddr, width)
  else match t {
    Execute()  => MemException(E_Fetch_Access_Fault()),
    Read(Data) => MemException(E_Load_Access_Fault()),
    _          => MemException(E_SAMO_Access_Fault())
  }

function mmio_write forall 'n, 0 <'n <= max_mem_access . (paddr : xlenbits, width : int('n), data: bits(8 * 'n)) -> MemoryOpResult(bool) =
  if   within_clint(paddr, width)
  then clint_store(paddr, width, data)
  else if within_htif_writable(paddr, width) & 'n <= 8
  then htif_store(paddr, width, data)
  else MemException(E_SAMO_Access_Fault())

/* Platform initialization and ticking. */

function init_platform() -> unit = {
  htif_tohost = zero_extend(0b0);
  htif_done   = false;
  htif_exit_code = zero_extend(0b0);
  htif_cmd_write = bitzero;
  htif_payload_writes = zero_extend(0b0);
}

function tick_platform() -> unit = {
  htif_tick();
}

/* Platform-specific handling of instruction faults */

function handle_illegal() -> unit = {
  let info = if plat_mtval_has_illegal_inst_bits ()
             then Some(instbits)
             else None();
  let t : sync_exception = struct { trap    = E_Illegal_Instr(),
                                    excinfo = info,
                                    ext     = None() };
  set_next_pc(exception_handler(cur_privilege, CTL_TRAP(t), PC))
}

/* Platform-specific wait-for-interrupt */

function platform_wfi() -> unit = {
  /* speed execution by getting the timer to fire at the next instruction,
   * since we currently don't have any other devices raising interrupts.
   */
  if mtime <_u mtimecmp then {
    mtime  = mtimecmp;
    mcycle = mtimecmp;
  }
}
