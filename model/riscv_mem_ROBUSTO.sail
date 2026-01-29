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
val randomindex = { c: "rand_num" } : bits(16) -> bits(32) 
val crep = { c: "crep" } : unit -> bits(32)
val cache_levels = { c: "which_cache_levels" } : unit -> bits(32)
val cache_sizes = { c: "cache_sizes" } : bits(8) -> bits(32) // (bits(32), bits(32), bits(32), bits(32), bits(32), bits(32))
val lb_sizes = { c: "cache_line_size" } : unit -> bits(32)


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

struct cache_block_L1 = {
  Cache_data_block    : bits(128),
  Cache_tag           : bits(18),
  Cache_index         : bits(10),
  Cache_offset        : bits(4),
  Cache_control_bits  : bits(5),
}

struct cache_block_L2 = {
  Cache_data_block    : bits(128),
  Cache_tag           : bits(18),
  Cache_index         : bits(10),
  Cache_offset        : bits(4),
  Cache_control_bits  : bits(5),
}

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
}

struct cache_info_L1_t = {
  cache_type : cache_mem_type,
  busy_lines : bits(10),
  repl_lines : bits(10), 
  rep_pol    : cache_rep_policy,
  mcs : int, // Maximum cache size
  mcb : int  // Maximum cache block size
}

struct cache_info_L1 = {
  cache_type : cache_mem_type,
  busy_lines : bits(11),
  repl_lines : bits(11), 
  rep_pol    : cache_rep_policy,
  mcs : int, // Maximum cache size
  mcb : int  // Maximum cache block size
}

