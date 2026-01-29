/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Physical memory model.
 *
 * This assumes that the platform memory map has been defined, so that accesses
 * to MMIO regions can be dispatched.
 *
 * The implementation below supports the reading and writing of memory
 * metadata in addition to raw memory data.
 *
 * The external API for this module is composed of three central functions
 *
 *   mem_read_priv_meta
 *   mem_write_ea
 *   mem_write_value_priv_meta
 *
 * and some special cases which partially apply these functions:
 *
 *   mem_read_priv - strips metadata from reads
 *   mem_read_meta - uses effectivePrivilege
 *   mem_read      - both of the above partial applications
 *
 *   mem_write_value_meta - uses effectivePrivilege
 *   mem_write_value_priv - uses a default value for metadata
 *   mem_write_value      - both of the above partial applications
 *
 * The internal implementation first performs a PMP check (if PMP is
 * enabled), and then dispatches to MMIO regions or physical memory as
 * per the platform memory map.
 */

 struct cache_params = {
  L1 : bits(32),
  L1_I : bits(32),
  L1_D : bits(32),
  L2 : bits(32),
  L2_I : bits(32),
  L2_D : bits(32),
 }

val print_mem_C = pure {c: "print_memory"} : (xlenbits, xlenbits, xlenbits) -> unit
val kind_of_cache = { c: "kind_of_cache" } : unit -> bits(32)
val randomindex = { c: "rand_num" } : bits(32) -> bits(32)
val crep = { c: "crep" } : unit -> bits(32)
val cache_levels = { c: "which_cache_levels" } : unit -> bits(32)
val cache_sizes = { c: "cache_sizes" } : bits(8) -> bits(32) // (bits(32), bits(32), bits(32), bits(32), bits(32), bits(32))
val lb_sizes = { c: "cache_line_size" } : bits(8) -> bits(32)
val set_config = { c: "set_config" } : bits(8) -> bits(32)
val address_c = { c: "get_size_field" } : (bits(8), bits(8)) -> bits(32)
val locpol = { c: "isDirect" } : unit -> bits(8)

let max_cache_lines : int = 4096 // Max cache lines
type h_maxcl : Int = 2048
type maxcl : Int = 4096

// If it is non attached, the lines must be a half of the maximum number of lines of a cache
register L1_I_cache_lines : int = max_cache_lines / 2
register L1_D_cache_lines : int = max_cache_lines / 2
register L1_cache_lines : int = max_cache_lines
register L2_I_cache_lines : int = max_cache_lines / 2
register L2_D_cache_lines : int = max_cache_lines / 2
register L2_cache_lines : int = max_cache_lines
register cache_block_size : int
register DirectLocation : int = 0

register level_types : int = unsigned(cache_levels())

enum cache_mem_type = {
  Cache_data,
  Cache_inst,
  Cache_all,
}

enum cache_level = {
  LL1,
  LL2,
}

$ifdef _RV32S

struct cache_block_L1 = {
  // Cache_data_block    : bits(128),
  // Cache_tag           : bits(24),
  // Cache_index         : bits(12),
  // Cache_offset        : bits(4),
  Cache_addr          : bits(32),
  Cache_control_bits  : bits(5),
}

struct cache_block_L2 = {
  // Cache_data_block    : bits(128),
  // Cache_tag           : bits(24),
  // Cache_index         : bits(12),
  // Cache_offset        : bits(4),
  Cache_addr          : bits(32),
  Cache_control_bits  : bits(5),
}

$endif _RV32S

$ifdef _RV64S

  struct cache_block_L1 = {
    // Cache_data_block    : bits(128),
    // Cache_tag           : bits(40),
    // Cache_index         : bits(20),
    // Cache_offset        : bits(4),
    Cache_addr          : bits(64),
    Cache_control_bits  : bits(5),
  }

  struct cache_block_L2 = {
    // Cache_data_block    : bits(128),
    // Cache_tag           : bits(40),
    // Cache_index         : bits(20),
    // Cache_offset        : bits(4),
    Cache_addr          : bits(64),
    Cache_control_bits  : bits(5),
  }

$endif _RV64S

enum cache_rep_policy = {
  // Cache_Rep_Beladys,
  Cache_Rep_RR,
  Cache_Rep_Simple_FIFO,
  // Cache_Rep_Simple_LIFO,
  // Cache_Rep_Simple_FILO,
  // Cache_Rep_Simple_SIEVE,
  // Cache_Rep_Simple_LRU,
  // Cache_Rep_Simple_MRU,
  // Cache_Rep_Simple_SLRU,
  NULL
}

struct cache_info_L1_t = {
  cache_type : cache_mem_type,
  busy_lines : bits(10),
  repl_lines : bits(10),
  num_set : int,
  num_lines_set: bits(32),
  repl_lines : bits(11),
  tag : int,
  index : int,
  offset : int,
  rep_pol    : cache_rep_policy,
  mcs : int, // Maximum cache size
  mcb : int  // Maximum cache block size
}

struct cache_info_L1 = {
  cache_type : cache_mem_type,
  busy_lines : bits(11),
  num_set : int,
  num_lines_set: bits(32),
  repl_lines : bits(11),
  tag : int,
  index : int,
  offset : int,
  rep_pol    : cache_rep_policy,
  mcs : int, // Maximum cache size
  mcb : int  // Maximum cache block size
}

struct cache_info_L2 = {
  cache_type : cache_mem_type,
  busy_lines : bits(11),
  num_set : int,
  num_lines_set: bits(32),
  tag : int,
  index : int,
  offset : int,
  repl_lines : bits(11),
  rep_pol    : cache_rep_policy,
  mcs : int, // Maximum cache size
  mcb : int  // Maximum cache block size
}

struct cache_mem_L1_t = {
  mem_L1        : vector(h_maxcl, dec, cache_block_L1),
  info          : cache_info_L1_t,
}

struct cache_mem_L1 = {
  mem_L1        : vector(maxcl, dec, cache_block_L1),
  info          : cache_info_L1,
}

struct cache_mem_L2 = {
  mem_L2        : vector(maxcl, dec, cache_block_L2),
  info          : cache_info_L2,
}

register L2 : cache_mem_L2
register L1 : cache_mem_L1
register L1_D : cache_mem_L1_t
register L1_I : cache_mem_L1_t
register L2_D : cache_mem_L1_t
register L2_I : cache_mem_L1_t
register kind_c : int


// Almacenamiento de los aciertos y los fallos para sacar estadisticas

register hits_L1 : int // Se reutiliza para el caso de (I+D) Instrucciones
register miss_L1 : int // Se reutiliza para el caso de (I+D) Instrucciones
register hits_L1_D : int
register miss_L1_D : int
register hits_L2 : int
register miss_L2 : int



function is_aligned_addr forall 'n. (addr : xlenbits, width : int('n)) -> bool =
  unsigned(addr) % width == 0

function read_kind_of_flags (aq : bool, rl : bool, res : bool) -> option(read_kind) =
  match (aq, rl, res) {
    (false, false, false) => Some(Read_plain),
    (true, false, false)  => Some(Read_RISCV_acquire),
    (true, true, false)   => Some(Read_RISCV_strong_acquire),
    (false, false, true)  => Some(Read_RISCV_reserved),
    (true, false, true)   => Some(Read_RISCV_reserved_acquire),
    (true, true, true)    => Some(Read_RISCV_reserved_strong_acquire),
    (false, true, false)  => None(), /* should these be instead throwing error_not_implemented as below? */
    (false, true, true)   => None()
  }

function write_kind_of_flags (aq : bool, rl : bool, con : bool) -> write_kind =
  match (aq, rl, con) {
    (false, false, false) => Write_plain,
    (false, true,  false) => Write_RISCV_release,
    (false, false, true)  => Write_RISCV_conditional,
    (false, true , true)  => Write_RISCV_conditional_release,
    (true,  true,  false) => Write_RISCV_strong_release,
    (true,  true , true)  => Write_RISCV_conditional_strong_release,
    // throw an illegal instruction here?
    (true,  false, false) => throw(Error_not_implemented("store.aq")),
    (true,  false, true)  => throw(Error_not_implemented("sc.aq"))
  }

// only used for actual memory regions, to avoid MMIO effects
function phys_mem_read forall 'n, 0 < 'n <= max_mem_access . (t : AccessType(ext_access_type), paddr : xlenbits, width : int('n), aq : bool, rl: bool, res : bool, meta : bool) -> MemoryOpResult((bits(8 * 'n), mem_meta)) = {
  let result = (match read_kind_of_flags(aq, rl, res) {
    Some(rk) => Some(read_ram(rk, paddr, width, meta)),
    None()   => None()
  }) : option((bits(8 * 'n), mem_meta));
  match (t, result) {
    (Execute(),  None()) => MemException(E_Fetch_Access_Fault()),
    (Read(Data), None()) => MemException(E_Load_Access_Fault()),
    (_,          None()) => MemException(E_SAMO_Access_Fault()),
    (_,      Some(v, m)) => { if   get_config_print_mem()
                              then {
                                // if (width == 8) then print_reg("Lectura alta: " ^ BitStr(v[63..32]));
                                // //print_reg("Lectura baja: " ^ BitStr(v[31..0]));

                                print_mem("mem[" ^ to_str(t) ^ "," ^ BitStr(paddr) ^ "] -> " ^ BitStr(v));
                                };
                              MemValue(v, m) }
  }
}

// Check if access is permitted according to PMPs and PMAs.
val phys_access_check : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), Privilege, xlenbits, int('n)) -> option(ExceptionType)
function phys_access_check (t, p, paddr, width) = {
  let pmpError : option(ExceptionType) = if sys_pmp_count() == 0 then None() else pmpCheck(paddr, width, t, p);
  // TODO: Also check PMAs and select the highest priority fault.
  pmpError
}

/* dispatches to MMIO regions or physical memory regions depending on physical memory map */
function checked_mem_read forall 'n, 0 < 'n <= max_mem_access . (
  t : AccessType(ext_access_type),
  priv : Privilege,
  paddr : xlenbits,
  width : int('n),
  aq : bool,
  rl : bool,
  res: bool,
  meta : bool,
) -> MemoryOpResult((bits(8 * 'n), mem_meta)) =
  match phys_access_check(t, priv, paddr, width) {
    Some(e) => MemException(e),
    None() => {
      if   within_mmio_readable(paddr, width)
      then MemoryOpResult_add_meta(mmio_read(t, paddr, width), default_meta)
      else if within_phys_mem(paddr, width)
      then match ext_check_phys_mem_read(t, paddr, width, aq, rl, res, meta) {
        Ext_PhysAddr_OK()     => phys_mem_read(t, paddr, width, aq, rl, res, meta),
        Ext_PhysAddr_Error(e) => MemException(e)
      } else match t {
        Execute()  => MemException(E_Fetch_Access_Fault()),
        Read(Data) => MemException(E_Load_Access_Fault()),
        _          => MemException(E_SAMO_Access_Fault())
      }
    }
  }

/* Atomic accesses can be done to MMIO regions, e.g. in kernel access to device registers. */

$ifdef RVFI_DII
val rvfi_read : forall 'n, 'n > 0. (xlenbits, int('n), MemoryOpResult((bits(8 * 'n), mem_meta))) -> unit
function rvfi_read (addr, width, result) = {
  rvfi_mem_data[rvfi_mem_addr] = zero_extend(addr);
  rvfi_mem_data_present = true;
  match result {
    /* TODO: report tag bit for capability writes and extend mask by one bit. */
    MemValue(v, _) => if width <= 16
                       then { rvfi_mem_data[rvfi_mem_rdata] = sail_zero_extend(v, 256);
                              rvfi_mem_data[rvfi_mem_rmask] = rvfi_encode_width_mask(width) }
                       else { internal_error(__FILE__, __LINE__, "Expected at most 16 bytes here!") },
    MemException(_) => ()
  };
}
$else
val rvfi_read : forall 'n, 'n > 0. (xlenbits, int('n), MemoryOpResult((bits(8 * 'n), mem_meta))) -> unit
function rvfi_read (addr, width, result) = ()
$endif

val mem_read      : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), xlenbits, int('n), bool, bool, bool)       -> MemoryOpResult(bits(8 * 'n))
val mem_read_priv : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), Privilege, xlenbits, int('n), bool, bool, bool)       -> MemoryOpResult(bits(8 * 'n))
val mem_read_meta : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), xlenbits, int('n), bool, bool, bool, bool) -> MemoryOpResult((bits(8 * 'n), mem_meta))
val mem_read_priv_meta : forall 'n, 0 < 'n <= max_mem_access . (AccessType(ext_access_type), Privilege, xlenbits, int('n), bool, bool, bool, bool) -> MemoryOpResult((bits(8 * 'n), mem_meta))

/* The most generic memory read operation */
function mem_read_priv_meta (typ, priv, paddr, width, aq, rl, res, meta) = {
  let result : MemoryOpResult((bits(8 * 'n), mem_meta)) =
    if (aq | res) & not(is_aligned_addr(paddr, width))
    then MemException(E_Load_Addr_Align())
    else match (aq, rl, res) {
      (false, true,  false) => throw(Error_not_implemented("load.rl")),
      (false, true,  true)  => throw(Error_not_implemented("lr.rl")),
      (_, _, _)             => checked_mem_read(typ, priv, paddr, width, aq, rl, res, meta)
    };
  rvfi_read(paddr, width, result);
  result
}

function mem_read_meta (typ, paddr, width, aq, rl, res, meta) =
  mem_read_priv_meta(typ, effectivePrivilege(typ, mstatus, cur_privilege), paddr, width, aq, rl, res, meta)

/* Specialized mem_read_meta that drops the metadata */
function mem_read_priv (typ, priv, paddr, width, aq, rl, res) =
  MemoryOpResult_drop_meta(mem_read_priv_meta(typ, priv, paddr, width, aq, rl, res, false))

/* Specialized mem_read_priv that operates at the default effective privilege */
function mem_read (typ, paddr, width, aq, rel, res) =
  mem_read_priv(typ, effectivePrivilege(typ, mstatus, cur_privilege), paddr, width, aq, rel, res)

val mem_write_ea : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bool, bool, bool) -> MemoryOpResult(unit)
function mem_write_ea (addr, width, aq, rl, con) =
  if (rl | con) & not(is_aligned_addr(addr, width))
  then MemException(E_SAMO_Addr_Align())
  else MemValue(write_ram_ea(write_kind_of_flags(aq, rl, con), addr, width))

$ifdef RVFI_DII
val rvfi_write : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bits(8 * 'n), mem_meta, MemoryOpResult(bool)) -> unit
function rvfi_write (addr, width, value, meta, result) = {
  rvfi_mem_data[rvfi_mem_addr] = zero_extend(addr);
  rvfi_mem_data_present = true;
  match result {
    /* Log only the memory address (without the value) if the write fails. */
    MemValue(_) => if width <= 16 then {
        /* TODO: report tag bit for capability writes and extend mask by one bit. */
        rvfi_mem_data[rvfi_mem_wdata] = sail_zero_extend(value,256);
        rvfi_mem_data[rvfi_mem_wmask] = rvfi_encode_width_mask(width);
      } else {
        internal_error(__FILE__, __LINE__, "Expected at most 16 bytes here!");
      },
    MemException(_) => ()
  }
}
$else
val rvfi_write : forall 'n, 'n > 0. (xlenbits, int('n), bits(8 * 'n), mem_meta, MemoryOpResult(bool)) -> unit
function rvfi_write (addr, width, value, meta, result) = ()
$endif


$ifdef _RV32S
  // only used for actual memory regions, to avoid MMIO effects
  function phys_mem_write forall 'n, 0 < 'n <= max_mem_access . (wk : write_kind, paddr : xlenbits, width : int('n), data : bits(8 * 'n), meta : mem_meta) -> MemoryOpResult(bool) = {
    var result : MemoryOpResult(bool) = MemValue(true);
    if (sizeof(xlen) == 32 & width == 8) then {
      let lo_result = MemValue(write_ram(wk, paddr, 4, double_to_store.low_p, meta));
      let hi_result = MemValue(write_ram(wk, paddr + 4, 4, double_to_store.high_p, meta));
      result = MemValue(true);
    }
    else{
      result = MemValue(write_ram(wk, paddr, width, data, meta));
    };
    if   get_config_print_mem()
    then {
      if ((sizeof(xlen) == 32) & width == 8) then {
        print_mem_C(paddr, double_to_store.high_p,  double_to_store.low_p);
      }else {
        print_reg("mem[" ^ BitStr(paddr) ^ "] <- " ^ BitStr(data));
        // print_mem("mem[" ^ BitStr(paddr) ^ "] <- " ^ BitStr(data));
      };
      
    };
    result
  }

$else

  // only used for actual memory regions, to avoid MMIO effects
  function phys_mem_write forall 'n, 0 < 'n <= max_mem_access . (wk : write_kind, paddr : xlenbits, width : int('n), data : bits(8 * 'n), meta : mem_meta) -> MemoryOpResult(bool) = {
    var result : MemoryOpResult(bool) = MemValue(true);
    // if (sizeof(xlen) == 32 & width == 8) then {
    //   print_reg("Escribimos en memoria");
    //   let lo_result = MemValue(write_ram(wk, paddr, 4, double_to_store.low_p, meta));
    //   let hi_result = MemValue(write_ram(wk, paddr + 4, 4, double_to_store.high_p, meta));
    //   result = MemValue(true);
    // }
    // else{
      result = MemValue(write_ram(wk, paddr, width, data, meta));
    // };
    if   get_config_print_mem()
    then {
      // if ((sizeof(xlen) == 32) ) then {
      //   if ( width == 8 ) then {
      //     print_mem_C(paddr, double_to_store.high_p,  double_to_store.low_p);
      //   };
      // }
      // else {
        print_mem("mem[" ^ BitStr(paddr) ^ "] <- " ^ BitStr(data));
      // }
    };
    result
  }

$endif


/* dispatches to MMIO regions or physical memory regions depending on physical memory map */
function checked_mem_write forall 'n, 0 < 'n <= max_mem_access . (
  paddr : xlenbits,
  width : int('n),
  data: bits(8 * 'n),
  typ : AccessType(ext_access_type),
  priv : Privilege,
  meta: mem_meta,
  aq : bool,
  rl : bool,
  con : bool,
) -> MemoryOpResult(bool) =
  match phys_access_check(typ, priv, paddr, width) {
    Some(e) => MemException(e),
    None() => {
      if   within_mmio_writable(paddr, width)
      then mmio_write(paddr, width, data)
      else if within_phys_mem(paddr, width)
      then {
        let wk = write_kind_of_flags(aq, rl, con);
        match ext_check_phys_mem_write (wk, paddr, width, data, meta) {
          Ext_PhysAddr_OK() => phys_mem_write(wk, paddr, width, data, meta),
          Ext_PhysAddr_Error(e)  => MemException(e),
        }
      } else MemException(E_SAMO_Access_Fault())
    }
  }

/* Atomic accesses can be done to MMIO regions, e.g. in kernel access to device registers. */

/* Memory write with an explicit metadata value.  Metadata writes are
 * currently assumed to have the same alignment constraints as their
 * data.
 * NOTE: The wreg effect is due to MMIO, the rreg is due to checking mtime.
 */
val mem_write_value_priv_meta : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bits(8 * 'n), AccessType(ext_access_type), Privilege, mem_meta, bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value_priv_meta (paddr, width, value, typ, priv, meta, aq, rl, con) = {
  if (rl | con) & not(is_aligned_addr(paddr, width))
  then MemException(E_SAMO_Addr_Align())
  else {
    let result = checked_mem_write(paddr, width, value, typ, priv, meta, aq, rl, con);
    rvfi_write(paddr, width, value, meta, result);
    result
  }
}

/* Memory write with explicit Privilege, implicit AccessType and metadata */
val mem_write_value_priv : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bits(8 * 'n), Privilege, bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value_priv (paddr, width, value, priv, aq, rl, con) =
  mem_write_value_priv_meta(paddr, width, value, Write(default_write_acc), priv, default_meta, aq, rl, con)

/* Memory write with explicit metadata and AccessType, implicit and Privilege */
val mem_write_value_meta : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bits(8 * 'n), ext_access_type, mem_meta, bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value_meta (paddr, width, value, ext_acc, meta, aq, rl, con) = {
  let typ = Write(ext_acc);
  let ep = effectivePrivilege(typ, mstatus, cur_privilege);
  mem_write_value_priv_meta(paddr, width, value, typ, ep, meta, aq, rl, con)
}

// /* Memory write with default AccessType, Privilege, and metadata */
// val mem_write_value : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bits(8 * 'n), bool, bool, bool) -> MemoryOpResult(bool)
function mem_write_value (paddr, width, value, aq, rl, con) = {
  mem_write_value_meta(paddr, width, value, default_write_acc, default_meta, aq, rl, con)
}


$ifdef _RV32S

  val init_cache : unit -> unit
  function init_cache () = { // Modificar para inicializar los registros en funcion del nivel de las caches y el numero de lineas por cache y el tamaño de bloque
    var sparams : cache_params = undefined;
    var bparams : cache_params = undefined;
    DirectLocation = unsigned(locpol());
    // var number_set : bits(32) = set_config(0b00000000);
    // var linesperset : bits(32) = set_config(0b00000001);
    L1.info.mcs = unsigned(cache_sizes(0b00000001));
    L1.info.mcb = unsigned(lb_sizes(0b00000001));
    L1.info.tag = unsigned(address_c(0b00000001,0b00000000));
    L1.info.num_lines_set = (set_config(0b00000001));
    // print_reg("L1 numlines set: " ^ BitStr(L1.info.num_lines_set));
    L1.info.index = unsigned(address_c(0b00000001,0b00000001));
    L1.info.offset = unsigned(address_c(0b00000001,0b00000010));

    // print_int("Divisor:", unsigned(L1.info.num_lines_set));
    // print_int("Dividendo:", L1.info.mcs);
    L1_I.info.mcs = unsigned(cache_sizes(0b00000010));
    L1_I.info.mcb = unsigned(lb_sizes(0b00000010));
    L1_I.info.num_lines_set = (set_config(0b00000001));
    L1_I.info.tag = unsigned(address_c(0b00000010,0b00000000));
    L1_I.info.index = unsigned(address_c(0b00000010,0b00000001));
    L1_I.info.offset = unsigned(address_c(0b00000010,0b00000010));

    L1_D.info.mcs = unsigned(cache_sizes(0b00000011));
    L1_D.info.mcb = unsigned(lb_sizes(0b00000011));
    L1_D.info.num_lines_set = (set_config(0b00000001));
    L1_D.info.tag = unsigned(address_c(0b00000011,0b00000000));
    L1_D.info.index = unsigned(address_c(0b00000011,0b00000001));
    L1_D.info.offset = unsigned(address_c(0b00000011,0b00000010));

    L2.info.mcs = unsigned(cache_sizes(0b00000100));
    L2.info.mcb = unsigned(lb_sizes(0b00000100));
    L2.info.num_lines_set = (set_config(0b00000001));
    L2.info.tag = unsigned(address_c(0b00000100,0b00000000));
    L2.info.index = unsigned(address_c(0b00000100,0b00000001));
    L2.info.offset = unsigned(address_c(0b00000100,0b00000010));

    L2_I.info.mcs = unsigned(cache_sizes(0b00000101));
    L2_I.info.mcb = unsigned(lb_sizes(0b00000101));
    L2_I.info.num_lines_set = (set_config(0b00000001));
    L2_I.info.tag = unsigned(address_c(0b00000101,0b00000000));
    L2_I.info.index = unsigned(address_c(0b00000101,0b00000001));
    L2_I.info.offset = unsigned(address_c(0b00000101,0b00000010));

    L2_D.info.mcs = unsigned(cache_sizes(0b00000110));
    // print_endline("Llego hasta aqui");
    L2_D.info.mcb = unsigned(lb_sizes(0b00000110));
    // print_endline("Llego hasta aqui");
    L2_D.info.num_lines_set = (set_config(0b00000001));
    // print_endline("Llego hasta aqui");
    L2_D.info.tag = unsigned(address_c(0b00000110,0b00000000));
    // print_endline("Llego hasta aqui");
    L2_D.info.index = unsigned(address_c(0b00000110,0b00000001));
    // print_endline("Llego hasta aqui");
    L2_D.info.offset = unsigned(address_c(0b00000110,0b00000010));
    // print_endline("Llego hasta aqui");
    // print_endline("Llego hasta aqui");
    // let kc : xlenbits = cache_levels();
    let crepc : xlenbits = crep();
    // cache_block_size = unsigned(lbparams);
    // kind_c = unsigned(kc);

    if (level_types == 0) then { // L1
      L1.info.cache_type = Cache_all;
      L1.info.busy_lines = zeros();
      L1.info.num_set = L1.info.mcs / unsigned(L1.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1.info.num_set = L1.info.mcs;
      };
      // unsigned(L1.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = Cache_Rep_RR;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 1) then { // L1_I + L1_D
      L1_I.info.cache_type = Cache_inst;
      L1_I.info.busy_lines = zeros();
      L1_I.info.num_set = L1_I.info.mcs / unsigned(L1_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_I.info.num_set = L1_I.info.mcs;
      };
      // L1_I.info.num_set = number_set;
      // unsigned(L1_I.info.num_lines_set) = linesperset;
      L1_D.info.cache_type = Cache_data;
      L1_D.info.busy_lines = zeros();
      L1_D.info.num_set = L1_D.info.mcs / unsigned(L1_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_D.info.num_set = L1_D.info.mcs;
      };
      // L1_D.info.num_set = number_set;
      // unsigned(L1_D.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = NULL;
        L1_I.info.rep_pol = Cache_Rep_RR;
        L1_D.info.rep_pol = Cache_Rep_RR;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   NULL;
        L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 2) then { // L1 + L2
      L1.info.cache_type = Cache_all;
      L1.info.busy_lines = zeros();
      L1.info.num_set = L1.info.mcs / unsigned(L1.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1.info.num_set = L1.info.mcs;
      };
      // L1.info.num_set = number_set;
      // unsigned(L1.info.num_lines_set) = linesperset;
      L2.info.cache_type = Cache_all;
      L2.info.busy_lines = zeros();
      L2.info.num_set = L2.info.mcs / unsigned(L2.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2.info.num_set = L2.info.mcs;
      };
      // L2.info.num_set = number_set;
      // unsigned(L2.info.num_lines_set) = linesperset;
      // L2_I.info.cache_type = Cache_inst;
      // L2_I.info.busy_lines = zeros();
      // L2_D.info.cache_type = Cache_data;
      // L2_D.info.busy_lines = zeros();

      // L1.info.mcs = unsigned(sparams.L1);
      // L1.info.mcb = unsigned(lbparams);

      // L1_I.info.mcs = 0;
      // L1_I.info.mcb = unsigned(lbparams);

      // L1_D.info.mcs = 0;
      // L1_D.info.mcb = unsigned(lbparams);

      // L2.info.mcs = unsigned(sparams.L2);
      // L2.info.mcb = unsigned(lbparams);

      // L2_I.info.mcs = 0;
      // L2_I.info.mcb = unsigned(lbparams);

      // L2_D.info.mcs = 0;
      // L2_D.info.mcb = unsigned(lbparams);

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = Cache_Rep_RR;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol = Cache_Rep_RR;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 3) then { // L1_I + L1_D + L2
      // L1.info.cache_type = Cache_all;
      // L1.info.busy_lines = zeros();
      L1_I.info.cache_type = Cache_inst;
      L1_I.info.busy_lines = zeros();
      L1_I.info.num_set = L1_I.info.mcs / unsigned(L1_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_I.info.num_set = L1_I.info.mcs;
      };
      // L1_I.info.num_set = number_set;
      // unsigned(L1_I.info.num_lines_set) = linesperset;
      L1_D.info.cache_type = Cache_data;
      L1_D.info.busy_lines = zeros();
      L1_D.info.num_set = L1_D.info.mcs / unsigned(L1_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_D.info.num_set = L1_D.info.mcs;
      };
      // L1_D.info.num_set = number_set;
      // unsigned(L1_D.info.num_lines_set) = linesperset;
      L2.info.cache_type = Cache_all;
      L2.info.busy_lines = zeros();
      L2.info.num_set = L2.info.mcs / unsigned(L2.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2.info.num_set = L2.info.mcs;
      };
      // L2.info.num_set = number_set;
      // unsigned(L2.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = NULL;
        L1_I.info.rep_pol = Cache_Rep_RR;
        L1_D.info.rep_pol = Cache_Rep_RR;
        L2.info.rep_pol = Cache_Rep_RR;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
        // print_endline("Cache policy FIFO");
      } else {
        L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2.info.rep_pol =   Cache_Rep_Simple_FIFO;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
      };

    } else if (level_types == 4) then { // L1 + L2_I + L2_D
      L1.info.cache_type = Cache_all;
      L1.info.busy_lines = zeros();
      L1.info.num_set = L1.info.mcs / unsigned(L1.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1.info.num_set = L1.info.mcs;
      };
      // L1.info.num_set = number_set;
      // unsigned(L1.info.num_lines_set) = linesperset;
      L2_I.info.cache_type = Cache_inst;
      L2_I.info.busy_lines = zeros();
      L2_I.info.num_set = L2_I.info.mcs / unsigned(L2_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_I.info.num_set = L2_I.info.mcs;
      };
      // L2_I.info.num_set = number_set;
      // unsigned(L2_I.info.num_lines_set) = linesperset;
      L2_D.info.cache_type = Cache_data;
      L2_D.info.busy_lines = zeros();
      L2_D.info.num_set = L2_D.info.mcs / unsigned(L2_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_D.info.num_set = L2_D.info.mcs;
      };
      // L2_D.info.num_set = number_set;
      // unsigned(L2_D.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = Cache_Rep_RR;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = Cache_Rep_RR;
        L2_D.info.rep_pol = Cache_Rep_RR;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 5) then { // L1_I + L1_D + L2_I + L2_D

      L1_I.info.cache_type = Cache_inst;
      L1_I.info.busy_lines = zeros();
      L1_I.info.num_set = L1_I.info.mcs / unsigned(L1_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_I.info.num_set = L1_I.info.mcs;
      };
      // L1_I.info.num_set = number_set;
      // unsigned(L1_I.info.num_lines_set) = linesperset;
      L1_D.info.cache_type = Cache_data;
      L1_D.info.busy_lines = zeros();
      L1_D.info.num_set = L1_D.info.mcs / unsigned(L1_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_D.info.num_set = L1_D.info.mcs;
      };
      // L1_D.info.num_set = number_set;
      // unsigned(L1_D.info.num_lines_set) = linesperset;
      L2_I.info.cache_type = Cache_inst;
      L2_I.info.busy_lines = zeros();
      L2_I.info.num_set = L2_I.info.mcs / unsigned(L2_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_I.info.num_set = L2_I.info.mcs;
      };
      // L2_I.info.num_set = number_set;
      // unsigned(L2_I.info.num_lines_set) = linesperset;
      L2_D.info.cache_type = Cache_data;
      L2_D.info.busy_lines = zeros();
      L2_D.info.num_set = L2_D.info.mcs / unsigned(L2_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_D.info.num_set = L2_D.info.mcs;
      };
      // L2_D.info.num_set = number_set;
      // unsigned(L2_D.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = NULL;
        L1_I.info.rep_pol = Cache_Rep_RR;
        L1_D.info.rep_pol = Cache_Rep_RR;
        L2.info.rep_pol = NULL;
        L2_I.info.rep_pol = Cache_Rep_RR;
        L2_D.info.rep_pol = Cache_Rep_RR;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   NULL;
        L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    };
  }


  val replace_cache : forall 'n, 0 <= 'n < 2048. (cache_mem_type, cache_level, xlenbits, int('n)) -> int

  function replace_cache(ct, cl, addr, init_line) = {

    // 1º Mirar la politica de reemplazo
    // 2º Si es random hacer un random de que elemento de la lista reemplazar
    // 3º Si es un valor modificado, escribir el valor en memoria
    // 4º Reemplazar el bloque de cache con el argumento

      if (L1_I.info.rep_pol == Cache_Rep_RR | L1_D.info.rep_pol == Cache_Rep_RR | L1.info.rep_pol == Cache_Rep_RR | L2.info.rep_pol == Cache_Rep_RR | L2_I.info.rep_pol == Cache_Rep_RR | L2_D.info.rep_pol == Cache_Rep_RR) then {
        if (ct == Cache_inst) then {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L1_I.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L1_I.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L1_I.mem_L1[index_rep].Cache_control_bits = zeros();
            L1_I.mem_L1[index_rep].Cache_addr = zeros();
            // L1_I.mem_L1[index_rep].Cache_tag = zeros(); //  addr[31..14];
            // L1_I.mem_L1[index_rep].Cache_index = zeros(); //  addr[13..4];
            // L1_I.mem_L1[index_rep].Cache_offset = zeros(); //  addr[13..4];
            index_rep
          } else {
            L1_I.mem_L1[init_line].Cache_control_bits = zeros();
            L1_I.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }

        } else if (ct == Cache_data) then {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L1_D.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L1_D.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L1_D.mem_L1[index_rep].Cache_control_bits = zeros();
            L1_D.mem_L1[index_rep].Cache_addr = zeros();
            
            index_rep
          } else {
            L1_D.mem_L1[init_line].Cache_control_bits = zeros();
            L1_D.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }
          
        } else if (ct == Cache_all & cl == LL1) then {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L1.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L1.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L1.mem_L1[index_rep].Cache_control_bits = zeros();
            L1.mem_L1[index_rep].Cache_addr = zeros();
            index_rep
          }else {
            L1.mem_L1[init_line].Cache_control_bits = zeros();
            L1.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }

        } else if (ct == Cache_inst & cl == LL2) then {
          if (DirectLocation == 0) then {
           
            let index_rep : int = unsigned(randomindex(L2_I.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L2_I.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L2_I.mem_L1[index_rep].Cache_control_bits = zeros();
            L2_I.mem_L1[index_rep].Cache_addr = zeros();
            index_rep 
          }else {
            L2_I.mem_L1[init_line].Cache_control_bits = zeros();
            L2_I.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }
        } else if (ct == Cache_data & cl == LL2) then {
          if (DirectLocation == 0) then {

            let index_rep : int = unsigned(randomindex(L2_D.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L2_D.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L2_D.mem_L1[index_rep].Cache_control_bits = zeros();
            L2_D.mem_L1[index_rep].Cache_addr = zeros();
            index_rep
          }else {
            L2_D.mem_L1[init_line].Cache_control_bits = zeros();
            L2_D.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }
        } else {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L2.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L2.info.mcs);
            // Actualizamos el vector de control y el tag y el index
            L2.mem_L2[index_rep].Cache_control_bits = zeros();
            L2.mem_L2[index_rep].Cache_addr = zeros();
            index_rep 
          } else {
            L2.mem_L2[init_line].Cache_control_bits = zeros();
            L2.mem_L2[init_line].Cache_addr = zeros();
            init_line
          }
        }
      } else { // Es el caso de FIFO
        if (ct == Cache_inst & cl == LL1) then {
          if (DirectLocation == 0) then {
            if (unsigned(L1_I.info.repl_lines) >= L1_I.info.mcs) then {
              L1_I.info.repl_lines = zeros();
            };
            L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_addr = zeros();
            L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_control_bits = zeros();
            L1_I.info.repl_lines = L1_I.info.repl_lines + 1;
            unsigned(L1_I.info.repl_lines - 1)
          } else {
            L1_I.mem_L1[init_line].Cache_addr = zeros();
            L1_I.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }
        } else if (ct == Cache_data & cl == LL1) then {

          if (DirectLocation == 0) then {
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_data_block = zeros();
            if (unsigned(L1_D.info.repl_lines) >= L1_D.info.mcs) then {
              L1_D.info.repl_lines = zeros();
            };
            L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_addr = zeros();
            L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_control_bits = zeros();
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_tag = zeros();
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_index = zeros();
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_offset = zeros();
            L1_D.info.repl_lines = L1_D.info.repl_lines + 1;
            print_int("repl_lines L1_D: ", unsigned(L1_D.info.repl_lines - 1));
            unsigned(L1_D.info.repl_lines - 1)
          } else {
            L1_D.mem_L1[init_line].Cache_addr = zeros();
            L1_D.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }

          
        } else if (ct == Cache_all & cl == LL1) then {
          if (DirectLocation == 0) then {

            if (unsigned(L1.info.repl_lines) >= L1.info.mcs) then {
              L1.info.repl_lines = zeros();
            };
            L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_addr = zeros();
            L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_control_bits = zeros();
            L1.info.repl_lines = L1.info.repl_lines + 1;
            print_int("repl_lines L1: ", unsigned(L1.info.repl_lines - 1));
            unsigned(L1.info.repl_lines - 1)
          } else {

            L1.mem_L1[init_line].Cache_addr = zeros();
            L1.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }

        } else if (ct == Cache_inst & cl == LL2) then {
          if (DirectLocation == 0) then {

            
            if (unsigned(L2_I.info.repl_lines) >= L2_I.info.mcs) then {
              L2_I.info.repl_lines = zeros();
            };
            L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_addr = zeros();
            L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_control_bits = zeros();
            L2_I.info.repl_lines = L2_I.info.repl_lines + 1;
            print_int("repl_lines L2_I: ", unsigned(L2_I.info.repl_lines - 1));
            unsigned(L2_I.info.repl_lines - 1)
          } else {
            L2_I.mem_L1[init_line].Cache_addr = zeros();
            L2_I.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }
        } else if (ct == Cache_data & cl == LL2) then {
          if (DirectLocation == 0) then {

            if (unsigned(L2_D.info.repl_lines) >= L2_D.info.mcs) then {
              L2_D.info.repl_lines = zeros();
            };
            L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_addr = zeros();
            L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_control_bits = zeros();
            L2_D.info.repl_lines = L2_D.info.repl_lines + 1;
            print_int("repl_lines L2_D: ", unsigned(L2_D.info.repl_lines - 1));
            unsigned(L2_D.info.repl_lines - 1)
          } else {
            L2_D.mem_L1[init_line].Cache_addr = zeros();
            L2_D.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }

        } else {
          if (DirectLocation == 0) then {

            if (unsigned(L2.info.repl_lines) >= L2.info.mcs) then {
              L2.info.repl_lines = zeros();
            };
            L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_addr = zeros();
            L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_control_bits = zeros();
            L2.info.repl_lines = L2.info.repl_lines + 1;
            print_int("repl_lines L2: ", unsigned(L2.info.repl_lines - 1));
            unsigned(L2.info.repl_lines - 1)            
          } else {
            L2.mem_L2[init_line].Cache_addr = zeros();
            L2.mem_L2[init_line].Cache_control_bits = zeros();
            init_line
          }
        }
      }
  }


  val write_cache : forall 'n, 0 < 'n <= 16. (cache_mem_type, cache_level, xlenbits, int('n), bits('n * 8), bool) -> bool

  function write_cache(ct, cl, addr, width, value, new_line) = {

    var found : bool = false;
    var written : bool = false;
    let maxbs : int = L1_I.info.mcb;

    if(new_line) then {
      var lines_to_store_128 : bits(128) = zeros();
      var lines_to_store_64 : bits(128) = zeros();
      var lines_to_store_32 : bits(32) = zeros();

      if (ct == Cache_inst & cl == LL1) then {
        let tah = (L1_I.info.offset + L1_I.info.index + L1_I.info.tag - 1);
        let tal = (L1_I.info.offset + L1_I.info.index);

        let inh = L1_I.info.offset + (L1_I.info.index - 1);
        let inl = (L1_I.info.offset);

        let tag_s : int = L1_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L1_I.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L1_I.info.num_lines_set);
            let lines : int = init + unsigned(L1_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_I.mem_L1[i].Cache_control_bits = 0b00001;
                L1_I.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
              if(L1_I.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_I.mem_L1[id_set].Cache_control_bits = 0b00001;
                L1_I.mem_L1[id_set].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L1_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L1_I.mem_L1[i].Cache_control_bits = 0b00001;
              L1_I.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(32 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);
          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };

      } else if (ct == Cache_data & cl == LL1) then {
        let tah = (L1_D.info.offset + L1_D.info.index + L1_D.info.tag - 1);
        let tal = (L1_D.info.offset + L1_D.info.index);

        let inh = L1_D.info.offset + (L1_D.info.index - 1);
        let inl = (L1_D.info.offset);

        let tag_s : int = L1_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];
          let id_set : int = unsigned(c_index) % L1_D.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L1_D.info.num_lines_set);
            let lines : int = init + unsigned(L1_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_D.mem_L1[i].Cache_control_bits = 0b00001;
                L1_D.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
          
              }
            };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, init);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
          } else {

            if(L1_D.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_D.mem_L1[id_set].Cache_control_bits = 0b00001;
                L1_D.mem_L1[id_set].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
          
              };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };

          };

        } else {
          let lines : int = unsigned(L1_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L1_D.mem_L1[i].Cache_control_bits = 0b00001;
              L1_D.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(32 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((addr_p)) ^ ")");
        
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

      } else if (ct == Cache_all & cl == LL1) then {
        let tah = (L1.info.offset + L1.info.index + L1.info.tag - 1);
        let tal = L1.info.offset + L1.info.index;

        let inh = L1.info.offset + (L1.info.index - 1);
        let inl = (L1.info.offset);

        let tag_s : int = L1.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L1.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L1.info.num_lines_set);
            assert(0 <= init & init < 2048);
            let lines : int = init + unsigned(L1.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1.mem_L1[i].Cache_control_bits = 0b00001;
                L1.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };

            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
              if(L1.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1.mem_L1[id_set].Cache_control_bits = 0b00001;
                L1.mem_L1[id_set].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              };


              if (written == false) then {
                let index : int = replace_cache(ct, cl, addr, id_set);
                written = write_cache(ct, cl, addr, width, value, new_line);

              };
          };

        } else {
          let lines : int = unsigned(L1.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L1.mem_L1[i].Cache_control_bits = 0b00001;
              L1.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(32 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };

      } else if (ct == Cache_inst & cl == LL2) then {
        let tah = (L2_I.info.offset + L2_I.info.index + L2_I.info.tag - 1);
        let tal = (L2_I.info.offset + L2_I.info.index);

        let inh = L2_I.info.offset + (L2_I.info.index - 1);
        let inl = (L2_I.info.offset);

        let tag_s : int = L2_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L2_I.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L2_I.info.num_lines_set);
            let lines : int = init + unsigned(L2_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L2_I.mem_L1[i].Cache_control_bits = 0b00001;
                L2_I.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);
            };
          } else {
            if(L2_I.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_I.mem_L1[id_set].Cache_control_bits = 0b00001;
              L2_I.mem_L1[id_set].Cache_addr = addr;
              assert((tag_s + ind_s) < 32);
              print_reg("["^ dec_str(id_set) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          
          };

        } else {
          let lines : int = unsigned(L2_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_I.mem_L1[i].Cache_control_bits = 0b00001;
              L2_I.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(32 - tag_s);
              print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

      } else if (ct == Cache_data & cl == LL2) then {
        let tah = (L2_D.info.offset + L2_D.info.index + L2_D.info.tag - 1);
        let tal = (L2_D.info.offset + L2_D.info.index);

        let inh = L2_D.info.offset + (L2_D.info.index - 1);
        let inl = (L2_D.info.offset);

        let tag_s : int = L2_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];
          let id_set : int = unsigned(c_index) % L2_D.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
            let init : int = id_set * unsigned(L2_D.info.num_lines_set);

            let lines : int = init + unsigned(L2_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L2_D.mem_L1[i].Cache_control_bits = 0b00001;
                L2_D.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
            if(L2_D.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_D.mem_L1[id_set].Cache_control_bits = 0b00001;
              L2_D.mem_L1[id_set].Cache_addr = addr;
              assert((tag_s + ind_s) < 32);
              print_reg("["^ dec_str(id_set) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_D.mem_L1[i].Cache_control_bits = 0b00001;
              L2_D.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(32 - tag_s);
              print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };


      } else { // Si no es ninguna de las dos es una caché L2
        let tah = (L2.info.offset + L2.info.index + L2.info.tag - 1);
        let tal = (L2.info.offset + L2.info.index);

        let inh = L2.info.offset + (L2.info.index - 1);
        let inl = (L2.info.offset);

        let tag_s : int = L2.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
        let c_tag = addr[tah..tal];
        let ind_s : int = L2.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L2.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
            let init : int = id_set * unsigned(L2.info.num_lines_set);

            let lines : int = init + unsigned(L2.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2.mem_L2[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L2.mem_L2[i].Cache_control_bits = 0b00001;
                L2.mem_L2[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
            if(L2.mem_L2[id_set].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2.mem_L2[id_set].Cache_control_bits = 0b00001;
              L2.mem_L2[id_set].Cache_addr = addr;
              assert((tag_s + ind_s) < 32);
              print_reg("["^ dec_str(id_set) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
            };

            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L2.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2.mem_L2[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2.mem_L2[i].Cache_control_bits = 0b00001;
              L2.mem_L2[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(32 - tag_s);
              print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };
      };


    } else { // cuando no se quiere escribir una nueva linea solo un elemento

      // 1) Busca la linea de caché
      // 1.1) Si existe la línea Ir a 3
      // 1.2) No existe la linea Ir a 2 y notificar cache miss
      // 2) Escribir nueva linea caché return true
      // 3) Modificar el valor de la linea cache.

      if (cl == LL1) then { // Nivel 1: (Insn + Datos) o Unificada
        if (ct == Cache_data) then {
          
        let tah = (L1_D.info.offset + L1_D.info.index + L1_D.info.tag - 1);
        let tal = (L1_D.info.offset + L1_D.info.index);

        let inh = L1_D.info.offset + (L1_D.info.index - 1);
        let inl = (L1_D.info.offset);

        let tag_s : int = L1_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];
          let id_set : int = unsigned(c_index) %  L1_D.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
            let init : int = id_set * unsigned(L1_D.info.num_lines_set);

            let lines : int = init + unsigned(L1_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {

            if(L1_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
              written = true;
              found = true;
              assert((tag_s + ind_s) < 32);
              print_reg("["^ dec_str(id_set) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
            };

            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L1_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
              written = true;
              found = true;
              let addr_p = c_tag @ zeros(32 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };


          if (found == false) then { // Observamos si se encuentra en L2
            print_endline("Write Cache L1_D miss");
            if (level_types == 3) then {
              written = write_cache(Cache_all, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_data, LL1, addr, width, value, true);
                written = write_cache(Cache_data, LL1, addr, width, value, false);
                written = write_cache(Cache_all, LL2, addr, width, value, false);
              };
            } else if (level_types == 5) then {
              written = write_cache(Cache_data, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_data, LL1, addr, width, value, true);
                written = write_cache(Cache_data, LL1, addr, width, value, false);
                written = write_cache(Cache_data, LL2, addr, width, value, false);
              };
            } else if {level_types == 1} then {
              written = write_cache(Cache_data, LL1, addr, width, value, true);
              written = write_cache(Cache_data, LL1, addr, width, value, false);
            };
          };
        } else if (ct == Cache_inst) then {
          let tah = (L1_I.info.offset + L1_I.info.index + L1_I.info.tag - 1);
          let tal = (L1_I.info.offset + L1_I.info.index);

          let inh = L1_I.info.offset + (L1_I.info.index - 1);
          let inl = (L1_I.info.offset);

          let tag_s : int = L1_I.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
          let c_tag = addr[tah..tal];
          let ind_s : int = L1_I.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L1_I.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L1_I.info.num_lines_set);
              let lines : int = init + unsigned(L1_I.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 32);
                  print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
                }
              };
            } else {

              if(L1_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              };
            };

          } else {
            let lines : int = unsigned(L1_I.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(32 - tag_s);
                print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L1_I miss");
            if (level_types == 3) then {
              written = write_cache(Cache_all, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_inst, LL1, addr, width, value, true);
                written = write_cache(Cache_inst, LL1, addr, width, value, false);
                written = write_cache(Cache_all, LL2, addr, width, value, false);
              };
            } else if (level_types == 5) then {
              written = write_cache(Cache_inst, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_inst, LL1, addr, width, value, true);
                written = write_cache(Cache_inst, LL1, addr, width, value, false);
                written = write_cache(Cache_inst, LL2, addr, width, value, false);
              };
            } else if {level_types == 1} then {
              written = write_cache(Cache_inst, LL1, addr, width, value, true);
              written = write_cache(Cache_inst, LL1, addr, width, value, false);
            };
          }
        }
        else {
          let tah = (L1.info.offset + L1.info.index + L1.info.tag - 1);
          let tal = (L1.info.offset + L1.info.index);

          let inh = L1.info.offset + (L1.info.index - 1);
          let inl = (L1.info.offset);

          let tag_s : int = L1.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
          let c_tag = addr[tah..tal];
          let ind_s : int = L1.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L1.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L1.info.num_lines_set);
              let lines : int = init + unsigned(L1.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 32);
                  print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L1.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };

          } else {
            let lines : int = unsigned(L1.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(32 - tag_s);
                print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L1 miss");
            if (level_types == 2) then {
              written = write_cache(Cache_all, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_all, LL1, addr, width, value, true);
                written = write_cache(Cache_all, LL1, addr, width, value, false);
                written = write_cache(Cache_all, LL2, addr, width, value, false);
              };
            } else if (level_types == 4) then {
              written = write_cache(Cache_inst, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_all, LL1, addr, width, value, true);
                written = write_cache(Cache_all, LL1, addr, width, value, false);
                written = write_cache(Cache_inst, LL2, addr, width, value, false);
              };
            } else if {level_types == 0} then {
              written = write_cache(Cache_all, LL1, addr, width, value, true);
              written = write_cache(Cache_all, LL1, addr, width, value, false);
            };
          }
        };
      } else { // Cache de nivel 2
        if (ct ==  Cache_inst) then {
          let tah = (L2_I.info.offset + L2_I.info.index + L2_I.info.tag - 1);
          let tal = (L2_I.info.offset + L2_I.info.index);

          let inh = L2_I.info.offset + (L2_I.info.index - 1);
          let inl = (L2_I.info.offset);

          let tag_s : int = L2_I.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
          let c_tag = addr[tah..tal];
          let ind_s : int = L2_I.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L2_I.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L2_I.info.num_lines_set);
              let lines : int = init + unsigned(L2_I.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 32);
                  print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L2_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };

          } else {
            let lines : int = unsigned(L2_I.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(32 - tag_s);
                print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L2_I miss");

            written = write_cache(Cache_inst, LL2, addr, width, value, true);
            written = write_cache(Cache_inst, LL2, addr, width, value, false);
            written = false;
          }
        } else if (ct == Cache_data) then {
          let tah = (L2_D.info.offset + L2_D.info.index + L2_D.info.tag - 1);
          let tal = (L2_D.info.offset + L2_D.info.index);

          let inh = L2_D.info.offset + (L2_D.info.index - 1);
          let inl = (L2_D.info.offset);

          let tag_s : int = L2_D.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
          let c_tag = addr[tah..tal];
          let ind_s : int = L2_D.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L2_D.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {
  
              let init : int = id_set * unsigned(L2_D.info.num_lines_set);
              let lines : int = init + unsigned(L2_D.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 32);
                  print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L2_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            }; 

          } else {
            let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(32 - tag_s);
                print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };
          if(found == false) then {
            print_endline("Write Cache L2_D miss");
            written = write_cache(Cache_data, LL2, addr, width, value, true);
            written = write_cache(Cache_data, LL2, addr, width, value, false);
            written = false;
          }

        } else {
          let tah = (L2.info.offset + L2.info.index + L2.info.tag - 1);
          let tal = (L2.info.offset + L2.info.index);

          let inh = L2.info.offset + (L2.info.index - 1);
          let inl = (L2.info.offset);

          let tag_s : int = L2.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32) & tag_s < 32);
          let c_tag = addr[tah..tal];
          let ind_s : int = L2.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L2.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L2.info.num_lines_set);
              let lines : int = init + unsigned(L2.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 32);
                  print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L2.mem_L2[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 32);
                print_reg("["^ dec_str(id_set) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(32 - (tag_s + ind_s)))) ^ ") ");
              }
            };

          } else {
            let lines : int = unsigned(L2.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(32 - tag_s);
                print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L2 miss");
            written = write_cache(Cache_all, LL2, addr, width, value, true);
            written = write_cache(Cache_all, LL2, addr, width, value, false);
            written = false;
          }

        }



      };
    };
    written
  }

  // hacer un prewrite de la cache


  val read_cache : forall 'n, 0 < 'n <= 4096. /*16.*/ (cache_mem_type, cache_level, xlenbits, int('n)) ->  bool

  function read_cache(ct, cl, addr, width) = {
    // Descomponemos la direccion en los 3 elementos a buscar
    var result    : bits(8 * 'n) = zeros();
    var set : int = 0;

    var found : bool = false;
    // var can_continue = false;
    var width_to_read : int = 0;

    // Primero se prueba que el width corresponde con el tamaño de cache
    if (cl == LL1) then {
      if (ct == Cache_data) then {
        if (L1_D.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L1_D.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L1_D.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else if (ct == Cache_inst) then {
        if (L1_I.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L1_I.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L1_I.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else {
        if (L1.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L1.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L1.info.mcb / 8)), new_width);
        } else width_to_read = width;

      }
    } else {
      if (ct == Cache_data) then {
        if (L2_D.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L2_D.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L2_D.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else if (ct == Cache_inst) then {
        if (L2_I.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L2_I.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L2_I.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else {
        if (L2.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L2.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L2.info.mcb / 8)), new_width);
        } else width_to_read = width;

      }
    };

    let new_width = width_to_read;
    assert(0 < new_width & new_width <= 4096);
    if (cl  == LL1) then { // Si es de nivel 1 buscamos entre datos + instrucciones o una cache unificada
      if(ct == Cache_data) then {

        let tah = (L1_D.info.offset + L1_D.info.index + L1_D.info.tag - 1);
        let tal = (L1_D.info.offset + L1_D.info.index);

        let inh = L1_D.info.offset + (L1_D.info.index - 1);
        let inl = (L1_D.info.offset);

        let tag_s : int = L1_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32));
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L1_D.info.num_set;
          
          assert( 0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L1_D.info.num_lines_set);
            let lines : int = init + unsigned(L1_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_D.mem_L1[i].Cache_control_bits == 0b00001) then {
                found = true;
                print_endline("Cache L1_D hit");
              }
            }
          } else {

              if(L1_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L1_D.mem_L1[id_set].Cache_control_bits == 0b00001) then {
                found = true;
                print_endline("Cache L1_D hit");
              }
          };

        } else {
          let lines : int = unsigned(L1_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_D.mem_L1[i].Cache_control_bits == 0b00001) then {
              found = true;
              print_endline("Cache L1_D hit");
            }
          }
        };

        if (found == false) then {
          print_reg("Cache L1_D miss on: " ^ BitStr(addr));
          // Mirar que cache es
          if (level_types == 1) then {
            let lines_to_store : bits (128) = zeros();
            found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
            // Devolver el valor escrito
          } else if (level_types == 5) then {

            // assert(0 < width_to_read & width_to_read <= 4096);
            found = read_cache(Cache_data, LL2, addr, new_width);
          };
        };

      } else if (ct == Cache_inst) then {
        let tah = (L1_I.info.offset + L1_I.info.index + L1_I.info.tag - 1);
        let tal = (L1_I.info.offset + L1_I.info.index);

        let inh = L1_I.info.offset + (L1_I.info.index - 1);
        let inl = (L1_I.info.offset);

        let tag_s : int = L1_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32));
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L1_I.info.num_set;
          // print_int("Id_set:", id_set);
          // print_reg("index: " ^BitStr(c_index));
          // print_int("Numbser:", L1_I.info.num_set);
          assert( 0 <= id_set & id_set < 2048);

          if (DirectLocation == 0) then  {
            let init : int = id_set * unsigned(L1_I.info.num_lines_set);

            let lines : int = init + unsigned(L1_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_I.mem_L1[i].Cache_control_bits == 0b00001) then {
                found = true;
                print_endline("Cache L1_I hit");
              }
            }
          } else {

            if(L1_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L1_I.mem_L1[id_set].Cache_control_bits == 0b00001) then {
              found = true;
              print_endline("Cache L1_I hit");
            }
          };

        } else {
          let lines : int = unsigned(L1_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_I.mem_L1[i].Cache_control_bits == 0b00001) then {
              found = true;
              print_endline("Cache L1_I hit");
            }
          }
        };

        if (found == false) then {
          print_endline("Cache L1_I miss");
          // Si no se encuentra se busca en L2
          if (level_types == 1) then {
            if ( L1_I.info.mcb == 128 ) then {
              let lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
            } else if ( L1.info.mcb == 64 ) then {
              let lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
            } else if ( L1.info.mcb == 32 ) then {
              let lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
            };
          } else if (level_types == 3) then {
            found = read_cache(Cache_all, LL2, addr, new_width);
          } else if (level_types == 5) then {
            found = read_cache(Cache_inst, LL2, addr, new_width);
          };
        };

      } else { // Buscar en toda la cache L1
        let tah = L1.info.offset + L1.info.index + L1.info.tag - 1;
        let tal = L1.info.offset + L1.info.index;

        let inh = L1.info.offset + (L1.info.index - 1);
        let inl = L1.info.offset;

        let tag_s : int = L1.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32));
        let c_tag = addr[tah..tal];
        // print_reg("c_tag: " ^BitStr(c_tag));
        let ind_s : int = L1.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L1.info.num_set;
          // print_int("id_set: ", id_set);
          assert( 0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then  {
            let init : int = id_set * unsigned(L1.info.num_lines_set);
            assert( 0 <= init & init < 2048);

            let lines : int = init + unsigned(L1.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1.mem_L1[i].Cache_control_bits == 0b00001) then { //
                found = true;
                if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L1 hit inst") else print_reg("Cache L1 hit data on: " ^ BitStr(addr));
              }
            }
          } else {

            if(L1.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L1.mem_L1[id_set].Cache_control_bits == 0b00001) then { //
              found = true;
              if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L1 hit inst") else print_reg("Cache L1 hit data on: " ^ BitStr(addr));
            }
          };

        } else {
          let lines : int = unsigned(L1.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            // print_reg("Cache_add: " ^BitStr(L1.mem_L1[i].Cache_addr[tah..tal]));
            // print_reg("Cache_control_bits: " ^ BitStr(L1.mem_L1[i].Cache_control_bits));
            if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1.mem_L1[i].Cache_control_bits == 0b00001) then {
              found = true;
              if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L1 hit inst") else print_reg("Cache L1 hit data on: " ^ BitStr(addr));
            }
          }
        };

        if (found == false) then {
          // print_endline("Cache L1 miss");
          if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L1 miss inst") else print_reg("Cache L1 miss data on: " ^ BitStr(addr));
          if (level_types == 0) then {
            if (L1.info.mcb == 128) then {
              let lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
            } else if (L1.info.mcb == 64) then {
              let lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
            } else if (L1.info.mcb == 32) then {
              let lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
            };

          } else if (level_types == 2) then {
            found = read_cache(Cache_all, LL2, addr, new_width);
          } else if (level_types == 4) then {
            if (PC == addr | (PC + 2) == addr) then {
              found = read_cache(Cache_inst, LL2, addr, new_width);
            } else {
              found = read_cache(Cache_data, LL2, addr, new_width);
            }
          }
        };

      };

    } else { // Buscamos en L2
      if (ct == Cache_data) then {
        let tah = (L2_D.info.offset + L2_D.info.index + L2_D.info.tag - 1);
        let tal = (L2_D.info.offset + L2_D.info.index);

        let inh = L2_D.info.offset + (L2_D.info.index - 1);
        let inl = (L2_D.info.offset);

        let tag_s : int = L2_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32));
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L2_D.info.num_set;
          assert( 0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L2_D.info.num_lines_set);
            let lines : int = init + unsigned(L2_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_D.mem_L1[i].Cache_control_bits == 0b00001) then {
                found = true;
                print_endline("Cache L2_D hit");
              }
            }
          } else {

            if(L2_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L2_D.mem_L1[id_set].Cache_control_bits == 0b00001) then {
              found = true;
              print_endline("Cache L2_D hit");
            }
          };

        } else {
          let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_D.mem_L1[i].Cache_control_bits == 0b00001) then {
              found = true;
              print_endline("Cache L2_D hit");
            }
          }
        };

        if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                  // solicitamos a memoria un bloque entero para L1
                                  // y tambien lo escribimos en L2
          print_reg("Cache L2_D miss on: " ^ BitStr(addr));

          if (level_types == 4) then {
            if (L2_D.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
            } else if (L2_D.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
            } else if (L2_D.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
            };
          } else if (level_types == 5) then {
            if (L1_D.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
            } else if (L1_D.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_data, LL1, addr, 8, lines_to_store, true);
            } else if (L1_D.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_data, LL1, addr, 4, lines_to_store, true);
            };
          };
          if (L2_D.info.mcb == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_data,LL2,addr, 16, lines_to_store, true);
          } else if (L2_D.info.mcb == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_data,LL2,addr, 8, lines_to_store, true);
          } else if (L2_D.info.mcb == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_data,LL2,addr, 4, lines_to_store, true);
          };

        }

      } else if (ct == Cache_inst) then {
        let tah = (L2_I.info.offset + L2_I.info.index + L2_I.info.tag - 1);
        let tal = (L2_I.info.offset + L2_I.info.index);

        let inh = L2_I.info.offset + (L2_I.info.index - 1);
        let inl = (L2_I.info.offset);

        let tag_s : int = L2_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32));
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L2_I.info.num_set;
          assert( 0 <= id_set & id_set < 2048);
          
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L2_I.info.num_lines_set);
            let lines : int = init + unsigned(L2_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_I.mem_L1[i].Cache_control_bits == 0b00001) then {
                found = true;
                print_endline("Cache L2_I hit");
              }
            }
          } else {

            if(L2_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L2_I.mem_L1[id_set].Cache_control_bits == 0b00001) then {
              found = true;
              print_endline("Cache L2_I hit");
            }
          };

        } else {
          let lines : int = unsigned(L2_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_I.mem_L1[i].Cache_control_bits == 0b00001) then {
              found = true;
              print_endline("Cache L2_I hit");
            }
          }
        };


        if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                  // solicitamos a memoria un bloque entero para L1
                                  // y tambien lo escribimos en L2
          print_endline("Cache L2_I miss");
          // Si falla en L2, miramos si la direccion es relativa al pc o es relativa a memoria y leemos


          if (level_types == 4) then {
            if (L1.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
            } else if (L1.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
            } else if (L1.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
            };

          } else if (level_types == 5) then {
            if (L1_I.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
            } else if (L1_I.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
            } else if (L1_I.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
            };

          };
          if (L2_I.info.mcb == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_inst,LL2,addr, 16, lines_to_store, true);
          } else if (L2_I.info.mcb == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_inst,LL2,addr, 8, lines_to_store, true);
          } else if (L2_I.info.mcb == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_inst,LL2,addr, 4, lines_to_store, true);
          };


        };

      } else {
        let tah = (L2.info.offset + L2.info.index + L2.info.tag - 1);
        let tal = (L2.info.offset + L2.info.index);

        let inh = L2.info.offset + (L2.info.index - 1);
        let inl = (L2.info.offset);

        let tag_s : int = L2.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 32));
        let c_tag = addr[tah..tal];
        let ind_s : int = L2.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 32));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L2.info.num_set;
          assert( 0 <= id_set & id_set < 2048);
          
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L2.info.num_lines_set);
            let lines : int = init + unsigned(L2.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & found == false & L2.mem_L2[i].Cache_control_bits == 0b00001) then {
                found = true;
                if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 hit inst") else print_endline("Cache L2 hit data");
              }
            }
          } else {
            if(L2.mem_L2[id_set].Cache_addr[tah..tal] == c_tag & found == false & L2.mem_L2[id_set].Cache_control_bits == 0b00001) then {
              found = true;
              if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 hit inst") else print_endline("Cache L2 hit data");
            }
          };

        } else {
          let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & found == false & L2.mem_L2[i].Cache_control_bits == 0b00001) then {
              found = true;
              if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 hit inst") else print_endline("Cache L2 hit data");
            }
          }
        };

        if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                  // solicitamos a memoria un bloque entero para L1
                                  // y tambien lo escribimos en L2
          if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 miss inst") else print_endline("Cache L2 miss data");

          // Si falla en L2, miramos si la direccion es relativa al pc o es relativa a memoria y leemos


          if (PC == addr | (PC + 2) == addr) then {
            if (level_types == 2) then { // Significa que L1 es de tipo all
              if (L1.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
              } else if (L1.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
              } else if (L1.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
              };

            } else if (level_types == 3) then {
              if (L1_I.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
              } else if (L1_I.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
              } else if (L1_I.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
              };

            };

          }else {
            if (level_types == 2) then { // Significa que L1 es de tipo all
              if (L1.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
              } else if (L1.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
              } else if (L1.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
              };

            } else if (level_types == 3) then {
              if (L1_D.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
              } else if (L1_D.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_data, LL1, addr, 8, lines_to_store, true);
              } else if (L1_D.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_data, LL1, addr, 4, lines_to_store, true);
              };
            };
          };
          if (L2.info.mcb == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_all,LL2,addr, 16, lines_to_store, true);
          } else if (L2.info.mcb == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_all,LL2,addr, 8, lines_to_store, true);
          } else if (L2.info.mcb == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_all,LL2,addr, 4, lines_to_store, true);
          };


        };
      };
    };
    found

  }