struct cache_info_L2 = {
  cache_type : cache_mem_type,
  busy_lines : bits(11),
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
      if ((sizeof(xlen) == 32) ) then {
        if ( width == 8 ) then {
          print_mem_C(paddr, double_to_store.high_p,  double_to_store.low_p);
        };
      }
      else {
        print_mem("mem[" ^ BitStr(paddr) ^ "] <- " ^ BitStr(data));
      }
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




val init_cache : unit -> unit
function init_cache () = { // Modificar para inicializar los registros en funcion del nivel de las caches y el numero de lineas por cache y el tamaño de bloque
  var sparams : cache_params = undefined;
  let lbparams : bits(32) = lb_sizes();
  sparams.L1 = cache_sizes(0b00000001);
  sparams.L1_I = cache_sizes(0b00000010);
  sparams.L1_D = cache_sizes(0b00000011);
  sparams.L2 = cache_sizes(0b00000100);
  sparams.L2_I = cache_sizes(0b00000101);
  sparams.L2_D = cache_sizes(0b00000110);
  
  // let kc : xlenbits = cache_levels();
  let crepc : xlenbits = crep();
  cache_block_size = unsigned(lbparams);
  // kind_c = unsigned(kc);

  if (level_types == 0) then { // L1
    L1.info.cache_type = Cache_all;
    L1.info.busy_lines = zeros();
    // L1_I.info.cache_type = Cache_inst;
    // L1_I.info.busy_lines = zeros();
    // L1_D.info.cache_type = Cache_data;
    // L1_D.info.busy_lines = zeros();
    // L2.info.cache_type = Cache_all;
    // L2.info.busy_lines = zeros();
    // L2_I.info.cache_type = Cache_inst;
    // L2_I.info.busy_lines = zeros();
    // L2_D.info.cache_type = Cache_data;
    // L2_D.info.busy_lines = zeros();

    L1.info.mcs = unsigned(sparams.L1);
    L1.info.mcb = unsigned(lbparams);

    L1_I.info.mcs = 0;
    L1_I.info.mcb = unsigned(lbparams);
    
    L1_D.info.mcs = 0;
    L1_D.info.mcb = unsigned(lbparams);
    
    L2.info.mcs = 0;
    L2.info.mcb = unsigned(lbparams);
    
    L2_I.info.mcs = 0;
    L2_I.info.mcb = unsigned(lbparams);
    
    L2_D.info.mcs = 0;
    L2_D.info.mcb = unsigned(lbparams);

    if (unsigned(crepc) == 0) then {
      // print_endline("Cache policy Random");
      L1.info.rep_pol = Cache_Rep_RR;
      // L1_I.info.rep_pol = Cache_Rep_RR;
      // L1_D.info.rep_pol = Cache_Rep_RR;
      // L2.info.rep_pol = Cache_Rep_RR;
      // L2_I.info.rep_pol = Cache_Rep_RR;
      // L2_D.info.rep_pol = Cache_Rep_RR;
      print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      // print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      // print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      // print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      // print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      // print_endline("Configuration: Rep_policy <- FIFO");
      print_endline("Configuration: Rep_policy <- Random");
    } else {
      // print_endline("Cache policy FIFO");
      L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
      // L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
      // L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      // print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      // print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      // print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      // print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      print_endline("Configuration: Rep_policy <- FIFO");
      // print_endline("Configuration: Rep_policy <- Random");
    };
    
  } else if (level_types == 1) then { // L1_I + L1_D
    // L1.info.cache_type = Cache_all;
    // L1.info.busy_lines = zeros();
    L1_I.info.cache_type = Cache_inst;
    L1_I.info.busy_lines = zeros();
    L1_D.info.cache_type = Cache_data;
    L1_D.info.busy_lines = zeros();
    // L2.info.cache_type = Cache_all;
    // L2.info.busy_lines = zeros();
    // L2_I.info.cache_type = Cache_inst;
    // L2_I.info.busy_lines = zeros();
    // L2_D.info.cache_type = Cache_data;
    // L2_D.info.busy_lines = zeros();

    L1.info.mcs = 0;
    L1.info.mcb = unsigned(lbparams);

    L1_I.info.mcs = unsigned(sparams.L1_I);
    L1_I.info.mcb = unsigned(lbparams);
    
    L1_D.info.mcs = unsigned(sparams.L1_D);
    L1_D.info.mcb = unsigned(lbparams);
    
    L2.info.mcs = 0;
    L2.info.mcb = unsigned(lbparams);
    
    L2_I.info.mcs = 0;
    L2_I.info.mcb = unsigned(lbparams);
    
    L2_D.info.mcs = 0;
    L2_D.info.mcb = unsigned(lbparams);
    
    if (unsigned(crepc) == 0) then {
      // print_endline("Cache policy Random");
      // L1.info.rep_pol = Cache_Rep_RR;
      L1_I.info.rep_pol = Cache_Rep_RR;
      L1_D.info.rep_pol = Cache_Rep_RR;
      // L2.info.rep_pol = Cache_Rep_RR;
      // L2_I.info.rep_pol = Cache_Rep_RR;
      // L2_D.info.rep_pol = Cache_Rep_RR;
      // print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      // print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      // print_endline("Configuration: Rep_policy <- FIFO");
      print_endline("Configuration: Rep_policy <- Random");
    } else {
      // print_endline("Cache policy FIFO");
      // L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
      L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
      // L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      // print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      // print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      print_endline("Configuration: Rep_policy <- FIFO");
      // print_endline("Configuration: Rep_policy <- Random");
    };

  } else if (level_types == 2) then { // L1 + L2
    L1.info.cache_type = Cache_all;
    L1.info.busy_lines = zeros();
    // L1_I.info.cache_type = Cache_inst;
    // L1_I.info.busy_lines = zeros();
    // L1_D.info.cache_type = Cache_data;
    // L1_D.info.busy_lines = zeros();
    L2.info.cache_type = Cache_all;
    L2.info.busy_lines = zeros();
    // L2_I.info.cache_type = Cache_inst;
    // L2_I.info.busy_lines = zeros();
    // L2_D.info.cache_type = Cache_data;
    // L2_D.info.busy_lines = zeros();

    L1.info.mcs = unsigned(sparams.L1);
    L1.info.mcb = unsigned(lbparams);

    L1_I.info.mcs = 0;
    L1_I.info.mcb = unsigned(lbparams);
    
    L1_D.info.mcs = 0;
    L1_D.info.mcb = unsigned(lbparams);
    
    L2.info.mcs = unsigned(sparams.L2);
    L2.info.mcb = unsigned(lbparams);
    
    L2_I.info.mcs = 0;
    L2_I.info.mcb = unsigned(lbparams);
    
    L2_D.info.mcs = 0;
    L2_D.info.mcb = unsigned(lbparams);

    if (unsigned(crepc) == 0) then {
      // print_endline("Cache policy Random");
      L1.info.rep_pol = Cache_Rep_RR;
      // L1_I.info.rep_pol = Cache_Rep_RR;
      // L1_D.info.rep_pol = Cache_Rep_RR;
      L2.info.rep_pol = Cache_Rep_RR;
      // L2_I.info.rep_pol = Cache_Rep_RR;
      // L2_D.info.rep_pol = Cache_Rep_RR;
      print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      // print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      // print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      // print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      // print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      // print_endline("Configuration: Rep_policy <- FIFO");
      print_endline("Configuration: Rep_policy <- Random");
    } else {
      // print_endline("Cache policy FIFO");
      L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
      // L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
      // L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      // print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      // print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      // print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      // print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      print_endline("Configuration: Rep_policy <- FIFO");
      // print_endline("Configuration: Rep_policy <- Random");
    };
    
  } else if (level_types == 3) then { // L1_I + L1_D + L2
    // L1.info.cache_type = Cache_all;
    // L1.info.busy_lines = zeros();
    L1_I.info.cache_type = Cache_inst;
    L1_I.info.busy_lines = zeros();
    L1_D.info.cache_type = Cache_data;
    L1_D.info.busy_lines = zeros();
    L2.info.cache_type = Cache_all;
    L2.info.busy_lines = zeros();
    // L2_I.info.cache_type = Cache_inst;
    // L2_I.info.busy_lines = zeros();
    // L2_D.info.cache_type = Cache_data;
    // L2_D.info.busy_lines = zeros();

    L1.info.mcs = 0;
    L1.info.mcb = unsigned(lbparams);

    L1_I.info.mcs = unsigned(sparams.L1_I);
    L1_I.info.mcb = unsigned(lbparams);
    
    L1_D.info.mcs = unsigned(sparams.L1_D);
    L1_D.info.mcb = unsigned(lbparams);
    
    L2.info.mcs = unsigned(sparams.L2);
    L2.info.mcb = unsigned(lbparams);
    
    L2_I.info.mcs = 0;
    L2_I.info.mcb = unsigned(lbparams);
    
    L2_D.info.mcs = 0;
    L2_D.info.mcb = unsigned(lbparams);
    
    if (unsigned(crepc) == 0) then {
      // print_endline("Cache policy Random");
      // L1.info.rep_pol = Cache_Rep_RR;
      L1_I.info.rep_pol = Cache_Rep_RR;
      L1_D.info.rep_pol = Cache_Rep_RR;
      L2.info.rep_pol = Cache_Rep_RR;
      // L2_I.info.rep_pol = Cache_Rep_RR;
      // L2_D.info.rep_pol = Cache_Rep_RR;
      // print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      // print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      // print_endline("Configuration: Rep_policy <- FIFO");
      print_endline("Configuration: Rep_policy <- Random");
      // print_endline("Cache policy FIFO");
    } else {
      // L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
      L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
      // L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      // print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      // print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      // print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      // print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      // print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      // print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      print_endline("Configuration: Rep_policy <- FIFO");
      // print_endline("Configuration: Rep_policy <- Random");
    };

  } else if (level_types == 4) then { // L1 + L2_I + L2_D
    L1.info.cache_type = Cache_all;
    L1.info.busy_lines = zeros();
    // L1_I.info.cache_type = Cache_inst;
    // L1_I.info.busy_lines = zeros();
    // L1_D.info.cache_type = Cache_data;
    // L1_D.info.busy_lines = zeros();
    // L2.info.cache_type = Cache_all;
    // L2.info.busy_lines = zeros();
    L2_I.info.cache_type = Cache_inst;
    L2_I.info.busy_lines = zeros();
    L2_D.info.cache_type = Cache_data;
    L2_D.info.busy_lines = zeros();

    L1.info.mcs = unsigned(sparams.L1);
    L1.info.mcb = unsigned(lbparams);

    L1_I.info.mcs = 0;
    L1_I.info.mcb = unsigned(lbparams);
    
    L1_D.info.mcs = 0;
    L1_D.info.mcb = unsigned(lbparams);
    
    L2.info.mcs = 0;
    L2.info.mcb = unsigned(lbparams);
    
    L2_I.info.mcs = unsigned(sparams.L2_I);
    L2_I.info.mcb = unsigned(lbparams);
    
    L2_D.info.mcs = unsigned(sparams.L2_D);
    L2_D.info.mcb = unsigned(lbparams);

    if (unsigned(crepc) == 0) then {
      // print_endline("Cache policy Random");
      L1.info.rep_pol = Cache_Rep_RR;
      // L1_I.info.rep_pol = Cache_Rep_RR;
      // L1_D.info.rep_pol = Cache_Rep_RR;
      // L2.info.rep_pol = Cache_Rep_RR;
      L2_I.info.rep_pol = Cache_Rep_RR;
      L2_D.info.rep_pol = Cache_Rep_RR;
      print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      // print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      // print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      // print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      // print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      // print_endline("Configuration: Rep_policy <- FIFO");
      print_endline("Configuration: Rep_policy <- Random");
    } else {
      // print_endline("Cache policy FIFO");
      L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
      // L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
      L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      // print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      // print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      // print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      // print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      print_endline("Configuration: Rep_policy <- FIFO");
      // print_endline("Configuration: Rep_policy <- Random");
    };

  } else if (level_types == 5) then { // L1_I + L1_D + L2_I + L2_D


    // L1.info.cache_type = Cache_all;
    // L1.info.busy_lines = zeros();
    L1_I.info.cache_type = Cache_inst;
    L1_I.info.busy_lines = zeros();
    L1_D.info.cache_type = Cache_data;
    L1_D.info.busy_lines = zeros();
    // L2.info.cache_type = Cache_all;
    // L2.info.busy_lines = zeros();
    L2_I.info.cache_type = Cache_inst;
    L2_I.info.busy_lines = zeros();
    L2_D.info.cache_type = Cache_data;
    L2_D.info.busy_lines = zeros();

    L1.info.mcs = 0;
    L1.info.mcb = unsigned(lbparams);

    L1_I.info.mcs = unsigned(sparams.L1_I);
    L1_I.info.mcb = unsigned(lbparams);
    
    L1_D.info.mcs = unsigned(sparams.L1_D);
    L1_D.info.mcb = unsigned(lbparams);
    
    L2.info.mcs = 0;
    L2.info.mcb = unsigned(lbparams);
    
    L2_I.info.mcs = unsigned(sparams.L2_I);
    L2_I.info.mcb = unsigned(lbparams);
    
    L2_D.info.mcs = unsigned(sparams.L2_D);
    L2_D.info.mcb = unsigned(lbparams);
    
    if (unsigned(crepc) == 0) then {
      // print_endline("Cache policy Random");
      // L1.info.rep_pol = Cache_Rep_RR;
      L1_I.info.rep_pol = Cache_Rep_RR;
      L1_D.info.rep_pol = Cache_Rep_RR;
      // L2.info.rep_pol = Cache_Rep_RR;
      L2_I.info.rep_pol = Cache_Rep_RR;
      L2_D.info.rep_pol = Cache_Rep_RR;
      // print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      // print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      // print_endline("Configuration: Rep_policy <- FIFO");
      print_endline("Configuration: Rep_policy <- Random");
    } else {
      // print_endline("Cache policy FIFO");
      // L1.info.rep_pol =   Cache_Rep_Simple_FIFO;
      L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      // L2.info.rep_pol =   Cache_Rep_Simple_FIFO;
      L2_I.info.rep_pol = Cache_Rep_Simple_FIFO;
      L2_D.info.rep_pol = Cache_Rep_Simple_FIFO;
      // print_int("Configuration: L1_SIZE <- ",       L1.info.mcs);
      // print_int("Configuration: L1_BLOCK_SIZE <- ", L1.info.mcb);

      print_int("Configuration: L1_I_SIZE <- ",       L1_I.info.mcs);
      print_int("Configuration: L1_I_BLOCK_SIZE <- ", L1_I.info.mcb);
      
      print_int("Configuration: L1_D_SIZE <- ",       L1_D.info.mcs);
      print_int("Configuration: L1_D_BLOCK_SIZE <- ", L1_D.info.mcb);
      
      // print_int("Configuration: L2_SIZE <- ",       L2.info.mcs);
      // print_int("Configuration: L2_BLOCK_SIZE <- ", L2.info.mcb);
      
      print_int("Configuration: L2_I_SIZE <- ",       L2_I.info.mcs);
      print_int("Configuration: L2_I_BLOCK_SIZE <- ", L2_I.info.mcb);
      
      print_int("Configuration: L2_D_SIZE <- ",       L2_D.info.mcs);
      print_int("Configuration: L2_D_BLOCK_SIZE <- ", L2_D.info.mcb);

      print_endline("Configuration: Rep_policy <- FIFO");
      // print_endline("Configuration: Rep_policy <- Random");
    };

  };
  
  
  // if (unsigned(kc) == 0) then { // Si es 0 significa que la cache es de tipo all
  //   // L1.info.cache_type = Cache_all;
  //   // L1.info.busy_lines = zeros();
  //   // L2.info.cache_type = Cache_all;
  //   // L2.info.busy_lines = zeros();
    
  //   if (unsigned(crepc) == 0) then {
  //     // print_endline("Cache policy Random");
  //     L1.info.rep_pol = Cache_Rep_RR;
  //     print_endline("Configuration: L1_SIZE <- 2048");
  //     L2.info.rep_pol = Cache_Rep_RR;
  //     print_endline("Configuration: L2_SIZE <- 2048");
  //     print_endline("Configuration: Rep_policy <- Random");
  //   } else {
  //     // print_endline("Cache policy FIFO");
  //     L1.info.rep_pol = Cache_Rep_Simple_FIFO;
  //     print_endline("Configuration: L1_SIZE <- 2048");
  //     L2.info.rep_pol = Cache_Rep_Simple_FIFO;
  //     print_endline("Configuration: L2_SIZE <- 2048");
  //     print_endline("Configuration: Rep_policy <- FIFO");
  //   };
  // } else { // Cualquier otro valor indica que la cache es de tipo Instruction + Data
  //   L1_D.info.cache_type = Cache_data;
  //   L1_D.info.busy_lines = zeros();
  //   L1_I.info.cache_type = Cache_inst;
  //   L1_I.info.busy_lines = zeros();
  //   L2.info.cache_type = Cache_all;
  //   L2.info.busy_lines = zeros();
  //   if (unsigned(crepc) == 0) then {
  //     // print_endline("Cache policy Random");
  //     L1_I.info.rep_pol = Cache_Rep_RR;
  //     print_endline("Configuration: L1_I_SIZE <- 1024");
  //     L1_D.info.rep_pol = Cache_Rep_RR;
  //     print_endline("Configuration: L1_I_SIZE <- 1024");
  //     L2.info.rep_pol = Cache_Rep_RR;
  //     print_endline("Configuration: L2_SIZE <- 2048");
  //     print_endline("Configuration: Rep_policy <- Random");
  //   } else {
  //     // print_endline("Cache policy FIFO");
  //     L1_I.info.rep_pol = Cache_Rep_Simple_FIFO;
  //     print_endline("Configuration: L1_I_SIZE <- 1024");
  //     L1_D.info.rep_pol = Cache_Rep_Simple_FIFO;
  //     print_endline("Configuration: L1_D_SIZE <- 1024");
  //     L2.info.rep_pol = Cache_Rep_Simple_FIFO;
  //     print_endline("Configuration: L2_SIZE <- 2048");
  //     print_endline("Configuration: Rep_policy <- FIFO");
  //   };
  // };

  // print_endline("Configuration: SIZE_CACHE_BLOCK <- 128");
  
}


val replace_cache : forall 'n, 0 < 'n <= 16 & (8 * 'n) <= 128. (cache_mem_type, cache_level, xlenbits, int('n), bits('n * 8)) -> int

function replace_cache(ct, cl, addr, width, value) = {
  
  // 1º Mirar la politica de reemplazo
  // 2º Si es random hacer un random de que elemento de la lista reemplazar
  // 3º Si es un valor modificado, escribir el valor en memoria
  // 4º Reemplazar el bloque de cache con el argumento 

    if (L1_I.info.rep_pol == Cache_Rep_RR | L1_D.info.rep_pol == Cache_Rep_RR | L1.info.rep_pol == Cache_Rep_RR | L2.info.rep_pol == Cache_Rep_RR | L2_I.info.rep_pol == Cache_Rep_RR | L2_D.info.rep_pol == Cache_Rep_RR) then {
      if (ct == Cache_inst) then {

      let index_rep : int = unsigned(randomindex(0b000000 @ L1_I.info.busy_lines));
      
      assert(0 <= index_rep & index_rep < L1_I.info.mcs & index_rep < 2048);
      if (L1_I.mem_L1[index_rep].Cache_control_bits == 0b00001) then { // Si algun elemento de la linea de cache 
                                                                       // ha sido modificado se vuelca el bloque entero en memoria
        foreach (i from 0 to 3) {
          let lo : int = i * 32;
          let hi : int = (i + 1) * 32 - 1;

          // make the slice bounds obvious to the solver
          assert(0 <= lo & lo < hi & hi < ('n * 8) & (hi - lo) + 1 == 32);
          
          // Escribimos el elemento actual de la cache en memoria
          match mem_write_value((addr + i * 4), 4, value[hi..lo], false, false, false) {

          MemValue(true)  => {print_endline("");},
          MemValue(false) => {print_endline("");},
          MemException(e) => { print_endline("error storing value from cache to memory"); }
          };
        };
      };

      // Ahora escribimos el nuevo elemento a almacenar en la cache
      L1_I.mem_L1[index_rep].Cache_data_block = zeros(); // [hi..lo] = value[hi..lo];
      // Actualizamos el vector de control y el tag y el index
      L1_I.mem_L1[index_rep].Cache_control_bits = zeros();
      L1_I.mem_L1[index_rep].Cache_tag = zeros(); //  addr[31..14];
      L1_I.mem_L1[index_rep].Cache_index = zeros(); //  addr[13..4];
      index_rep

    } else if (ct == Cache_data) then {
      let index_rep : int = unsigned(randomindex(0b000000 @ L1_D.info.busy_lines));
      
      assert(0 <= index_rep & index_rep < L1_D.info.mcs & index_rep < 2048);
      if (L1_D.mem_L1[index_rep].Cache_control_bits == 0b00001) then { // Si algun elemento de la linea de cache 
                                                                       // ha sido modificado se vuelca el bloque entero en memoria
        foreach (i from 0 to 3) {
          let lo : int = i * 32;
          let hi : int = (i + 1) * 32 - 1;

          // make the slice bounds obvious to the solver
          assert(0 <= lo & lo < hi & hi < ('n * 8) & (hi - lo) + 1 == 32);
          
          // Escribimos el elemento actual de la cache en memoria
          match mem_write_value((addr + i * 4), 4, value[hi..lo], false, false, false) {

          MemValue(true)  => {print_endline("");},
          MemValue(false) => {print_endline("");},
          MemException(e) => { print_endline("error storing value from cache to memory"); }
          };
        };
      };

      // Ahora escribimos el nuevo elemento a almacenar en la cache
      L1_D.mem_L1[index_rep].Cache_data_block = zeros(); // [hi..lo] = value[hi..lo];
      // Actualizamos el vector de control y el tag y el index
      L1_D.mem_L1[index_rep].Cache_control_bits = zeros();
      L1_D.mem_L1[index_rep].Cache_tag = zeros(); //  addr[31..14];
      L1_D.mem_L1[index_rep].Cache_index = zeros(); //  addr[13..4];

      index_rep

    } else if (ct == Cache_all & cl == LL1) then {
      let index_rep : int = unsigned(randomindex(0b00000 @ L1.info.busy_lines));
      
      assert(0 <= index_rep & index_rep < L1.info.mcs & index_rep < 4096);
      if (L1.mem_L1[index_rep].Cache_control_bits == 0b00001) then { // Si algun elemento de la linea de cache 
                                                                       // ha sido modificado se vuelca el bloque entero en memoria
        foreach (i from 0 to 3) {
          let lo : int = i * 32;
          let hi : int = (i + 1) * 32 - 1;

          // make the slice bounds obvious to the solver
          assert(0 <= lo & lo < hi & hi < ('n * 8) & (hi - lo) + 1 == 32);
          
          // Escribimos el elemento actual de la cache en memoria
          match mem_write_value((addr + i * 4), 4, value[hi..lo], false, false, false) {

          MemValue(true)  => {print_endline("");},
          MemValue(false) => {print_endline("");},
          MemException(e) => { print_endline("error storing value from cache to memory"); }
          };
        };
      };


      // Ahora escribimos el nuevo elemento a almacenar en la cache
      L1.mem_L1[index_rep].Cache_data_block = zeros(); // [hi..lo] = value[hi..lo];
      // Actualizamos el vector de control y el tag y el index
      L1.mem_L1[index_rep].Cache_control_bits = zeros();
      L1.mem_L1[index_rep].Cache_tag = zeros(); //  addr[31..14];
      L1.mem_L1[index_rep].Cache_index = zeros(); //  addr[13..4];
      index_rep

    } else if (ct == Cache_inst & cl == LL2) then {
      let index_rep : int = unsigned(randomindex(0b000000 @ L2_I.info.busy_lines));
      
      assert(0 <= index_rep & index_rep < L2_I.info.mcs & index_rep < 2048);
      if (L2_I.mem_L1[index_rep].Cache_control_bits == 0b00001) then { // Si algun elemento de la linea de cache 
                                                                       // ha sido modificado se vuelca el bloque entero en memoria
        foreach (i from 0 to 3) {
          let lo : int = i * 32;
          let hi : int = (i + 1) * 32 - 1;

          // make the slice bounds obvious to the solver
          assert(0 <= lo & lo < hi & hi < ('n * 8) & (hi - lo) + 1 == 32);
          
          // Escribimos el elemento actual de la cache en memoria
          match mem_write_value((addr + i * 4), 4, value[hi..lo], false, false, false) {

          MemValue(true)  => {print_endline("");},
          MemValue(false) => {print_endline("");},
          MemException(e) => { print_endline("error storing value from cache to memory"); }
          };
        };
      };


      // Ahora escribimos el nuevo elemento a almacenar en la cache
      L2_I.mem_L1[index_rep].Cache_data_block = zeros(); // [hi..lo] = value[hi..lo];
      // Actualizamos el vector de control y el tag y el index
      L2_I.mem_L1[index_rep].Cache_control_bits = zeros();
      L2_I.mem_L1[index_rep].Cache_tag = zeros(); //  addr[31..14];
      L2_I.mem_L1[index_rep].Cache_index = zeros(); //  addr[13..4];
      index_rep
    } else if (ct == Cache_data & cl == LL2) then {
      let index_rep : int = unsigned(randomindex(0b000000 @ L2_D.info.busy_lines));
      
      assert(0 <= index_rep & index_rep < L2_D.info.mcs & index_rep < 2048);
      if (L2_D.mem_L1[index_rep].Cache_control_bits == 0b00001) then { // Si algun elemento de la linea de cache 
                                                                       // ha sido modificado se vuelca el bloque entero en memoria
        foreach (i from 0 to 3) {
          let lo : int = i * 32;
          let hi : int = (i + 1) * 32 - 1;

          // make the slice bounds obvious to the solver
          assert(0 <= lo & lo < hi & hi < ('n * 8) & (hi - lo) + 1 == 32);
          
          // Escribimos el elemento actual de la cache en memoria
          match mem_write_value((addr + i * 4), 4, value[hi..lo], false, false, false) {

          MemValue(true)  => {print_endline("");},
          MemValue(false) => {print_endline("");},
          MemException(e) => { print_endline("error storing value from cache to memory"); }
          };
        };
      };


      // Ahora escribimos el nuevo elemento a almacenar en la cache
      L2_D.mem_L1[index_rep].Cache_data_block = zeros(); // [hi..lo] = value[hi..lo];
      // Actualizamos el vector de control y el tag y el index
      L2_D.mem_L1[index_rep].Cache_control_bits = zeros();
      L2_D.mem_L1[index_rep].Cache_tag = zeros(); //  addr[31..14];
      L2_D.mem_L1[index_rep].Cache_index = zeros(); //  addr[13..4];
      index_rep

    } else {
      let index_rep : int = unsigned(randomindex(0b00000 @ L2.info.busy_lines));
      
      assert(0 <= index_rep & index_rep < L2.info.mcs & index_rep < 4096);
      if (L2.mem_L2[index_rep].Cache_control_bits == 0b00001) then { // Si algun elemento de la linea de cache 
                                                                       // ha sido modificado se vuelca el bloque entero en memoria
        foreach (i from 0 to 3) {
          let lo : int = i * 32;
          let hi : int = (i + 1) * 32 - 1;

          // make the slice bounds obvious to the solver
          assert(0 <= lo & lo < hi & hi < ('n * 8) & (hi - lo) + 1 == 32);
          
          // Escribimos el elemento actual de la cache en memoria
          match mem_write_value((addr + i * 4), 4, value[hi..lo], false, false, false) {

          MemValue(true)  => {print_endline("");},
          MemValue(false) => {print_endline("");},
          MemException(e) => { print_endline("error storing value from cache to memory"); }
          };
        };
      };


      // Ahora escribimos el nuevo elemento a almacenar en la cache
      L2.mem_L2[index_rep].Cache_data_block = zeros(); // [hi..lo] = value[hi..lo];
      // Actualizamos el vector de control y el tag y el index
      L2.mem_L2[index_rep].Cache_control_bits = zeros();
      L2.mem_L2[index_rep].Cache_tag = zeros(); //  addr[31..14];
      L2.mem_L2[index_rep].Cache_index = zeros(); //  addr[13..4];
      index_rep
    }
  } else { // Es el caso de FIFO
    if (ct == Cache_inst & cl == LL1) then {
      L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_data_block = zeros();
      L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_tag = zeros();
      L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_index = zeros();
      L1_I.mem_L1[unsigned(L1_I.info.repl_lines)].Cache_offset = zeros();
      L1_I.info.repl_lines = L1_I.info.repl_lines + 1;
      unsigned(L1_I.info.repl_lines)
    } else if (ct == Cache_data & cl == LL1) then {
      L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_data_block = zeros();
      L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_tag = zeros();
      L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_index = zeros();
      L1_D.mem_L1[unsigned(L1_D.info.repl_lines)].Cache_offset = zeros();
      L1_D.info.repl_lines = L1_D.info.repl_lines + 1;
      unsigned(L1_D.info.repl_lines)
    } else if (ct == Cache_all & cl == LL1) then { 
      L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_data_block = zeros();
      L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_tag = zeros();
      L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_index = zeros();
      L1.mem_L1[unsigned(L1.info.repl_lines)].Cache_offset = zeros();
      L1.info.repl_lines = L1.info.repl_lines + 1;
      unsigned(L1.info.repl_lines )

    } else if (ct == Cache_inst & cl == LL2) then {
      L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_data_block = zeros();
      L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_tag = zeros();
      L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_index = zeros();
      L2_I.mem_L1[unsigned(L2_I.info.repl_lines)].Cache_offset = zeros();
      L2_I.info.repl_lines = L2_I.info.repl_lines + 1;
      unsigned(L2_I.info.repl_lines) 
    } else if (ct == Cache_data & cl == LL2) then {
      L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_data_block = zeros();
      L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_tag = zeros();
      L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_index = zeros();
      L2_D.mem_L1[unsigned(L2_D.info.repl_lines)].Cache_offset = zeros();
      L2_D.info.repl_lines = L2_D.info.repl_lines + 1;
      unsigned(L2_D.info.repl_lines) 
    } else {
      L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_data_block = zeros();
      L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_tag = zeros();
      L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_index = zeros();
      L2.mem_L2[unsigned(L2.info.repl_lines)].Cache_offset = zeros();
      L2.info.repl_lines = L2.info.repl_lines + 1;
      unsigned(L2.info.repl_lines) 
    }
  }
}


val write_cache : forall 'n, 0 < 'n <= 16. (cache_mem_type, cache_level, xlenbits, int('n), bits('n * 8), bool) -> bool

function write_cache(ct, cl, addr, width, value, new_line) = {
  let c_tag : bits(18) = addr[31..14];

  let c_index_32 : bits(12) = addr[13..2];
  let c_index_64 : bits(11) = addr[13..3];
  let c_index_128 : bits(10) = addr[13..4];
  
  let c_offset_32 : int = unsigned(addr[1..0]);
  let c_offset_64 : int = unsigned(addr[2..0]);
  let c_offset_128 : int = unsigned(addr[3..0]);
  
  var found : bool = false;
  var written : bool = false;
  let maxbs : int = L1_I.info.mcb;
  
  // let maxsize = maxbs;
  // let a = 43;
  // assert(maxsize != 0);
  if(new_line /*& width == (maxsize / 8)*/) then {
    let addr_to_find_32 : xlenbits = c_tag @ c_index_32 @ 0b00;
    let addr_to_find_64 : xlenbits = c_tag @ c_index_64 @ 0b000;
    let addr_to_find_128 : xlenbits = c_tag @ c_index_128 @ 0b0000;
    // var addr_to_find_ : xlenbits = c_tag @ c_index @ 0b0000; // Solo vale para la version de 32 bits

    var lines_to_store_128 : bits(128) = zeros();
    var lines_to_store_64 : bits(128) = zeros();
    var lines_to_store_32 : bits(32) = zeros();
    if (PC == addr) then {
      // Leemos 16 instrucciones y las integramos en la memoria cache
      assert(0 < maxbs & maxbs <= 128);
      foreach(i from 0 to ((maxbs / 8) - 1)) {
        // Leemos de 2 en 2
        if ((i % 2) == 0) then {
          if (cache_block_size == 128) then {
            assert(0 <= i & i < 16);
            lines_to_store_128[((i + 2) * 8) - 1..(i*8)] = match mem_read(Execute(), (addr_to_find_128 + i), 2, false, false, false) {
                                                        MemException(e) => zeros(),
                                                        MemValue(ilo)   => ilo,
                                                      };
          } else if (cache_block_size == 64) then {
            assert(0 <= i & i < 8);
            lines_to_store_64[((i + 2) * 8) - 1..(i*8)] = match mem_read(Execute(), (addr_to_find_64 + i), 2, false, false, false) {
                                                        MemException(e) => zeros(),
                                                        MemValue(ilo)   => ilo,

                                                      };
          } else if (cache_block_size == 32) then {
            assert(0 <= i & i < 4);
            lines_to_store_32[((i + 2) * 8) - 1..(i*8)] = match mem_read(Execute(), (addr_to_find_32 + i), 2, false, false, false) {
                                                        MemException(e) => zeros(),
                                                        MemValue(ilo)   => ilo,
                                                      };
          };
        };
      };
      // print_reg("linea de bloque a guardar: " ^BitStr(lines_to_store_64));
      // print_reg("linea de bloque a guardar: " ^BitStr(lines_to_store_64[63..0]));
      // ahora se comprueba si la L1 es de instrucciones o completa
      

    }else {
      foreach(i from 0 to ((maxbs / 32) - 1)) {
        if (cache_block_size == 128) then {
            assert(0 <= i & i < 4);
          lines_to_store_128[((i+1)*32) - 1..(i*32)] = match mem_read(Read(Data), (addr_to_find_128 + (i * 4)), 4, false, false, false) {
                                    MemException(e) => zeros(),
                                    MemValue(value)   => value,
                                  };
        } else if (cache_block_size == 64) then {
          assert(0 <= i & i < 2);
          lines_to_store_64[((i+1)*32) - 1..(i*32)] = match mem_read(Read(Data), (addr_to_find_64 + (i * 4)), 4, false, false, false) {
                                    MemException(e) => zeros(),
                                    MemValue(value)   => value,
                                  };
        } else if (cache_block_size == 32) then {
          assert(0 <= i & i < 1);
          lines_to_store_32[((i+1)*32) - 1..(i*32)] = match mem_read(Read(Data), (addr_to_find_32 + (i * 4)), 4, false, false, false) {
                                    MemException(e) => zeros(),
                                    MemValue(value)   => value,
                                  };
        };
      };
      
    };
    if (ct == Cache_inst & cl == LL1) then {
      assert(maxbs > 0 & maxbs <= 128);
      if (unsigned(L1_I.info.busy_lines) < L1_I.info.mcs) then {
        if (cache_block_size == 128) then {
          L1_I.mem_L1[unsigned(L1_I.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L1_I.info.busy_lines)) ^"] L1_I:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));
        } else if (cache_block_size == 64 & maxbs == 64) then {
          print_int("maxbs: ", maxbs);
          L1_I.mem_L1[unsigned(L1_I.info.busy_lines)].Cache_data_block = lines_to_store_64;
          print_reg("["^ dec_str(unsigned(L1_I.info.busy_lines)) ^"] L1_I:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
        } else if (cache_block_size == 32 & maxbs == 32) then {
          L1_I.mem_L1[unsigned(L1_I.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L1_I.info.busy_lines)) ^"] L1_I:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
        };
        // L1_I.mem_L1[unsigned(L1_I.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store[(maxbs - 1)..0];
        L1_I.mem_L1[unsigned(L1_I.info.busy_lines)].Cache_tag = addr[31..14];
        L1_I.mem_L1[unsigned(L1_I.info.busy_lines)].Cache_index = addr[13..4];
        L1_I.mem_L1[unsigned(L1_I.info.busy_lines)].Cache_offset = addr[3..0];
        L1_I.info.busy_lines = L1_I.info.busy_lines + 1;
        // print_reg("["^ dec_str(unsigned(L1_I.info.busy_lines) - 1) ^"] L1_I:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      } else {
        if (cache_block_size == 128) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_128, width, lines_to_store_128[width * 8 - 1..0]);
          assert(0 <= index & index < L1_I.info.mcs & index < 2048);
          L1_I.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store_128[width * 8 - 1..0];
          print_reg("["^ dec_str(index) ^"] L1_I:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));
          L1_I.mem_L1[index].Cache_tag = c_tag;
          L1_I.mem_L1[index].Cache_index = addr[13..4];
          L1_I.mem_L1[index].Cache_offset = addr[3..0];

        } else if (cache_block_size == 64 & width <= 8) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_64, width, lines_to_store_64[width * 8 - 1..0]);
          assert(0 <= index & index < L1_I.info.mcs & index < 2048);
          L1_I.mem_L1[index].Cache_data_block = lines_to_store_64;
          print_reg("["^ dec_str(index) ^"] L1_I:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
          L1_I.mem_L1[index].Cache_tag = c_tag;
          L1_I.mem_L1[index].Cache_index = addr[13..4];
          L1_I.mem_L1[index].Cache_offset = addr[3..0];
          
        } else if (cache_block_size == 32 & width <= 4) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_32, width, lines_to_store_32[width * 8 - 1..0]);
          assert(0 <= index & index < L1_I.info.mcs & index < 2048);
          L1_I.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store_32[width * 8 - 1..0];
          print_reg("["^ dec_str(index) ^"] L1_I:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
          L1_I.mem_L1[index].Cache_tag = c_tag;
          L1_I.mem_L1[index].Cache_index = addr[13..4];
          L1_I.mem_L1[index].Cache_offset = addr[3..0];
          
        };
        // let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find, width, lines_to_store[width * 8 - 1..0]);
        // assert(0 <= index & index < L1_I.info.mcs & index < 2048);
        // L1_I.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store[width * 8 - 1..0];
        // L1_I.mem_L1[index].Cache_tag = c_tag;
        // L1_I.mem_L1[index].Cache_index = addr[13..4];
        // L1_I.mem_L1[index].Cache_offset = addr[3..0];
        // print_reg("["^ dec_str(index) ^"] L1_I:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      };
      // if (unsigned(L2.info.busy_lines) < 2048) then {
      //   L2.info.busy_lines = L2.info.busy_lines + 1;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_tag = c_tag;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_index = c_index;
      // } else {
      //   replace_cache();
      // };
      written = true;

      // let w_ret_L1_I : bool = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true); 
    } else if (ct == Cache_data & cl == LL1) then {
      if (unsigned(L1_D.info.busy_lines) < L1_D.info.mcs) then {
        if (cache_block_size == 128) then {
          L1_D.mem_L1[unsigned(L1_D.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store_128[(width * 8 - 1)..0];
          print_reg("["^ dec_str(unsigned(L1_D.info.busy_lines) - 1) ^"] L1_D:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));
        } else if (cache_block_size == 64 & width <= 8) then {
          L1_D.mem_L1[unsigned(L1_D.info.busy_lines)].Cache_data_block = lines_to_store_64;
          print_reg("["^ dec_str(unsigned(L1_D.info.busy_lines) - 1) ^"] L1_D:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
        } else if (cache_block_size == 32 & width <= 4) then {
          L1_D.mem_L1[unsigned(L1_D.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store_32[(width * 8 - 1)..0];
          print_reg("["^ dec_str(unsigned(L1_D.info.busy_lines) - 1) ^"] L1_D:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
        };
        // L1_D.mem_L1[unsigned(L1_D.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store[(width * 8 - 1)..0];
        L1_D.mem_L1[unsigned(L1_D.info.busy_lines)].Cache_tag = addr[31..14];
        L1_D.mem_L1[unsigned(L1_D.info.busy_lines)].Cache_index = addr[13..4];
        L1_D.mem_L1[unsigned(L1_D.info.busy_lines)].Cache_offset = addr[3..0];
        L1_D.info.busy_lines = L1_D.info.busy_lines + 1;
        // print_reg("["^ dec_str(unsigned(L1_D.info.busy_lines) - 1) ^"] L1_D:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      } else {
        if (cache_block_size == 128) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_128, width, lines_to_store_128[(width * 8 - 1)..0]);
          assert(0 <= index & index < L1_D.info.mcs & index < 2048);
          L1_D.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store_128[(width * 8 - 1)..0];
          L1_D.mem_L1[index].Cache_tag = c_tag;
          L1_D.mem_L1[index].Cache_index = addr[13..4];
          L1_D.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L1_D:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));

        } else if (cache_block_size == 64 & width <= 8) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_64, width, lines_to_store_64[(width * 8 - 1)..0]);
          assert(0 <= index & index < L1_D.info.mcs & index < 2048);
          L1_D.mem_L1[index].Cache_data_block = lines_to_store_64;
          L1_D.mem_L1[index].Cache_tag = c_tag;
          L1_D.mem_L1[index].Cache_index = addr[13..4];
          L1_D.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L1_D:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
        } else if (cache_block_size == 32 & width <= 4) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_32, width, lines_to_store_32[(width * 8 - 1)..0]);
          assert(0 <= index & index < L1_D.info.mcs & index < 2048);
          L1_D.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store_32[(width * 8 - 1)..0];
          L1_D.mem_L1[index].Cache_tag = c_tag;
          L1_D.mem_L1[index].Cache_index = addr[13..4];
          L1_D.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L1_D:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
        };
      };
      // if (unsigned(L2.info.busy_lines) < 2048) then {
      //   L2.info.busy_lines = L2.info.busy_lines + 1;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_tag = c_tag;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_index = c_index;
      // } else {
      //   replace_cache();
      // };
      written = true;

      //let w_ret_L1_I : bool = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true); 
    } else if (ct == Cache_all & cl == LL1) then {
      if (unsigned(L1.info.busy_lines) < L1.info.mcs) then {
        if (cache_block_size == 128 & maxbs == 128) then {
          L1.mem_L1[unsigned(L1.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L1.info.busy_lines)) ^"] L1:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));
        } else if (cache_block_size == 64 & maxbs == 64) then {
          L1.mem_L1[unsigned(L1.info.busy_lines)].Cache_data_block = lines_to_store_64;
          print_reg("["^ dec_str(unsigned(L1.info.busy_lines)) ^"] L1:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
          
        } else if (cache_block_size == 32 & maxbs == 32) then {
          L1.mem_L1[unsigned(L1.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L1.info.busy_lines)) ^"] L1:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
          
        };
        // L1.mem_L1[unsigned(L1.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store[(width * 8 - 1)..0];
        L1.mem_L1[unsigned(L1.info.busy_lines)].Cache_tag = c_tag;
        L1.mem_L1[unsigned(L1.info.busy_lines)].Cache_index = addr[13..4];
        L1.mem_L1[unsigned(L1.info.busy_lines)].Cache_offset = addr[3..0];
        L1.info.busy_lines = L1.info.busy_lines + 1;
        // print_reg("["^ dec_str(unsigned(L1.info.busy_lines) - 1) ^"] L1:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      } else {
        if (cache_block_size == 128 & maxbs == 128) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_128, maxbs/8, lines_to_store_128[(maxbs - 1)..0]);
          assert(0 <= index & index < L1.info.mcs & index < 2048);
          L1.mem_L1[index].Cache_data_block[maxbs - 1..0] = lines_to_store_128[(maxbs - 1)..0];
          L1.mem_L1[index].Cache_tag = c_tag;
          L1.mem_L1[index].Cache_index = addr[13..4];
          L1.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L1:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));

        } else if (cache_block_size == 64  & maxbs == 64) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_64, width, lines_to_store_64[(maxbs - 1)..0]);
          assert(0 <= index & index < L1.info.mcs & index < 2048);
          L1.mem_L1[index].Cache_data_block = lines_to_store_64;
          L1.mem_L1[index].Cache_tag = c_tag;
          L1.mem_L1[index].Cache_index = addr[13..4];
          L1.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L1:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
          
        } else if (cache_block_size == 32  & maxbs == 32) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_32, width, lines_to_store_32[(maxbs - 1)..0]);
          assert(0 <= index & index < L1.info.mcs & index < 2048);
          L1.mem_L1[index].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          L1.mem_L1[index].Cache_tag = c_tag;
          L1.mem_L1[index].Cache_index = addr[13..4];
          L1.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L1:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
          
        };
        // assert(width == 16 & length(lines_to_store) == 128);
        // let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find, width, lines_to_store[(width * 8 - 1)..0]);
        // assert(0 <= index & index < L1.info.mcs & index < 2048);
        // L1.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store[(width * 8 - 1)..0];
        // L1.mem_L1[index].Cache_tag = c_tag;
        // L1.mem_L1[index].Cache_index = addr[13..4];
        // L1.mem_L1[index].Cache_offset = addr[3..0];
        // print_reg("["^ dec_str(index) ^"] L1:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      };

      // if (unsigned() < 2048) then {
      //   L2.info.busy_lines = L2.info.busy_lines + 1;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_tag = c_tag;
      //   L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_index = c_index;
      // } else {
      //   replace_cache();
      // };
      
      written = true;

    } else if (ct == Cache_inst & cl == LL2) then {
      if (unsigned(L2_I.info.busy_lines) < L2_I.info.mcs) then {
        if (cache_block_size == 128 & maxbs == 128) then {
          L2_I.mem_L1[unsigned(L2_I.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L2_I.info.busy_lines)) ^"] L2_I:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));  
        } else if (cache_block_size == 64 & maxbs == 64) then {
          L2_I.mem_L1[unsigned(L2_I.info.busy_lines)].Cache_data_block = lines_to_store_64;
          print_reg("["^ dec_str(unsigned(L2_I.info.busy_lines)) ^"] L2_I:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64)); 
        } else if (cache_block_size == 32 & maxbs == 32) then {
          L2_I.mem_L1[unsigned(L2_I.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L2_I.info.busy_lines)) ^"] L2_I:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32)); 
        };
        // L2_I.mem_L1[unsigned(L2_I.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store[(width * 8 - 1)..0];
        L2_I.mem_L1[unsigned(L2_I.info.busy_lines)].Cache_tag = c_tag;
        L2_I.mem_L1[unsigned(L2_I.info.busy_lines)].Cache_index = addr[13..4];
        L2_I.mem_L1[unsigned(L2_I.info.busy_lines)].Cache_offset = addr[3..0];
        L2_I.info.busy_lines = L2_I.info.busy_lines + 1;
        // print_reg("["^ dec_str(unsigned(L2_I.info.busy_lines) - 1) ^"] L2_I:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      } else { 
        if (cache_block_size == 128 & maxbs == 128) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_128, width, lines_to_store_128[(maxbs - 1)..0]);
          assert(0 <= index & index < L2_I.info.mcs & index < 2048);
          L2_I.mem_L1[index].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          L2_I.mem_L1[index].Cache_tag = c_tag;
          L2_I.mem_L1[index].Cache_index = addr[13..4];
          L2_I.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2_I:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));

        } else if (cache_block_size == 64  & maxbs == 64) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_64, width, lines_to_store_64[(maxbs - 1)..0]);
          assert(0 <= index & index < L2_I.info.mcs & index < 2048);
          L2_I.mem_L1[index].Cache_data_block = lines_to_store_64;
          L2_I.mem_L1[index].Cache_tag = c_tag;
          L2_I.mem_L1[index].Cache_index = addr[13..4];
          L2_I.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2_I:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
          
        } else if (cache_block_size == 32  & maxbs == 32) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_32, width, lines_to_store_32[(maxbs - 1)..0]);
          assert(0 <= index & index < L2_I.info.mcs & index < 2048);
          L2_I.mem_L1[index].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          L2_I.mem_L1[index].Cache_tag = c_tag;
          L2_I.mem_L1[index].Cache_index = addr[13..4];
          L2_I.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2_I:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
        };
        // let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_, width, lines_to_store_[(width * 8 - 1)..0]);
        // assert(0 <= index & index < L2_I.info.mcs & index < 2048);
        // L2_I.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store_[(width * 8 - 1)..0];
        // L2_I.mem_L1[index].Cache_tag = c_tag;
        // L2_I.mem_L1[index].Cache_index = addr[13..4];
        // L2_I.mem_L1[index].Cache_offset = addr[3..0];
        // print_reg("["^ dec_str(index) ^"] L2_I:("^ BitStr((c_tag @ c_index_ @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_));
      };
      
      written = true;

    } else if (ct == Cache_data & cl == LL2) then {
      if (unsigned(L2_D.info.busy_lines) < L2_D.info.mcs) then {
        if (cache_block_size == 128 & maxbs == 128) then {
          L2_D.mem_L1[unsigned(L2_D.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L2_D.info.busy_lines)) ^"] L2_D:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));
        } else if (cache_block_size == 64 & maxbs == 64) then {
          L2_D.mem_L1[unsigned(L2_D.info.busy_lines)].Cache_data_block = lines_to_store_64;
          print_reg("["^ dec_str(unsigned(L2_D.info.busy_lines)) ^"] L2_D:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
        } else if (cache_block_size == 32 & maxbs == 32) then {
          L2_D.mem_L1[unsigned(L2_D.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L2_D.info.busy_lines)) ^"] L2_D:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
        };
        // L2_D.mem_L1[unsigned(L2_D.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store[(width * 8 - 1)..0];
        L2_D.mem_L1[unsigned(L2_D.info.busy_lines)].Cache_tag = c_tag;
        L2_D.mem_L1[unsigned(L2_D.info.busy_lines)].Cache_index = addr[13..4];
        L2_D.mem_L1[unsigned(L2_D.info.busy_lines)].Cache_offset = addr[3..0];
        L2_D.info.busy_lines = L2_D.info.busy_lines + 1;
        // print_reg("["^ dec_str(unsigned(L2_D.info.busy_lines) - 1) ^"] L2_D:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      } else { 
        if (cache_block_size == 128 & maxbs == 128) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_128, width, lines_to_store_128[(maxbs - 1)..0]);
          assert(0 <= index & index < L2_D.info.mcs & index < 2048);
          L2_D.mem_L1[index].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          L2_D.mem_L1[index].Cache_tag = c_tag;
          L2_D.mem_L1[index].Cache_index = addr[13..4];
          L2_D.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2_D:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));
        } else if (cache_block_size == 64 & maxbs == 64) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_64, width, lines_to_store_64[(maxbs - 1)..0]);
          assert(0 <= index & index < L2_D.info.mcs & index < 2048);
          L2_D.mem_L1[index].Cache_data_block = lines_to_store_64;
          L2_D.mem_L1[index].Cache_tag = c_tag;
          L2_D.mem_L1[index].Cache_index = addr[13..4];
          L2_D.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2_D:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
        } else if (cache_block_size == 32 & maxbs == 32) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_32, width, lines_to_store_32[(maxbs - 1)..0]);
          assert(0 <= index & index < L2_D.info.mcs & index < 2048);
          L2_D.mem_L1[index].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          L2_D.mem_L1[index].Cache_tag = c_tag;
          L2_D.mem_L1[index].Cache_index = addr[13..4];
          L2_D.mem_L1[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2_D:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
        };
        // let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_, width, lines_to_store_[(width * 8 - 1)..0]);
        // assert(0 <= index & index < L2_D.info.mcs & index < 2048);
        // L2_D.mem_L1[index].Cache_data_block[width * 8 - 1..0] = lines_to_store_[(width * 8 - 1)..0];
        // L2_D.mem_L1[index].Cache_tag = c_tag;
        // L2_D.mem_L1[index].Cache_index = addr[13..4];
        // L2_D.mem_L1[index].Cache_offset = addr[3..0];
        // print_reg("["^ dec_str(index) ^"] L2_D:("^ BitStr((c_tag @ c_index_ @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_));
      };
      
      written = true;

    } else { // Si no es ninguna de las dos es una caché L2
      if (unsigned(L2.info.busy_lines) < L2.info.mcs) then {
        if (cache_block_size == 128 & maxbs == 128) then {
          L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L2.info.busy_lines)) ^"] L2:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));
        } else if (cache_block_size == 64 & maxbs == 64) then {
          L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_data_block = lines_to_store_64;
          print_reg("["^ dec_str(unsigned(L2.info.busy_lines)) ^"] L2:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
          
        } else if (cache_block_size == 32 & maxbs == 32) then {
          L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          print_reg("["^ dec_str(unsigned(L2.info.busy_lines)) ^"] L2:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
          
        };
        // L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_data_block[(width * 8 - 1)..0] = lines_to_store[(width * 8 - 1)..0];
        L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_tag = c_tag;
        L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_index = addr[13..4];
        L2.mem_L2[unsigned(L2.info.busy_lines)].Cache_offset = addr[3..0];
        L2.info.busy_lines = L2.info.busy_lines + 1;
        // print_reg("["^ dec_str(unsigned(L2.info.busy_lines) - 1) ^"] L2:("^ BitStr((c_tag @ c_index @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store));
      } else { 
        if (cache_block_size == 128 & maxbs == 128) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_128, width, lines_to_store_128[(maxbs - 1)..0]);
          assert(0 <= index & index < L2.info.mcs & index < 4096);
          L2.mem_L2[index].Cache_data_block[(maxbs - 1)..0] = lines_to_store_128[(maxbs - 1)..0];
          L2.mem_L2[index].Cache_tag = c_tag;
          L2.mem_L2[index].Cache_index = addr[13..4];
          L2.mem_L2[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_128));

        } else if (cache_block_size == 64 & maxbs == 64) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_64, width, lines_to_store_64[(maxbs - 1)..0]);
          assert(0 <= index & index < L2.info.mcs & index < 4096);
          L2.mem_L2[index].Cache_data_block = lines_to_store_64;
          L2.mem_L2[index].Cache_tag = c_tag;
          L2.mem_L2[index].Cache_index = addr[13..4];
          L2.mem_L2[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^BitStr(lines_to_store_64));
          
        } else if (cache_block_size == 32 & maxbs == 32) then {
          let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_32, width, lines_to_store_32[(maxbs - 1)..0]);
          assert(0 <= index & index < L2.info.mcs & index < 4096);
          L2.mem_L2[index].Cache_data_block[(maxbs - 1)..0] = lines_to_store_32[(maxbs - 1)..0];
          L2.mem_L2[index].Cache_tag = c_tag;
          L2.mem_L2[index].Cache_index = addr[13..4];
          L2.mem_L2[index].Cache_offset = addr[3..0];
          print_reg("["^ dec_str(index) ^"] L2:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^BitStr(lines_to_store_32));
        };
        // let index : int =  0; // let index : int = replace_cache(ct, cl, addr_to_find_, width, lines_to_store_[(width * 8 - 1)..0]);
        // assert(0 <= index & index < L2.info.mcs & index < 4096);
        // L2.mem_L2[index].Cache_data_block[width * 8 - 1..0] = lines_to_store_[(width * 8 - 1)..0];
        // L2.mem_L2[index].Cache_tag = c_tag;
        // L2.mem_L2[index].Cache_index = addr[13..4];
        // L2.mem_L2[index].Cache_offset = addr[3..0];
        // print_reg("["^ dec_str(index) ^"] L2:("^ BitStr((c_tag @ c_index_ @ 0b0000)) ^ ") <- " ^BitStr(lines_to_store_));
      };
      
      written = true;
      
      // let w_ret_L2 : bool = write_cache(Cache_all, LL2, addr, 16, lines_to_store, true); 
    };


  } else { // cuando no se quiere escribir una nueva linea solo un elemento

    // 1) Busca la linea de caché
    // 1.1) Si existe la línea Ir a 3
    // 1.2) No existe la linea Ir a 2 y notificar cache miss
    // 2) Escribir nueva linea caché return true
    // 3) Modificar el valor de la linea cache.

    if (cl == LL1) then { // Nivel 1: (Insn + Datos) o Unificada
      if (ct == Cache_data) then {
        let lines = unsigned(L1_D.info.busy_lines);
        foreach(i from 0 to (lines - 1)){
          if(L1_D.mem_L1[i].Cache_tag == c_tag & L1_D.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {

            if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < ((c_offset_128 + width) * 8 - 1) & ((c_offset_128 + width) * 8 - 1) < 128) then {
              L1_D.mem_L1[i].Cache_data_block[((c_offset_128 + width) * 8) - 1..(c_offset_128 * 8)] = value;    // Leemos el bloque
              L1_D.mem_L1[i].Cache_control_bits = 0b00001;

              print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^ BitStr(L1_D.mem_L1[i].Cache_data_block));
              written = true;
              found = true;
            };
            // L1_D.mem_L1[i].Cache_data_block[]
          } else if(L1_D.mem_L1[i].Cache_tag == c_tag & (L1_D.mem_L1[i].Cache_index @ L1_D.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {

            if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < ((c_offset_64 + width) * 8 - 1) & ((c_offset_64 + width) * 8 - 1) < 64) then {
              L1_D.mem_L1[i].Cache_data_block[((c_offset_64 + width) * 8) - 1..(c_offset_64 * 8)] = value;    // Leemos el bloque
              L1_D.mem_L1[i].Cache_control_bits = 0b00001;

              print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^ BitStr(L1_D.mem_L1[i].Cache_data_block));
              written = true;
              found = true;
            };
            // L1_D.mem_L1[i].Cache_data_block[]
          } else if(L1_D.mem_L1[i].Cache_tag == c_tag & (L1_D.mem_L1[i].Cache_index @ L1_D.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {

            if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < ((c_offset_32 + width) * 8 - 1) & ((c_offset_32 + width) * 8 - 1) < 32) then {
              L1_D.mem_L1[i].Cache_data_block[((c_offset_32 + width) * 8) - 1..(c_offset_32 * 8)] = value;    // Leemos el bloque
              L1_D.mem_L1[i].Cache_control_bits = 0b00001;

              print_reg("["^ dec_str(i) ^"] L1_D:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^ BitStr(L1_D.mem_L1[i].Cache_data_block));
              written = true;
              found = true;
            };
            // L1_D.mem_L1[i].Cache_data_block[]
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
        let lines = unsigned(L1_I.info.busy_lines);
        foreach(i from 0 to (lines - 1)){

          if(L1_I.mem_L1[i].Cache_tag == c_tag & L1_I.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
            if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
              L1_I.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)] = value;    // Leemos el bloque
              L1_I.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^ BitStr(L1_I.mem_L1[i].Cache_data_block));
              written = true;
              found = true;
            };
          } else if(L1_I.mem_L1[i].Cache_tag == c_tag & (L1_I.mem_L1[i].Cache_index @ L1_I.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
            if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
              L1_I.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)] = value;    // Leemos el bloque
              L1_I.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^ BitStr(L1_I.mem_L1[i].Cache_data_block));
              written = true;
              found = true;
            };
          } else if(L1_I.mem_L1[i].Cache_tag == c_tag & (L1_I.mem_L1[i].Cache_index @ L1_I.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
            if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
              L1_I.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)] = value;    // Leemos el bloque
              L1_I.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L1_I:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^ BitStr(L1_I.mem_L1[i].Cache_data_block));
              written = true;
              found = true;
            };
          }

        };
        // found = false;
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
          // written = write_cache(Cache_all, LL2, addr, width, value, false);
          // if (written == false) then {
          //   // var lines_to_store : bits (128) = zeros();
          //   print_endline("Escribo en L1_I write_cache true");
          //   written = write_cache(Cache_inst, LL1, addr, width, value, true);
          //   // ahora modificamos el valor en la nueva linea
          //   written = write_cache(Cache_all, LL2, addr, width, value, false);
          //   print_endline("Escribo en L1_I write_cache false");
          //   written = write_cache(Cache_inst, LL1, addr, width, value, false);
          // };
        }
      }
      else {
        let lines = unsigned(L1.info.busy_lines);
        foreach(i from 0 to (lines - 1)){
          if(L1.mem_L1[i].Cache_tag == c_tag & L1.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {

            found = true;
            if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
              L1.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)] = value;    // Leemos el bloque
              L1.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^ BitStr(L1.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
            };
          } else if(L1.mem_L1[i].Cache_tag == c_tag & (L1.mem_L1[i].Cache_index @ L1.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {

            found = true;
            if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
              L1.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)] = value;    // Leemos el bloque
              L1.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^ BitStr(L1.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
            };
          } else if(L1.mem_L1[i].Cache_tag == c_tag & (L1.mem_L1[i].Cache_index @ L1.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {

            found = true;
            if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
              L1.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)] = value;    // Leemos el bloque
              L1.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L1:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^ BitStr(L1.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
            };
          };
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
          



          // written = write_cache(Cache_all, LL2, addr, width, value, false);
          // if (written == false) then {
          //   // var lines_to_store : bits(128) = zeros();
          //   written = write_cache(Cache_all, LL1, addr, width, value, true);
          //   // ahora modificamos la lineas
          //   written = write_cache(Cache_all, LL2, addr, width, value, false);
          //   written = write_cache(Cache_all, LL1, addr, width, value, false);
          // };
        }
      };
    } else { // Cache de nivel 2
      if (ct ==  Cache_inst) then {
        let lines = unsigned(L2_I.info.busy_lines);
        foreach(i from 0 to (lines - 1)){
          if(L2_I.mem_L1[i].Cache_tag == c_tag & L2_I.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
            if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
              L2_I.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)] = value;    // Leemos el bloque
              L2_I.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^ BitStr(L2_I.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
              };
          } else if(L2_I.mem_L1[i].Cache_tag == c_tag & (L2_I.mem_L1[i].Cache_index @ L2_I.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
            if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
              L2_I.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)] = value;    // Leemos el bloque
              L2_I.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^ BitStr(L2_I.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
              };
          } else if(L2_I.mem_L1[i].Cache_tag == c_tag & (L2_I.mem_L1[i].Cache_index @ L2_I.mem_L1[i].Cache_offset[3..2])== c_index_32 & cache_block_size == 32) then {
            if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
              L2_I.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)] = value;    // Leemos el bloque
              L2_I.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2_I:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^ BitStr(L2_I.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
              };
          }; 
        };
        if(found == false) then {
          print_endline("Write Cache L2_I miss");

          written = write_cache(Cache_inst, LL2, addr, width, value, true);
          written = write_cache(Cache_inst, LL2, addr, width, value, false);
          written = false;
        }
      } else if (ct == Cache_data) then {
        let lines = unsigned(L2_D.info.busy_lines);
        foreach(i from 0 to (lines - 1)){
          if(L2_D.mem_L1[i].Cache_tag == c_tag & L2_D.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
            if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
              L2_D.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)] = value;    // Leemos el bloque
              L2_D.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^ BitStr(L2_D.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
              };
          } else if(L2_D.mem_L1[i].Cache_tag == c_tag & (L2_D.mem_L1[i].Cache_index @ L2_D.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
            if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
              L2_D.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)] = value;    // Leemos el bloque
              L2_D.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^ BitStr(L2_D.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
              };
          } else if(L2_D.mem_L1[i].Cache_tag == c_tag & (L2_D.mem_L1[i].Cache_index @ L2_D.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
            if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
              L2_D.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)] = value;    // Leemos el bloque
              L2_D.mem_L1[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2_D:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^ BitStr(L2_D.mem_L1[i].Cache_data_block));
              found = true;
              written = true;
              };
          }
        };
        if(found == false) then {
          print_endline("Write Cache L2_D miss");
          written = write_cache(Cache_data, LL2, addr, width, value, true);
          written = write_cache(Cache_data, LL2, addr, width, value, false);
          written = false;
        }

      } else {
        let lines = unsigned(L2.info.busy_lines);
        foreach(i from 0 to (lines - 1)){
          if(L2.mem_L2[i].Cache_tag == c_tag & L2.mem_L2[i].Cache_index == c_index_128 & cache_block_size == 128) then {
            if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
              L2.mem_L2[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)] = value;    // Leemos el bloque
              L2.mem_L2[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((c_tag @ c_index_128 @ 0b0000)) ^ ") <- " ^ BitStr(L2.mem_L2[i].Cache_data_block));
              found = true;
              written = true;
              };
          } else if(L2.mem_L2[i].Cache_tag == c_tag & (L2.mem_L2[i].Cache_index @ L2.mem_L2[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
            if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
              L2.mem_L2[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)] = value;    // Leemos el bloque
              L2.mem_L2[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((c_tag @ c_index_64 @ 0b000)) ^ ") <- " ^ BitStr(L2.mem_L2[i].Cache_data_block));
              found = true;
              written = true;
              };
          } else if(L2.mem_L2[i].Cache_tag == c_tag & (L2.mem_L2[i].Cache_index @ L2.mem_L2[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
            if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
              L2.mem_L2[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)] = value;    // Leemos el bloque
              L2.mem_L2[i].Cache_control_bits = 0b00001;
              print_reg("["^ dec_str(i) ^"] L2:("^ BitStr((c_tag @ c_index_32 @ 0b00)) ^ ") <- " ^ BitStr(L2.mem_L2[i].Cache_data_block));
              found = true;
              written = true;
              };
          };
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