$endif _RV32S

$ifdef _RV64S

  val init_cache : unit -> unit
  function init_cache () = { // Modificar para inicializar los registros en funcion del nivel de las caches y el numero de lineas por cache y el tamaño de bloque
    var sparams : cache_params = undefined;
    var bparams : cache_params = undefined;
    DirectLocation = unsigned(locpol());
    // var number_set : bits(32) = set_config(0b00000000);
    // var linesperset : bits(32) = set_config(0b00000001);
    L1.info.mcs = unsigned(cache_sizes(0b00000001));
    L1.info.mcb = unsigned(lb_sizes(0b00000001));
    L1.info.tag = unsigned(address_c(0b00000001,0b00000000));
    L1.info.num_lines_set = (set_config(0b00000001));
    L1.info.index = unsigned(address_c(0b00000001,0b00000001));
    L1.info.offset = unsigned(address_c(0b00000001,0b00000010));

    L1_I.info.mcs = unsigned(cache_sizes(0b00000010));
    L1_I.info.mcb = unsigned(lb_sizes(0b00000010));
    L1_I.info.num_lines_set = (set_config(0b00000001));
    L1_I.info.tag = unsigned(address_c(0b00000010,0b00000000));
    L1_I.info.index = unsigned(address_c(0b00000010,0b00000001));
    L1_I.info.offset = unsigned(address_c(0b00000010,0b00000010));

    L1_D.info.mcs = unsigned(cache_sizes(0b00000011));
    L1_D.info.mcb = unsigned(lb_sizes(0b00000011));
    L1_D.info.num_lines_set = (set_config(0b00000001));
    L1_D.info.tag = unsigned(address_c(0b00000011,0b00000000));
    L1_D.info.index = unsigned(address_c(0b00000011,0b00000001));
    L1_D.info.offset = unsigned(address_c(0b00000011,0b00000010));

    L2.info.mcs = unsigned(cache_sizes(0b00000100));
    L2.info.mcb = unsigned(lb_sizes(0b00000100));
    L2.info.num_lines_set = (set_config(0b00000001));
    L2.info.tag = unsigned(address_c(0b00000100,0b00000000));
    L2.info.index = unsigned(address_c(0b00000100,0b00000001));
    L2.info.offset = unsigned(address_c(0b00000100,0b00000010));

    L2_I.info.mcs = unsigned(cache_sizes(0b00000101));
    L2_I.info.mcb = unsigned(lb_sizes(0b00000101));
    L2_I.info.num_lines_set = (set_config(0b00000001));
    L2_I.info.tag = unsigned(address_c(0b00000101,0b00000000));
    L2_I.info.index = unsigned(address_c(0b00000101,0b00000001));
    L2_I.info.offset = unsigned(address_c(0b00000101,0b00000010));

    L2_D.info.mcs = unsigned(cache_sizes(0b00000110));
    L2_D.info.mcb = unsigned(lb_sizes(0b00000110));
    L2_D.info.num_lines_set = (set_config(0b00000001));
    L2_D.info.tag = unsigned(address_c(0b00000110,0b00000000));
    L2_D.info.index = unsigned(address_c(0b00000110,0b00000001));
    L2_D.info.offset = unsigned(address_c(0b00000110,0b00000010));

    // let kc : xlenbits = cache_levels();
    let crepc : bits(32) = crep();
    // cache_block_size = unsigned(lbparams);
    // kind_c = unsigned(kc);

    if (level_types == 0) then { // L1
      L1.info.cache_type = Cache_all;
      L1.info.busy_lines = zeros();
      L1.info.num_set = L1.info.mcs / unsigned(L1.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1.info.num_set = L1.info.mcs;
      };
      // unsigned(L1.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = Cache_Rep_RR;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 1) then { // L1_I + L1_D
      L1_I.info.cache_type = Cache_inst;
      L1_I.info.busy_lines = zeros();
      L1_I.info.num_set = L1_I.info.mcs / unsigned(L1_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_I.info.num_set = L1_I.info.mcs;
      };
      // L1_I.info.num_set = number_set;
      // unsigned(L1_I.info.num_lines_set) = linesperset;
      L1_D.info.cache_type = Cache_data;
      L1_D.info.busy_lines = zeros();
      L1_D.info.num_set = L1_D.info.mcs / unsigned(L1_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_D.info.num_set = L1_D.info.mcs;
      };
      // L1_D.info.num_set = number_set;
      // unsigned(L1_D.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = NULL;
        L1_I.info.rep_pol = Cache_Rep_RR;
        L1_D.info.rep_pol = Cache_Rep_RR;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   NULL;
        L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 2) then { // L1 + L2
      L1.info.cache_type = Cache_all;
      L1.info.busy_lines = zeros();
      L1.info.num_set = L1.info.mcs / unsigned(L1.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1.info.num_set = L1.info.mcs;
      };
      // L1.info.num_set = number_set;
      // unsigned(L1.info.num_lines_set) = linesperset;
      L2.info.cache_type = Cache_all;
      L2.info.busy_lines = zeros();
      L2.info.num_set = L2.info.mcs / unsigned(L2.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2.info.num_set = L2.info.mcs;
      };
      // L2.info.num_set = number_set;
      // unsigned(L2.info.num_lines_set) = linesperset;
      // L2_I.info.cache_type = Cache_inst;
      // L2_I.info.busy_lines = zeros();
      // L2_D.info.cache_type = Cache_data;
      // L2_D.info.busy_lines = zeros();

      // L1.info.mcs = unsigned(sparams.L1);
      // L1.info.mcb = unsigned(lbparams);

      // L1_I.info.mcs = 0;
      // L1_I.info.mcb = unsigned(lbparams);

      // L1_D.info.mcs = 0;
      // L1_D.info.mcb = unsigned(lbparams);

      // L2.info.mcs = unsigned(sparams.L2);
      // L2.info.mcb = unsigned(lbparams);

      // L2_I.info.mcs = 0;
      // L2_I.info.mcb = unsigned(lbparams);

      // L2_D.info.mcs = 0;
      // L2_D.info.mcb = unsigned(lbparams);

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = Cache_Rep_RR;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol = Cache_Rep_RR;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 3) then { // L1_I + L1_D + L2
      // L1.info.cache_type = Cache_all;
      // L1.info.busy_lines = zeros();
      L1_I.info.cache_type = Cache_inst;
      L1_I.info.busy_lines = zeros();
      L1_I.info.num_set = L1_I.info.mcs / unsigned(L1_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_I.info.num_set = L1_I.info.mcs;
      };
      // L1_I.info.num_set = number_set;
      // unsigned(L1_I.info.num_lines_set) = linesperset;
      L1_D.info.cache_type = Cache_data;
      L1_D.info.busy_lines = zeros();
      L1_D.info.num_set = L1_D.info.mcs / unsigned(L1_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_D.info.num_set = L1_D.info.mcs;
      };
      // L1_D.info.num_set = number_set;
      // unsigned(L1_D.info.num_lines_set) = linesperset;
      L2.info.cache_type = Cache_all;
      L2.info.busy_lines = zeros();
      L2.info.num_set = L2.info.mcs / unsigned(L2.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2.info.num_set = L2.info.mcs;
      };
      // L2.info.num_set = number_set;
      // unsigned(L2.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = NULL;
        L1_I.info.rep_pol = Cache_Rep_RR;
        L1_D.info.rep_pol = Cache_Rep_RR;
        L2.info.rep_pol = Cache_Rep_RR;
        L2_I.info.rep_pol = NULL;
        L2_D.info.rep_pol = NULL;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
        // print_endline("Cache policy FIFO");
      } else {
        L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2.info.rep_pol =   Cache_Rep_Simple_FIFO;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
        print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
      };

    } else if (level_types == 4) then { // L1 + L2_I + L2_D
      L1.info.cache_type = Cache_all;
      L1.info.busy_lines = zeros();
      L1.info.num_set = L1.info.mcs / unsigned(L1.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1.info.num_set = L1.info.mcs;
      };
      // L1.info.num_set = number_set;
      // unsigned(L1.info.num_lines_set) = linesperset;
      L2_I.info.cache_type = Cache_inst;
      L2_I.info.busy_lines = zeros();
      L2_I.info.num_set = L2_I.info.mcs / unsigned(L2_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_I.info.num_set = L2_I.info.mcs;
      };
      // L2_I.info.num_set = number_set;
      // unsigned(L2_I.info.num_lines_set) = linesperset;
      L2_D.info.cache_type = Cache_data;
      L2_D.info.busy_lines = zeros();
      L2_D.info.num_set = L2_D.info.mcs / unsigned(L2_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_D.info.num_set = L2_D.info.mcs;
      };
      // L2_D.info.num_set = number_set;
      // unsigned(L2_D.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = Cache_Rep_RR;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = Cache_Rep_RR;
        L2_D.info.rep_pol = Cache_Rep_RR;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
        L1_I.info.rep_pol = NULL;
        L1_D.info.rep_pol = NULL;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
        print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    } else if (level_types == 5) then { // L1_I + L1_D + L2_I + L2_D

      L1_I.info.cache_type = Cache_inst;
      L1_I.info.busy_lines = zeros();
      L1_I.info.num_set = L1_I.info.mcs / unsigned(L1_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_I.info.num_set = L1_I.info.mcs;
      };
      // L1_I.info.num_set = number_set;
      // unsigned(L1_I.info.num_lines_set) = linesperset;
      L1_D.info.cache_type = Cache_data;
      L1_D.info.busy_lines = zeros();
      L1_D.info.num_set = L1_D.info.mcs / unsigned(L1_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L1_D.info.num_set = L1_D.info.mcs;
      };
      // L1_D.info.num_set = number_set;
      // unsigned(L1_D.info.num_lines_set) = linesperset;
      L2_I.info.cache_type = Cache_inst;
      L2_I.info.busy_lines = zeros();
      L2_I.info.num_set = L2_I.info.mcs / unsigned(L2_I.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_I.info.num_set = L2_I.info.mcs;
      };
      // L2_I.info.num_set = number_set;
      // unsigned(L2_I.info.num_lines_set) = linesperset;
      L2_D.info.cache_type = Cache_data;
      L2_D.info.busy_lines = zeros();
      L2_D.info.num_set = L2_D.info.mcs / unsigned(L2_D.info.num_lines_set);
      if (DirectLocation == 1) then {
        L2_D.info.num_set = L2_D.info.mcs;
      };
      // L2_D.info.num_set = number_set;
      // unsigned(L2_D.info.num_lines_set) = linesperset;

      if (unsigned(crepc) == 0) then {
        // print_endline("Cache policy Random");
        L1.info.rep_pol = NULL;
        L1_I.info.rep_pol = Cache_Rep_RR;
        L1_D.info.rep_pol = Cache_Rep_RR;
        L2.info.rep_pol = NULL;
        L2_I.info.rep_pol = Cache_Rep_RR;
        L2_D.info.rep_pol = Cache_Rep_RR;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        // print_endline("Configuration: Rep_policy <- FIFO");
        print_endline("Configuration: Rep_policy <- Random");
      } else {
        // print_endline("Cache policy FIFO");
        L1.info.rep_pol =   NULL;
        L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2.info.rep_pol =   NULL;
        L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
        L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;

        print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
        print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);

        print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
        print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);

        print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
        print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);

        print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
        print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

        print_endline("Configuration: Rep_policy <- FIFO");
        // print_endline("Configuration: Rep_policy <- Random");
      };

    };
  }


  val replace_cache : forall 'n, 0 <= 'n < 2048. (cache_mem_type, cache_level, xlenbits, int('n)) -> int

  function replace_cache(ct, cl, addr, init_line) = {

    // 1º Mirar la politica de reemplazo
    // 2º Si es random hacer un random de que elemento de la lista reemplazar
    // 3º Si es un valor modificado, escribir el valor en memoria
    // 4º Reemplazar el bloque de cache con el argumento

      if (L1_I.info.rep_pol == Cache_Rep_RR | L1_D.info.rep_pol == Cache_Rep_RR | L1.info.rep_pol == Cache_Rep_RR | L2.info.rep_pol == Cache_Rep_RR | L2_I.info.rep_pol == Cache_Rep_RR | L2_D.info.rep_pol == Cache_Rep_RR) then {
        if (ct == Cache_inst) then {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L1_I.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L1_I.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L1_I.mem_L1[index_rep].Cache_control_bits = zeros();
            L1_I.mem_L1[index_rep].Cache_addr = zeros();
            // L1_I.mem_L1[index_rep].Cache_tag = zeros(); //  addr[31..14];
            // L1_I.mem_L1[index_rep].Cache_index = zeros(); //  addr[13..4];
            // L1_I.mem_L1[index_rep].Cache_offset = zeros(); //  addr[13..4];
            index_rep
          } else {
            L1_I.mem_L1[init_line].Cache_control_bits = zeros();
            L1_I.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }

        } else if (ct == Cache_data) then {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L1_D.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L1_D.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L1_D.mem_L1[index_rep].Cache_control_bits = zeros();
            L1_D.mem_L1[index_rep].Cache_addr = zeros();
            
            index_rep
          } else {
            L1_D.mem_L1[init_line].Cache_control_bits = zeros();
            L1_D.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }
          
        } else if (ct == Cache_all & cl == LL1) then {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L1.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L1.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L1.mem_L1[index_rep].Cache_control_bits = zeros();
            L1.mem_L1[index_rep].Cache_addr = zeros();
            index_rep
          }else {
            L1.mem_L1[init_line].Cache_control_bits = zeros();
            L1.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }

        } else if (ct == Cache_inst & cl == LL2) then {
          if (DirectLocation == 0) then {
           
            let index_rep : int = unsigned(randomindex(L2_I.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L2_I.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L2_I.mem_L1[index_rep].Cache_control_bits = zeros();
            L2_I.mem_L1[index_rep].Cache_addr = zeros();
            index_rep 
          }else {
            L2_I.mem_L1[init_line].Cache_control_bits = zeros();
            L2_I.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }
        } else if (ct == Cache_data & cl == LL2) then {
          if (DirectLocation == 0) then {

            let index_rep : int = unsigned(randomindex(L2_D.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L2_D.info.mcs );
            // Actualizamos el vector de control y el tag y el index
            L2_D.mem_L1[index_rep].Cache_control_bits = zeros();
            L2_D.mem_L1[index_rep].Cache_addr = zeros();
            index_rep
          }else {
            L2_D.mem_L1[init_line].Cache_control_bits = zeros();
            L2_D.mem_L1[init_line].Cache_addr = zeros();
            init_line
          }
        } else {
          if (DirectLocation == 0) then {
            let index_rep : int = unsigned(randomindex(L2.info.num_lines_set)) + init_line;
            assert(0<= index_rep & index_rep < 2048 & index_rep < L2.info.mcs);
            // Actualizamos el vector de control y el tag y el index
            L2.mem_L2[index_rep].Cache_control_bits = zeros();
            L2.mem_L2[index_rep].Cache_addr = zeros();
            index_rep 
          } else {
            L2.mem_L2[init_line].Cache_control_bits = zeros();
            L2.mem_L2[init_line].Cache_addr = zeros();
            init_line
          }
        }
      } else { // Es el caso de FIFO
        if (ct == Cache_inst & cl == LL1) then {
          if (DirectLocation == 0) then {
            if (unsigned(L1_I.info.repl_lines) >= L1_I.info.mcs) then {
              L1_I.info.repl_lines = zeros();
            };
            L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_addr = zeros();
            L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_control_bits = zeros();
            L1_I.info.repl_lines = L1_I.info.repl_lines + 1;
            unsigned(L1_I.info.repl_lines - 1)
          } else {
            L1_I.mem_L1[init_line].Cache_addr = zeros();
            L1_I.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }
        } else if (ct == Cache_data & cl == LL1) then {

          if (DirectLocation == 0) then {
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_data_block = zeros();
            if (unsigned(L1_D.info.repl_lines) >= L1_D.info.mcs) then {
              L1_D.info.repl_lines = zeros();
            };
            L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_addr = zeros();
            L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_control_bits = zeros();
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_tag = zeros();
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_index = zeros();
            // L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_offset = zeros();
            L1_D.info.repl_lines = L1_D.info.repl_lines + 1;
            print_int("repl_lines L1_D: ", unsigned(L1_D.info.repl_lines - 1));
            unsigned(L1_D.info.repl_lines - 1)
          } else {
            L1_D.mem_L1[init_line].Cache_addr = zeros();
            L1_D.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }

          
        } else if (ct == Cache_all & cl == LL1) then {
          if (DirectLocation == 0) then {

            if (unsigned(L1.info.repl_lines) >= L1.info.mcs) then {
              L1.info.repl_lines = zeros();
            };
            L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_addr = zeros();
            L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_control_bits = zeros();
            L1.info.repl_lines = L1.info.repl_lines + 1;
            print_int("repl_lines L1: ", unsigned(L1.info.repl_lines - 1));
            unsigned(L1.info.repl_lines - 1)
          } else {

            L1.mem_L1[init_line].Cache_addr = zeros();
            L1.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }

        } else if (ct == Cache_inst & cl == LL2) then {
          if (DirectLocation == 0) then {

            
            if (unsigned(L2_I.info.repl_lines) >= L2_I.info.mcs) then {
              L2_I.info.repl_lines = zeros();
            };
            L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_addr = zeros();
            L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_control_bits = zeros();
            L2_I.info.repl_lines = L2_I.info.repl_lines + 1;
            print_int("repl_lines L2_I: ", unsigned(L2_I.info.repl_lines - 1));
            unsigned(L2_I.info.repl_lines - 1)
          } else {
            L2_I.mem_L1[init_line].Cache_addr = zeros();
            L2_I.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }
        } else if (ct == Cache_data & cl == LL2) then {
          if (DirectLocation == 0) then {

            if (unsigned(L2_D.info.repl_lines) >= L2_D.info.mcs) then {
              L2_D.info.repl_lines = zeros();
            };
            L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_addr = zeros();
            L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_control_bits = zeros();
            L2_D.info.repl_lines = L2_D.info.repl_lines + 1;
            print_int("repl_lines L2_D: ", unsigned(L2_D.info.repl_lines - 1));
            unsigned(L2_D.info.repl_lines - 1)
          } else {
            L2_D.mem_L1[init_line].Cache_addr = zeros();
            L2_D.mem_L1[init_line].Cache_control_bits = zeros();
            init_line
          }

        } else {
          if (DirectLocation == 0) then {

            if (unsigned(L2.info.repl_lines) >= L2.info.mcs) then {
              L2.info.repl_lines = zeros();
            };
            L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_addr = zeros();
            L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_control_bits = zeros();
            L2.info.repl_lines = L2.info.repl_lines + 1;
            print_int("repl_lines L2: ", unsigned(L2.info.repl_lines - 1));
            unsigned(L2.info.repl_lines - 1)            
          } else {
            L2.mem_L2[init_line].Cache_addr = zeros();
            L2.mem_L2[init_line].Cache_control_bits = zeros();
            init_line
          }
        }
      }
  }


  val write_cache : forall 'n, 0 < 'n <= 16. (cache_mem_type, cache_level, xlenbits, int('n), bits('n * 8), bool) -> bool

  function write_cache(ct, cl, addr, width, value, new_line) = {

    var found : bool = false;
    var written : bool = false;
    let maxbs : int = L1_I.info.mcb;

    if(new_line) then {
      var lines_to_store_128 : bits(128) = zeros();
      var lines_to_store_64 : bits(128) = zeros();
      var lines_to_store_32 : bits(32) = zeros();

      if (ct == Cache_inst & cl == LL1) then {
        let tah = (L1_I.info.offset + L1_I.info.index + L1_I.info.tag - 1);
        let tal = (L1_I.info.offset + L1_I.info.index);

        let inh = L1_I.info.offset + (L1_I.info.index - 1);
        let inl = (L1_I.info.offset);

        let tag_s : int = L1_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L1_I.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L1_I.info.num_lines_set);
            let lines : int = init + unsigned(L1_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_I.mem_L1[i].Cache_control_bits = 0b00001;
                L1_I.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
              if(L1_I.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_I.mem_L1[id_set].Cache_control_bits = 0b00001;
                L1_I.mem_L1[id_set].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L1_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L1_I.mem_L1[i].Cache_control_bits = 0b00001;
              L1_I.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(64 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);
          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };

      } else if (ct == Cache_data & cl == LL1) then {
        let tah = (L1_D.info.offset + L1_D.info.index + L1_D.info.tag - 1);
        let tal = (L1_D.info.offset + L1_D.info.index);

        let inh = L1_D.info.offset + (L1_D.info.index - 1);
        let inl = (L1_D.info.offset);

        let tag_s : int = L1_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];
          let id_set : int = unsigned(c_index) % L1_D.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L1_D.info.num_lines_set);
            let lines : int = init + unsigned(L1_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_D.mem_L1[i].Cache_control_bits = 0b00001;
                L1_D.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
          
              }
            };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, init);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
          } else {

            if(L1_D.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1_D.mem_L1[id_set].Cache_control_bits = 0b00001;
                L1_D.mem_L1[id_set].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
          
              };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };

          };

        } else {
          let lines : int = unsigned(L1_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L1_D.mem_L1[i].Cache_control_bits = 0b00001;
              L1_D.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(64 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((addr_p)) ^ ")");
        
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

      } else if (ct == Cache_all & cl == LL1) then {
        let tah = (L1.info.offset + L1.info.index + L1.info.tag - 1);
        let tal = L1.info.offset + L1.info.index;

        let inh = L1.info.offset + (L1.info.index - 1);
        let inl = (L1.info.offset);

        let tag_s : int = L1.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L1.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L1.info.num_lines_set);
            assert(0 <= init & init < 2048);
            let lines : int = init + unsigned(L1.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1.mem_L1[i].Cache_control_bits = 0b00001;
                L1.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };

            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
              if(L1.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L1.mem_L1[id_set].Cache_control_bits = 0b00001;
                L1.mem_L1[id_set].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              };


              if (written == false) then {
                let index : int = replace_cache(ct, cl, addr, id_set);
                written = write_cache(ct, cl, addr, width, value, new_line);

              };
          };

        } else {
          let lines : int = unsigned(L1.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L1.mem_L1[i].Cache_control_bits = 0b00001;
              L1.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(64 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };

      } else if (ct == Cache_inst & cl == LL2) then {
        let tah = (L2_I.info.offset + L2_I.info.index + L2_I.info.tag - 1);
        let tal = (L2_I.info.offset + L2_I.info.index);

        let inh = L2_I.info.offset + (L2_I.info.index - 1);
        let inl = (L2_I.info.offset);

        let tag_s : int = L2_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L2_I.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
          let init : int = id_set * unsigned(L2_I.info.num_lines_set);
            let lines : int = init + unsigned(L2_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L2_I.mem_L1[i].Cache_control_bits = 0b00001;
                L2_I.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);
            };
          } else {
            if(L2_I.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_I.mem_L1[id_set].Cache_control_bits = 0b00001;
              L2_I.mem_L1[id_set].Cache_addr = addr;
              assert((tag_s + ind_s) < 64);
              print_reg("["^ dec_str(id_set) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          
          };

        } else {
          let lines : int = unsigned(L2_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_I.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_I.mem_L1[i].Cache_control_bits = 0b00001;
              L2_I.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(64 - tag_s);
              print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

      } else if (ct == Cache_data & cl == LL2) then {
        let tah = (L2_D.info.offset + L2_D.info.index + L2_D.info.tag - 1);
        let tal = (L2_D.info.offset + L2_D.info.index);

        let inh = L2_D.info.offset + (L2_D.info.index - 1);
        let inl = (L2_D.info.offset);

        let tag_s : int = L2_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];
          let id_set : int = unsigned(c_index) % L2_D.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
            let init : int = id_set * unsigned(L2_D.info.num_lines_set);

            let lines : int = init + unsigned(L2_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L2_D.mem_L1[i].Cache_control_bits = 0b00001;
                L2_D.mem_L1[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
            if(L2_D.mem_L1[id_set].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_D.mem_L1[id_set].Cache_control_bits = 0b00001;
              L2_D.mem_L1[id_set].Cache_addr = addr;
              assert((tag_s + ind_s) < 64);
              print_reg("["^ dec_str(id_set) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_D.mem_L1[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2_D.mem_L1[i].Cache_control_bits = 0b00001;
              L2_D.mem_L1[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(64 - tag_s);
              print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };


      } else { // Si no es ninguna de las dos es una caché L2
        let tah = (L2.info.offset + L2.info.index + L2.info.tag - 1);
        let tal = (L2.info.offset + L2.info.index);

        let inh = L2.info.offset + (L2.info.index - 1);
        let inl = (L2.info.offset);

        let tag_s : int = L2.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
        let c_tag = addr[tah..tal];
        let ind_s : int = L2.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L2.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
            let init : int = id_set * unsigned(L2.info.num_lines_set);

            let lines : int = init + unsigned(L2.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2.mem_L2[i].Cache_control_bits == 0b00000 & written == false) then {
                written = true;
                L2.mem_L2[i].Cache_control_bits = 0b00001;
                L2.mem_L2[i].Cache_addr = addr;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {
            if(L2.mem_L2[id_set].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2.mem_L2[id_set].Cache_control_bits = 0b00001;
              L2.mem_L2[id_set].Cache_addr = addr;
              assert((tag_s + ind_s) < 64);
              print_reg("["^ dec_str(id_set) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
            };

            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L2.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2.mem_L2[i].Cache_control_bits == 0b00000 & written == false) then {
              written = true;
              L2.mem_L2[i].Cache_control_bits = 0b00001;
              L2.mem_L2[i].Cache_addr = addr;
              let addr_p = c_tag @ zeros(64 - tag_s);
              print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };

        // if (written == false) then {
        //   let index : int = replace_cache(ct, cl, addr);
        //   written = write_cache(ct, cl, addr, width, value, new_line);

        // };
      };


    } else { // cuando no se quiere escribir una nueva linea solo un elemento

      // 1) Busca la linea de caché
      // 1.1) Si existe la línea Ir a 3
      // 1.2) No existe la linea Ir a 2 y notificar cache miss
      // 2) Escribir nueva linea caché return true
      // 3) Modificar el valor de la linea cache.

      if (cl == LL1) then { // Nivel 1: (Insn + Datos) o Unificada
        if (ct == Cache_data) then {
          
        let tah = (L1_D.info.offset + L1_D.info.index + L1_D.info.tag - 1);
        let tal = (L1_D.info.offset + L1_D.info.index);

        let inh = L1_D.info.offset + (L1_D.info.index - 1);
        let inl = (L1_D.info.offset);

        let tag_s : int = L1_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];
          let id_set : int = unsigned(c_index) %  L1_D.info.num_set;
          assert(0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then {
            let init : int = id_set * unsigned(L1_D.info.num_lines_set);

            let lines : int = init + unsigned(L1_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };
            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, init);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          } else {

            if(L1_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
              written = true;
              found = true;
              assert((tag_s + ind_s) < 64);
              print_reg("["^ dec_str(id_set) ^"] L1_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
            };

            if (written == false) then {
              let index : int = replace_cache(ct, cl, addr, id_set);
              written = write_cache(ct, cl, addr, width, value, new_line);

            };
          };

        } else {
          let lines : int = unsigned(L1_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
              written = true;
              found = true;
              let addr_p = c_tag @ zeros(64 - tag_s);
              print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((addr_p)) ^ ")");
            }
          };
          if (written == false) then {
            let index : int = replace_cache(ct, cl, addr, 0);
            written = write_cache(ct, cl, addr, width, value, new_line);

          };
        };


          if (found == false) then { // Observamos si se encuentra en L2
            print_endline("Write Cache L1_D miss");
            if (level_types == 3) then {
              written = write_cache(Cache_all, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_data, LL1, addr, width, value, true);
                written = write_cache(Cache_data, LL1, addr, width, value, false);
                written = write_cache(Cache_all, LL2, addr, width, value, false);
              };
            } else if (level_types == 5) then {
              written = write_cache(Cache_data, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_data, LL1, addr, width, value, true);
                written = write_cache(Cache_data, LL1, addr, width, value, false);
                written = write_cache(Cache_data, LL2, addr, width, value, false);
              };
            } else if {level_types == 1} then {
              written = write_cache(Cache_data, LL1, addr, width, value, true);
              written = write_cache(Cache_data, LL1, addr, width, value, false);
            };
          };
        } else if (ct == Cache_inst) then {
          let tah = (L1_I.info.offset + L1_I.info.index + L1_I.info.tag - 1);
          let tal = (L1_I.info.offset + L1_I.info.index);

          let inh = L1_I.info.offset + (L1_I.info.index - 1);
          let inl = (L1_I.info.offset);

          let tag_s : int = L1_I.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
          let c_tag = addr[tah..tal];
          let ind_s : int = L1_I.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L1_I.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L1_I.info.num_lines_set);
              let lines : int = init + unsigned(L1_I.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 64);
                  print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
                }
              };
            } else {

              if(L1_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L1_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              };
            };

          } else {
            let lines : int = unsigned(L1_I.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(64 - tag_s);
                print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L1_I miss");
            if (level_types == 3) then {
              written = write_cache(Cache_all, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_inst, LL1, addr, width, value, true);
                written = write_cache(Cache_inst, LL1, addr, width, value, false);
                written = write_cache(Cache_all, LL2, addr, width, value, false);
              };
            } else if (level_types == 5) then {
              written = write_cache(Cache_inst, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_inst, LL1, addr, width, value, true);
                written = write_cache(Cache_inst, LL1, addr, width, value, false);
                written = write_cache(Cache_inst, LL2, addr, width, value, false);
              };
            } else if {level_types == 1} then {
              written = write_cache(Cache_inst, LL1, addr, width, value, true);
              written = write_cache(Cache_inst, LL1, addr, width, value, false);
            };
          }
        }
        else {
          let tah = (L1.info.offset + L1.info.index + L1.info.tag - 1);
          let tal = (L1.info.offset + L1.info.index);

          let inh = L1.info.offset + (L1.info.index - 1);
          let inl = (L1.info.offset);

          let tag_s : int = L1.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
          let c_tag = addr[tah..tal];
          let ind_s : int = L1.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L1.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L1.info.num_lines_set);
              let lines : int = init + unsigned(L1.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 64);
                  print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L1.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L1:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };

          } else {
            let lines : int = unsigned(L1.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(64 - tag_s);
                print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L1 miss");
            if (level_types == 2) then {
              written = write_cache(Cache_all, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_all, LL1, addr, width, value, true);
                written = write_cache(Cache_all, LL1, addr, width, value, false);
                written = write_cache(Cache_all, LL2, addr, width, value, false);
              };
            } else if (level_types == 4) then {
              written = write_cache(Cache_inst, LL2, addr, width, value, false);
              if (written == false) then {
                written = write_cache(Cache_all, LL1, addr, width, value, true);
                written = write_cache(Cache_all, LL1, addr, width, value, false);
                written = write_cache(Cache_inst, LL2, addr, width, value, false);
              };
            } else if {level_types == 0} then {
              written = write_cache(Cache_all, LL1, addr, width, value, true);
              written = write_cache(Cache_all, LL1, addr, width, value, false);
            };
          }
        };
      } else { // Cache de nivel 2
        if (ct ==  Cache_inst) then {
          let tah = (L2_I.info.offset + L2_I.info.index + L2_I.info.tag - 1);
          let tal = (L2_I.info.offset + L2_I.info.index);

          let inh = L2_I.info.offset + (L2_I.info.index - 1);
          let inl = (L2_I.info.offset);

          let tag_s : int = L2_I.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
          let c_tag = addr[tah..tal];
          let ind_s : int = L2_I.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L2_I.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L2_I.info.num_lines_set);
              let lines : int = init + unsigned(L2_I.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 64);
                  print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L2_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L2_I:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };

          } else {
            let lines : int = unsigned(L2_I.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(64 - tag_s);
                print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L2_I miss");

            written = write_cache(Cache_inst, LL2, addr, width, value, true);
            written = write_cache(Cache_inst, LL2, addr, width, value, false);
            written = false;
          }
        } else if (ct == Cache_data) then {
          let tah = (L2_D.info.offset + L2_D.info.index + L2_D.info.tag - 1);
          let tal = (L2_D.info.offset + L2_D.info.index);

          let inh = L2_D.info.offset + (L2_D.info.index - 1);
          let inl = (L2_D.info.offset);

          let tag_s : int = L2_D.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
          let c_tag = addr[tah..tal];
          let ind_s : int = L2_D.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L2_D.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {
  
              let init : int = id_set * unsigned(L2_D.info.num_lines_set);
              let lines : int = init + unsigned(L2_D.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 64);
                  print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L2_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L2_D:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            }; 

          } else {
            let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(64 - tag_s);
                print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };
          if(found == false) then {
            print_endline("Write Cache L2_D miss");
            written = write_cache(Cache_data, LL2, addr, width, value, true);
            written = write_cache(Cache_data, LL2, addr, width, value, false);
            written = false;
          }

        } else {
          let tah = (L2.info.offset + L2.info.index + L2.info.tag - 1);
          let tal = (L2.info.offset + L2.info.index);

          let inh = L2.info.offset + (L2.info.index - 1);
          let inl = (L2.info.offset);

          let tag_s : int = L2.info.tag;
          assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64) & tag_s < 64);
          let c_tag = addr[tah..tal];
          let ind_s : int = L2.info.index;
          if (ind_s != 0) then {
            assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
            let c_index = addr[inh..inl];
            let id_set : int = unsigned(c_index) %  L2.info.num_set;
            assert(0 <= id_set & id_set < 2048);
            if (DirectLocation == 0) then {

              let init : int = id_set * unsigned(L2.info.num_lines_set);
              let lines : int = init + unsigned(L2.info.num_lines_set) - 1;
              assert(lines >= init & init >= 0 & lines < 2048);
              foreach(i from init to lines) {
                if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                  written = true;
                  found = true;
                  assert((tag_s + ind_s) < 64);
                  print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
                }
              }
            } else {

              if(L2.mem_L2[id_set].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                assert((tag_s + ind_s) < 64);
                print_reg("["^ dec_str(id_set) ^"] L2:("^ BitStr((c_tag @ c_index @ zeros(64 - (tag_s + ind_s)))) ^ ") ");
              }
            };

          } else {
            let lines : int = unsigned(L2.info.num_lines_set) - 1;
            assert(lines >= 0 & lines < 2048);
            foreach(i from 0 to lines) {
              if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & written == false) then {
                written = true;
                found = true;
                let addr_p = c_tag @ zeros(64 - tag_s);
                print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((addr_p)) ^ ")");
              }
            }
          };

          if(found == false) then {
            print_endline("Write Cache L2 miss");
            written = write_cache(Cache_all, LL2, addr, width, value, true);
            written = write_cache(Cache_all, LL2, addr, width, value, false);
            written = false;
          }

        }



      };
    };
    written
  }

  // hacer un prewrite de la cache


  val read_cache : forall 'n, 0 < 'n <= 4096. /*16.*/ (cache_mem_type, cache_level, xlenbits, int('n)) ->  bool

  function read_cache(ct, cl, addr, width) = {
    // Descomponemos la direccion en los 3 elementos a buscar
    var result    : bits(8 * 'n) = zeros();
    var set : int = 0;

    var found : bool = false;
    // var can_continue = false;
    var width_to_read : int = 0;

    // Primero se prueba que el width corresponde con el tamaño de cache
    if (cl == LL1) then {
      if (ct == Cache_data) then {
        if (L1_D.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L1_D.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L1_D.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else if (ct == Cache_inst) then {
        if (L1_I.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L1_I.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L1_I.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else {
        if (L1.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L1.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L1.info.mcb / 8)), new_width);
        } else width_to_read = width;

      }
    } else {
      if (ct == Cache_data) then {
        if (L2_D.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L2_D.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L2_D.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else if (ct == Cache_inst) then {
        if (L2_I.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L2_I.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L2_I.info.mcb / 8)), new_width);
        } else width_to_read = width;

      } else {
        if (L2.info.mcb < (width * 8)) then {
          // llamar a read_cache
          width_to_read = L2.info.mcb / 8;
          let new_width = width - width_to_read;

          assert(0 <= width_to_read & width_to_read < width & 0 < width & new_width > 0 & new_width <= 4096);
          found = read_cache(ct, cl, (addr + (L2.info.mcb / 8)), new_width);
        } else width_to_read = width;

      }
    };

    let new_width = width_to_read;
    assert(0 < new_width & new_width <= 4096);
    if (cl  == LL1) then { // Si es de nivel 1 buscamos entre datos + instrucciones o una cache unificada
      if(ct == Cache_data) then {

        let tah = (L1_D.info.offset + L1_D.info.index + L1_D.info.tag - 1);
        let tal = (L1_D.info.offset + L1_D.info.index);

        let inh = L1_D.info.offset + (L1_D.info.index - 1);
        let inl = (L1_D.info.offset);

        let tag_s : int = L1_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64));
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L1_D.info.num_set;
          
          assert( 0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L1_D.info.num_lines_set);
            let lines : int = init + unsigned(L1_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_D.mem_L1[i].Cache_control_bits != 0b00000) then {
                found = true;
                print_endline("Cache L1_D hit");
              }
            }
          } else {

              if(L1_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L1_D.mem_L1[id_set].Cache_control_bits != 0b00000) then {
                found = true;
                print_endline("Cache L1_D hit");
              }
          };

        } else {
          let lines : int = unsigned(L1_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_D.mem_L1[i].Cache_control_bits != 0b00000) then {
              found = true;
              print_endline("Cache L1_D hit");
            }
          }
        };

        if (found == false) then {
          print_reg("Cache L1_D miss on: " ^ BitStr(addr));
          // Mirar que cache es
          if (level_types == 1) then {
            let lines_to_store : bits (128) = zeros();
            found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
            // Devolver el valor escrito
          } else if (level_types == 5) then {

            // assert(0 < width_to_read & width_to_read <= 4096);
            found = read_cache(Cache_data, LL2, addr, new_width);
          };
        };

      } else if (ct == Cache_inst) then {
        let tah = (L1_I.info.offset + L1_I.info.index + L1_I.info.tag - 1);
        let tal = (L1_I.info.offset + L1_I.info.index);

        let inh = L1_I.info.offset + (L1_I.info.index - 1);
        let inl = (L1_I.info.offset);

        let tag_s : int = L1_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64));
        let c_tag = addr[tah..tal];
        let ind_s : int = L1_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L1_I.info.num_set;
          // print_int("Id_set:", id_set);
          // print_reg("index: " ^BitStr(c_index));
          // print_int("Numbser:", L1_I.info.num_set);
          assert( 0 <= id_set & id_set < 2048);

          if (DirectLocation == 0) then  {
            let init : int = id_set * unsigned(L1_I.info.num_lines_set);

            let lines : int = init + unsigned(L1_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_I.mem_L1[i].Cache_control_bits != 0b00000) then {
                found = true;
                print_endline("Cache L1_I hit");
              }
            }
          } else {

            if(L1_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L1_I.mem_L1[id_set].Cache_control_bits != 0b00000) then {
              found = true;
              print_endline("Cache L1_I hit");
            }
          };

        } else {
          let lines : int = unsigned(L1_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1_I.mem_L1[i].Cache_control_bits != 0b00000) then {
              found = true;
              print_endline("Cache L1_I hit");
            }
          }
        };

        if (found == false) then {
          print_endline("Cache L1_I miss");
          // Si no se encuentra se busca en L2
          if (level_types == 1) then {
            if ( L1_I.info.mcb == 128 ) then {
              let lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
            } else if ( L1.info.mcb == 64 ) then {
              let lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
            } else if ( L1.info.mcb == 32 ) then {
              let lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
            };
          } else if (level_types == 3) then {
            found = read_cache(Cache_all, LL2, addr, new_width);
          } else if (level_types == 5) then {
            found = read_cache(Cache_inst, LL2, addr, new_width);
          };
        };

      } else { // Buscar en toda la cache L1
        let tah = L1.info.offset + L1.info.index + L1.info.tag - 1;
        let tal = L1.info.offset + L1.info.index;

        let inh = L1.info.offset + (L1.info.index - 1);
        let inl = L1.info.offset;

        let tag_s : int = L1.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64));
        let c_tag = addr[tah..tal];
        let ind_s : int = L1.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) % L1.info.num_set;
          print_int("id_set: ", id_set);
          assert( 0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then  {
            let init : int = id_set * unsigned(L1.info.num_lines_set);
            assert( 0 <= init & init < 2048);

            let lines : int = init + unsigned(L1.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              
              if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1.mem_L1[i].Cache_control_bits != 0b00000) then { //

                found = true;
                if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L1 hit inst") else print_reg("Cache L1 hit data on: " ^ BitStr(addr));
              }
            }
          } else {
            // print_reg("Cache_tag a buscar: " ^BitStr(c_tag));
            // print_reg("Cache_tag en memoria: " ^BitStr(L1.mem_L1[id_set].Cache_addr[tah..tal]));

            if(L1.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & L1.mem_L1[id_set].Cache_control_bits != 0b00000 & found == false) then { //
              found = true;
              if (PC == addr | (PC + 2) == addr) then print_endline("Cache L1 hit inst") else print_reg("Cache L1 hit data on: " ^ BitStr(addr));
            }
          };

        } else {
          let lines : int = unsigned(L1.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L1.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L1.mem_L1[i].Cache_control_bits != 0b00000) then {
              found = true;
              if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L1 hit inst") else print_reg("Cache L1 hit data on: " ^ BitStr(addr));
            }
          }
        };

        if (found == false) then {
          // print_endline("Cache L1 miss");
          if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L1 miss inst") else print_reg("Cache L1 miss data on: " ^ BitStr(addr));
          if (level_types == 0) then {
            if (L1.info.mcb == 128) then {
              let lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
            } else if (L1.info.mcb == 64) then {
              let lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
            } else if (L1.info.mcb == 32) then {
              let lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
            };

          } else if (level_types == 2) then {
            found = read_cache(Cache_all, LL2, addr, new_width);
          } else if (level_types == 4) then {
            if (PC == addr | (PC + 2) == addr) then {
              found = read_cache(Cache_inst, LL2, addr, new_width);
            } else {
              found = read_cache(Cache_data, LL2, addr, new_width);
            }
          }
        };

      };

    } else { // Buscamos en L2
      if (ct == Cache_data) then {
        let tah = (L2_D.info.offset + L2_D.info.index + L2_D.info.tag - 1);
        let tal = (L2_D.info.offset + L2_D.info.index);

        let inh = L2_D.info.offset + (L2_D.info.index - 1);
        let inl = (L2_D.info.offset);

        let tag_s : int = L2_D.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64));
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_D.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L2_D.info.num_set;
          assert( 0 <= id_set & id_set < 2048);
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L2_D.info.num_lines_set);
            let lines : int = init + unsigned(L2_D.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_D.mem_L1[i].Cache_control_bits != 0b00000) then {
                found = true;
                print_endline("Cache L2_D hit");
              }
            }
          } else {

            if(L2_D.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L2_D.mem_L1[id_set].Cache_control_bits != 0b00000) then {
              found = true;
              print_endline("Cache L2_D hit");
            }
          };

        } else {
          let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_D.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_D.mem_L1[i].Cache_control_bits != 0b00000) then {
              found = true;
              print_endline("Cache L2_D hit");
            }
          }
        };

        if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                  // solicitamos a memoria un bloque entero para L1
                                  // y tambien lo escribimos en L2
          print_reg("Cache L2_D miss on: " ^ BitStr(addr));

          if (level_types == 4) then {
            if (L2_D.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
            } else if (L2_D.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
            } else if (L2_D.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
            };
          } else if (level_types == 5) then {
            if (L1_D.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
            } else if (L1_D.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_data, LL1, addr, 8, lines_to_store, true);
            } else if (L1_D.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_data, LL1, addr, 4, lines_to_store, true);
            };
          };
          if (L2_D.info.mcb == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_data,LL2,addr, 16, lines_to_store, true);
          } else if (L2_D.info.mcb == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_data,LL2,addr, 8, lines_to_store, true);
          } else if (L2_D.info.mcb == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_data,LL2,addr, 4, lines_to_store, true);
          };

        }

      } else if (ct == Cache_inst) then {
        let tah = (L2_I.info.offset + L2_I.info.index + L2_I.info.tag - 1);
        let tal = (L2_I.info.offset + L2_I.info.index);

        let inh = L2_I.info.offset + (L2_I.info.index - 1);
        let inl = (L2_I.info.offset);

        let tag_s : int = L2_I.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64));
        let c_tag = addr[tah..tal];
        let ind_s : int = L2_I.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L2_I.info.num_set;
          assert( 0 <= id_set & id_set < 2048);
          
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L2_I.info.num_lines_set);
            let lines : int = init + unsigned(L2_I.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_I.mem_L1[i].Cache_control_bits != 0b00000) then {
                found = true;
                print_endline("Cache L2_I hit");
              }
            }
          } else {

            if(L2_I.mem_L1[id_set].Cache_addr[tah..tal] == c_tag & found == false & L2_I.mem_L1[id_set].Cache_control_bits != 0b00000) then {
              found = true;
              print_endline("Cache L2_I hit");
            }
          };

        } else {
          let lines : int = unsigned(L2_I.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2_I.mem_L1[i].Cache_addr[tah..tal] == c_tag & found == false & L2_I.mem_L1[i].Cache_control_bits != 0b00000) then {
              found = true;
              print_endline("Cache L2_I hit");
            }
          }
        };


        if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                  // solicitamos a memoria un bloque entero para L1
                                  // y tambien lo escribimos en L2
          print_endline("Cache L2_I miss");
          // Si falla en L2, miramos si la direccion es relativa al pc o es relativa a memoria y leemos


          if (level_types == 4) then {
            if (L1.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
            } else if (L1.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
            } else if (L1.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
            };

          } else if (level_types == 5) then {
            if (L1_I.info.mcb == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
            } else if (L1_I.info.mcb == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
            } else if (L1_I.info.mcb == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
            };

          };
          if (L2_I.info.mcb == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_inst,LL2,addr, 16, lines_to_store, true);
          } else if (L2_I.info.mcb == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_inst,LL2,addr, 8, lines_to_store, true);
          } else if (L2_I.info.mcb == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_inst,LL2,addr, 4, lines_to_store, true);
          };


        };

      } else {
        let tah = (L2.info.offset + L2.info.index + L2.info.tag - 1);
        let tal = (L2.info.offset + L2.info.index);

        let inh = L2.info.offset + (L2.info.index - 1);
        let inl = (L2.info.offset);

        let tag_s : int = L2.info.tag;
        assert((tal >= 0) & (tah >= 0) & (tal <= tah) & (tah < 64));
        let c_tag = addr[tah..tal];
        let ind_s : int = L2.info.index;
        if (ind_s != 0) then {
          assert((inl >= 0) & (inh >= 0) & (inl <= inh & inh < 64));
          let c_index = addr[inh..inl];

          let id_set : int = unsigned(c_index) %  L2.info.num_set;
          assert( 0 <= id_set & id_set < 2048);
          
          if (DirectLocation == 0) then  {

            let init : int = id_set * unsigned(L2.info.num_lines_set);
            let lines : int = init + unsigned(L2.info.num_lines_set) - 1;
            assert(lines >= init & init >= 0 & lines < 2048);
            foreach(i from init to lines) {
              if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & found == false & L2.mem_L2[i].Cache_control_bits != 0b00000) then {
                found = true;
                if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 hit inst") else print_endline("Cache L2 hit data");
              }
            }
          } else {
            if(L2.mem_L2[id_set].Cache_addr[tah..tal] == c_tag & found == false & L2.mem_L2[id_set].Cache_control_bits != 0b00000) then {
              found = true;
              if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 hit inst") else print_endline("Cache L2 hit data");
            }
          };

        } else {
          let lines : int = unsigned(L2_D.info.num_lines_set) - 1;
          assert(lines >= 0 & lines < 2048);
          foreach(i from 0 to lines) {
            if(L2.mem_L2[i].Cache_addr[tah..tal] == c_tag & found == false & L2.mem_L2[i].Cache_control_bits != 0b00000) then {
              found = true;
              if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 hit inst") else print_endline("Cache L2 hit data");
            }
          }
        };

        if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                  // solicitamos a memoria un bloque entero para L1
                                  // y tambien lo escribimos en L2
          if (PC == addr | (PC + 2) == addr ) then print_endline("Cache L2 miss inst") else print_endline("Cache L2 miss data");

          // Si falla en L2, miramos si la direccion es relativa al pc o es relativa a memoria y leemos


          if (PC == addr | (PC + 2) == addr) then {
            if (level_types == 2) then { // Significa que L1 es de tipo all
              if (L1.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
              } else if (L1.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
              } else if (L1.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
              };

            } else if (level_types == 3) then {
              if (L1_I.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
              } else if (L1_I.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
              } else if (L1_I.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
              };

            };

          }else {
            if (level_types == 2) then { // Significa que L1 es de tipo all
              if (L1.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
              } else if (L1.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
              } else if (L1.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
              };

            } else if (level_types == 3) then {
              if (L1_D.info.mcb == 128) then {
                var lines_to_store : bits(128) = zeros();
                found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
              } else if (L1_D.info.mcb == 64) then {
                var lines_to_store : bits(64) = zeros();
                found = write_cache(Cache_data, LL1, addr, 8, lines_to_store, true);
              } else if (L1_D.info.mcb == 32) then {
                var lines_to_store : bits(32) = zeros();
                found = write_cache(Cache_data, LL1, addr, 4, lines_to_store, true);
              };
            };
          };
          if (L2.info.mcb == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_all,LL2,addr, 16, lines_to_store, true);
          } else if (L2.info.mcb == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_all,LL2,addr, 8, lines_to_store, true);
          } else if (L2.info.mcb == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_all,LL2,addr, 4, lines_to_store, true);
          };


        };
      };
    };
    found

  }


$endif _RV64S