val read_cache : forall 'n, 0 < 'n <= max_mem_access. /*16.*/ (cache_mem_type, cache_level, xlenbits, int('n)) -> (bits(8 * 'n), bool)

function read_cache(ct, cl, addr, width) = {
  // Descomponemos la direccion en los 3 elementos a buscar
  // let kc = unsigned(kind_of_cache());
  var result    : bits(8 * 'n) = zeros();
  let c_tag     : bits(18) = addr[31..14];

  let c_index_32 : bits(12)  = addr[13..2];
  let c_index_64 : bits(11)  = addr[13..3];
  let c_index_128 : bits(10) = addr[13..4];
  
  let c_offset_32 :  int = unsigned(addr[1..0]);
  let c_offset_64 :  int = unsigned(addr[2..0]);
  let c_offset_128 : int = unsigned(addr[3..0]);
  
  var found : bool = false;

  if (cl  == LL1) then { // Si es de nivel 1 buscamos entre datos + instrucciones o una cache unificada
    if(ct == Cache_data) then {

      // let c_tag     : bits(18) = addr[31..14];
      // let c_index : bits(10) = addr[13..4];
      // let c_offset  : int      = unsigned(addr[3..0]);
      let lines = unsigned(L1_D.info.busy_lines);


      foreach(i from 0 to (lines - 1)) {
        if(L1_D.mem_L1[i].Cache_tag == c_tag & L1_D.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
          found = true;
          print_endline("Cache L1_D hit");

          if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
            result = L1_D.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)];    // Leemos el bloque
          };
        } else if(L1_D.mem_L1[i].Cache_tag == c_tag & (L1_D.mem_L1[i].Cache_index @ L1_D.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
          found = true;
          print_endline("Cache L1_D hit");

          if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 128) then {
            result = L1_D.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)];    // Leemos el bloque
          };
        } else if(L1_D.mem_L1[i].Cache_tag == c_tag & (L1_D.mem_L1[i].Cache_index @ L1_D.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
          found = true;
          print_endline("Cache L1_D hit");

          if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
            result = L1_D.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)];    // Leemos el bloque
          };
        };

      };
      if (found == false) then {
        print_endline("Cache L1_D miss");
        // Mirar que cache es
        if (level_types == 1) then {
          let lines_to_store : bits (128) = zeros();
          written = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
          // Devolver el valor escrito
        } else if (level_types == 5) then {
          (result, found) = read_cache(Cache_data, LL2, addr, width);
        };

        // Buscamos en L2 y devolvemos el resultado
        // (result, found) = read_cache(Cache_all, LL2, addr, width);
        // let lines_to_store : bits(128) = zeros();
        // found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
      };

    } else if (ct == Cache_inst) then {



      let lines = unsigned(L1_I.info.busy_lines);
      foreach(i from 0 to (lines - 1)) {
        // print_reg("Cache tag: " ^ BitStr(L1_I.mem_L1[i].Cache_tag));
        // print_reg("Cache index: " ^ BitStr(L1_I.mem_L1[i].Cache_index));
        if(L1_I.mem_L1[i].Cache_tag == c_tag & L1_I.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
          // found = true;
          print_endline("Cache L1_I hit");
          if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
            result = L1_I.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)];    // Leemos el bloque
            found = true;
          };
        } else if (L1_I.mem_L1[i].Cache_tag == c_tag & (L1_I.mem_L1[i].Cache_index @ L1_I.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
          // found = true;
          print_endline("Cache L1_I hit");
          if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
            result = L1_I.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)];    // Leemos el bloque
            found = true;
          };
        } else if (L1_I.mem_L1[i].Cache_tag == c_tag & (L1_I.mem_L1[i].Cache_index @ L1_I.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
          // found = true;
          print_endline("Cache L1_I hit");
          if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
            result = L1_I.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)];    // Leemos el bloque
            found = true;
          };
        };
      };
      if (found == false) then {
        print_endline("Cache L1_I miss");
        // Si no se encuentra se busca en L2
        if (level_types == 1) then {
          if ( cache_block_size == 128 ) then {
            let lines_to_store : bits(128) = zeros();  
            found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
          } else if ( cache_block_size == 64 ) then {
            let lines_to_store : bits(64) = zeros();  
            found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
          } else if ( cache_block_size == 32 ) then {
            let lines_to_store : bits(32) = zeros();  
            found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
          };
          assert('n == 2);
          result = match mem_read(Execute(), addr, 2, false, false, false) {
                                                      MemException(e) => zeros(),
                                                      MemValue(ilo)   => ilo['n * 8 - 1 .. 0],
                                                    };
        } else if (level_types == 3) then {
          (result, found) = read_cache(Cache_all, LL2, addr, width);
        } else if (level_types == 5) then {
          (result, found) = read_cache(Cache_inst, LL2, addr, width);
        };
        // (result, found) = read_cache(Cache_all, LL2, addr, width);
        // let lines_to_store : bits(128) = zeros();
        // found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
      };

    } else { // Buscar en toda la cache L1

      // let c_tag     : bits(18) = addr[31..14];
      // let c_index : bits(10) = addr[13..4];
      // let c_offset  : int      = unsigned(addr[3..0]);
      let lines = unsigned(L1.info.busy_lines);
      foreach(i from 0 to (lines - 1)) {
        if(L1.mem_L1[i].Cache_tag == c_tag & L1.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
          if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
            print_endline("Cache L1 hit inst");
            result = L1.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)];    // Leemos el bloque
            found = true;
          };
        } else if(L1.mem_L1[i].Cache_tag == c_tag & (L1.mem_L1[i].Cache_index @ L1.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
          if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
            print_endline("Cache L1 hit inst");
            result = L1.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)];    // Leemos el bloque
            found = true;
          };
        } else if(L1.mem_L1[i].Cache_tag == c_tag & (L1.mem_L1[i].Cache_index @ L1.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
          
          if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 128) then {
            print_endline("Cache L1 hit inst");
            result = L1.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)];    // Leemos el bloque
            found = true;
          };
        }

      };

      if (found == false) then {
        print_endline("Cache L1 miss");

        if (level_types == 0) then {
          if (cache_block_size == 128) then {
            let lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
          } else if (cache_block_size == 64) then {
            let lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
          } else if (cache_block_size == 32) then {
            let lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
          };
          if (PC == addr | (PC + 2) == addr) then {
            assert('n == 2);
            result= match mem_read(Execute(), addr, 2, false, false, false) {
                                                      MemException(e) => zeros(),
                                                      MemValue(ilo)   => ilo['n * 8 - 1 .. 0],
                                                    };
          } else{
            assert('n == 4);
            result = match mem_read(Read(Data), addr, 4, false, false, false) {
                                  MemException(e) => zeros(),
                                  MemValue(value)   => value,
                                };
          }; 
        } else if (level_types == 2) then {
          (result, found) = read_cache(Cache_all, LL2, addr, width);
        } else if (level_types == 4) then {
          if (PC == addr | (PC + 2) == addr) then {
            (result, found) = read_cache(Cache_inst, LL2, addr, width);
          } else {
            (result, found) = read_cache(Cache_data, LL2, addr, width);
          }
        }
        // Si no se encuentra se busca en L2
        // (result, found) = read_cache(Cache_all, LL2, addr, width);
        // let lines_to_store : bits(128) = zeros();
        // found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
      };

    };

  } else { // Buscamos en L2
    if (ct == Cache_data) then {

      let lines = unsigned(L2_D.info.busy_lines);

      foreach(i from 0 to (lines - 1)) {
        if(L2_D.mem_L1[i].Cache_tag == c_tag & L2_D.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
          if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
            found = true;
            print_endline("Cache L2_D hit");
            result = L2_D.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)];    // Leemos el bloque
          };
        } else if(L2_D.mem_L1[i].Cache_tag == c_tag & (L2_D.mem_L1[i].Cache_index @ L2_D.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
          if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
            found = true;
            print_endline("Cache L2_D hit");
            result = L2_D.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)];    // Leemos el bloque
          };
        } else if(L2_D.mem_L1[i].Cache_tag == c_tag & (L2_D.mem_L1[i].Cache_index @ L2_D.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
          if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
            found = true;
            print_endline("Cache L2_D hit");
            result = L2_D.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)];    // Leemos el bloque
          };
        } 

      };

      if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                // solicitamos a memoria un bloque entero para L1 
                                // y tambien lo escribimos en L2
        print_endline("Cache L2_D miss");
        // Si falla en L2, miramos si la direccion es relativa al pc o es relativa a memoria y leemos
        

        if (level_types == 4) then {
          if (cache_block_size == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true); 
          } else if (cache_block_size == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true); 
          } else if (cache_block_size == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true); 
          };
        } else if (level_types == 5) then {
          if (cache_block_size == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true);
          } else if (cache_block_size == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_data, LL1, addr, 8, lines_to_store, true);
          } else if (cache_block_size == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_data, LL1, addr, 4, lines_to_store, true);
          };
        };
        if (cache_block_size == 128) then {
          var lines_to_store : bits(128) = zeros();
          found = write_cache(Cache_data,LL2,addr, 16, lines_to_store, true);
        } else if (cache_block_size == 64) then {
          var lines_to_store : bits(64) = zeros();
          found = write_cache(Cache_data,LL2,addr, 8, lines_to_store, true);
        } else if (cache_block_size == 32) then {
          var lines_to_store : bits(32) = zeros();
          found = write_cache(Cache_data,LL2,addr, 4, lines_to_store, true);
        };

        result = match mem_read(Read(Data), addr, width, false, false, false) {
                                  MemException(e) => zeros(),
                                  MemValue(value)   => value,
                                };
      }

    } else if (ct == Cache_inst) then {

      // let c_tag     : bits(18) = addr[31..14];
      // let c_index : bits(10) = addr[13..4];
      // let c_offset  : int      = unsigned(addr[3..0]);
      let lines = unsigned(L2_I.info.busy_lines);

      foreach(i from 0 to (lines - 1)) {
        if(L2_I.mem_L1[i].Cache_tag == c_tag & L2_I.mem_L1[i].Cache_index == c_index_128 & cache_block_size == 128) then {
          if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
            found = true;
            print_endline("Cache L2_I hit");
            result = L2_I.mem_L1[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)];    // Leemos el bloque
          };
        } else if(L2_I.mem_L1[i].Cache_tag == c_tag & (L2_I.mem_L1[i].Cache_index @ L2_I.mem_L1[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
          if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
            found = true;
            print_endline("Cache L2_I hit");
            result = L2_I.mem_L1[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)];    // Leemos el bloque
          };
        } else if(L2_I.mem_L1[i].Cache_tag == c_tag & (L2_I.mem_L1[i].Cache_index @ L2_I.mem_L1[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
          if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
            found = true;
            print_endline("Cache L2_I hit");
            result = L2_I.mem_L1[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)];    // Leemos el bloque
          };
        } 

      };

      if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                // solicitamos a memoria un bloque entero para L1 
                                // y tambien lo escribimos en L2
        print_endline("Cache L2_I miss");
        // Si falla en L2, miramos si la direccion es relativa al pc o es relativa a memoria y leemos
        

        if (level_types == 4) then {
          if (cache_block_size == 128) then {
            var lines_to_store : bits(128) = zeros();
            found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true);
          } else if (cache_block_size == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true);
          } else if (cache_block_size == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true);
          };
           
        } else if (level_types == 5) then {
          if (cache_block_size == 128) then {
            var lines_to_store : bits(128) = zeros(); 
            found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true);
          } else if (cache_block_size == 64) then {
            var lines_to_store : bits(64) = zeros();
            found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true);
          } else if (cache_block_size == 32) then {
            var lines_to_store : bits(32) = zeros();
            found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true);
          };
          
        };
        if (cache_block_size == 128) then {
          var lines_to_store : bits(128) = zeros();
          found = write_cache(Cache_inst,LL2,addr, 16, lines_to_store, true);
        } else if (cache_block_size == 64) then {
          var lines_to_store : bits(64) = zeros();
          found = write_cache(Cache_inst,LL2,addr, 8, lines_to_store, true);
        } else if (cache_block_size == 32) then {
          var lines_to_store : bits(32) = zeros();
          found = write_cache(Cache_inst,LL2,addr, 4, lines_to_store, true);
        };
        

        result = match mem_read(Execute(), addr, width, false, false, false) {
                  MemException(e) => zeros(),
                  MemValue(ilo)   => ilo,
                };
          

        // }else {
        //   if (level_types == 2) then { // Significa que L1 es de tipo all
        //     found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true); 
        //   } else if (level_types == 3){
        //     found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true); 
        //   };
        //   result = match mem_read(Read(Data), addr, width, false, false, false) {
        //                                 MemException(e) => zeros(),
        //                                 MemValue(value)   => value,
        //                               };
        // };
        

      };

    } else {

      // let c_tag     : bits(18) = addr[31..14];
      // let c_index : bits(10) = addr[13..4];
      // let c_offset  : int      = unsigned(addr[3..0]);
      let lines = unsigned(L2.info.busy_lines);

      foreach(i from 0 to (lines - 1)) {
        if(L2.mem_L2[i].Cache_tag == c_tag & L2.mem_L2[i].Cache_index == c_index_128 & cache_block_size == 128) then {
          if ((c_offset_128 * 8) >= 0 & (c_offset_128 * 8) < (c_offset_128 * 8 +  width * 8 - 1) & (c_offset_128 * 8 +  width * 8 - 1) < 128) then {
            found = true;
            print_endline("Cache L2 hit inst");
            result = L2.mem_L2[i].Cache_data_block[(c_offset_128 * 8 + width * 8 - 1)..(c_offset_128 * 8)];    // Leemos el bloque
          };
        } else if(L2.mem_L2[i].Cache_tag == c_tag & (L2.mem_L2[i].Cache_index @ L2.mem_L2[i].Cache_offset[3..3]) == c_index_64 & cache_block_size == 64) then {
          if ((c_offset_64 * 8) >= 0 & (c_offset_64 * 8) < (c_offset_64 * 8 +  width * 8 - 1) & (c_offset_64 * 8 +  width * 8 - 1) < 64) then {
            found = true;
            print_endline("Cache L2 hit inst");
            result = L2.mem_L2[i].Cache_data_block[(c_offset_64 * 8 + width * 8 - 1)..(c_offset_64 * 8)];    // Leemos el bloque
          };
        } else if(L2.mem_L2[i].Cache_tag == c_tag & (L2.mem_L2[i].Cache_index @ L2.mem_L2[i].Cache_offset[3..2]) == c_index_32 & cache_block_size == 32) then {
          if ((c_offset_32 * 8) >= 0 & (c_offset_32 * 8) < (c_offset_32 * 8 +  width * 8 - 1) & (c_offset_32 * 8 +  width * 8 - 1) < 32) then {
            found = true;
            print_endline("Cache L2 hit inst");
            result = L2.mem_L2[i].Cache_data_block[(c_offset_32 * 8 + width * 8 - 1)..(c_offset_32 * 8)];    // Leemos el bloque
          };
        }

      };

      if (found == false) then { // Si no se enecuentra ya en L2 tampoco
                                // solicitamos a memoria un bloque entero para L1 
                                // y tambien lo escribimos en L2
        print_endline("Cache L2 miss");
        // Si falla en L2, miramos si la direccion es relativa al pc o es relativa a memoria y leemos
        

        if (PC == addr | (PC + 2) == addr) then {
          if (level_types == 2) then { // Significa que L1 es de tipo all
            if (cache_block_size == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true); 
            } else if (cache_block_size == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true); 
            } else if (cache_block_size == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true); 
            };
            
          } else if (level_types == 3) then {
            if (cache_block_size == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 16, lines_to_store, true); 
            } else if (cache_block_size == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 8, lines_to_store, true); 
            } else if (cache_block_size == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_inst, LL1, addr, 4, lines_to_store, true); 
            };
            
          };
          result = match mem_read(Execute(), addr, width, false, false, false) {
                    MemException(e) => zeros(),
                    MemValue(ilo)   => ilo,
                  };
          

        }else {
          if (level_types == 2) then { // Significa que L1 es de tipo all
            if (cache_block_size == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_all, LL1, addr, 16, lines_to_store, true); 
            } else if (cache_block_size == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_all, LL1, addr, 8, lines_to_store, true); 
            } else if (cache_block_size == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_all, LL1, addr, 4, lines_to_store, true); 
            };
            
          } else if (level_types == 3) then {
            if (cache_block_size == 128) then {
              var lines_to_store : bits(128) = zeros();
              found = write_cache(Cache_data, LL1, addr, 16, lines_to_store, true); 
            } else if (cache_block_size == 64) then {
              var lines_to_store : bits(64) = zeros();
              found = write_cache(Cache_data, LL1, addr, 8, lines_to_store, true); 
            } else if (cache_block_size == 32) then {
              var lines_to_store : bits(32) = zeros();
              found = write_cache(Cache_data, LL1, addr, 4, lines_to_store, true); 
            };
          };
          result = match mem_read(Read(Data), addr, width, false, false, false) {
                                        MemException(e) => zeros(),
                                        MemValue(value)   => value,
                                      };
        };
        if (cache_block_size == 128) then {
          var lines_to_store : bits(128) = zeros();
          found = write_cache(Cache_all,LL2,addr, 16, lines_to_store, true);
        } else if (cache_block_size == 64) then {
          var lines_to_store : bits(64) = zeros();
          found = write_cache(Cache_all,LL2,addr, 8, lines_to_store, true);
        } else if (cache_block_size == 32) then {
          var lines_to_store : bits(32) = zeros();
          found = write_cache(Cache_all,LL2,addr, 4, lines_to_store, true);
        };
        

      };
    };
  };    
  // print_reg("Resultado: " ^ BitStr(result));
  // if (found == true) then {
  // print_endline("found!");
  // } else {
  //   print_endline("Not found :(");
  // };
  (result, found)

}





