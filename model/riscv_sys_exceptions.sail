/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/
/* default exception model */

union MemoryOpResult ('a : Type) = {
  MemValue     : 'a,
  MemException : ExceptionType
}

type ext_exception = unit

val mem_write_value : forall 'n, 0 < 'n <= max_mem_access . (xlenbits, int('n), bits(8 * 'n), bool, bool, bool) -> MemoryOpResult(bool)
// function mem_write_value (paddr, width, value, aq, rl, con) = {
//   mem_write_value_meta(paddr, width, value, default_write_acc, default_meta, aq, rl, con)
// }

val read_string         = { c: "read_string_C" }        : bits(8) -> bits(8)
val read_s              = { c: "read_s" }               : bits(32) -> bits(8) 
val print_test          = { c: "print_test_C" }         : (flenbits, bit) -> unit
val read_int            = { c: "read_int_C" }           : unit -> xlenbits
val read_float          = { c: "read_float_C" }         : unit -> flenbits
val read_double64       = { c: "read_double_64C" }      : unit -> flenbits
val read_double32_low   = { c: "read_double_32C_low" }  : unit -> bits(32)
val read_double32_high  = { c: "read_double_32C_high" } : unit -> bits(32)
val read_char           = { c: "read_char_C" }          : unit -> xlenbits
val print_st            = { c: "print_string_C" }       : string -> unit

/* Is XRET from given mode permitted by extension? */
function ext_check_xret_priv (p : Privilege) : Privilege -> bool = true

/* Called if above check fails */
function ext_fail_xret_priv () : unit -> unit = ()

function handle_trap_extension(p : Privilege, pc : xlenbits, u : option(unit)) -> unit = ()

function print_message(message : xlenbits, is_char : bit) -> unit = {
  var c_message : string = "";
  var printing : bool = true;
  var index : xlenbits = zeros();
  var c_final_message : list(bits(8)) = [||];
  
    if is_char == bitzero then {
    
      c_message = ascii_to_string(message[7..0]);
      print_string("ECALL CHAR: ",c_message);

    } else {
      while(printing) do {
        // print_int("Indice: ", unsigned(index));
        // print_reg("Siguiente direccion a leer: " ^ BitStr(message+index));
        let (mem_value, metaread) = read_ram(Read_plain, message + index, 1, false);
        // print_reg("Valor leido de memoria:" ^ BitStr(mem_value));
        if mem_value == 0b00000000   
        then { 
          printing = false;
        }
        else 
        {
          // if (unsigned(index) % 16 == 0) 
          // then{
            // if unsigned(index) != 0 then print_st(c_message);
            // c_message = "";
          // }; 
          // print_int("Valor del indice fuera else: ", unsigned(index));
          // print_string("Contenido antes: ", c_message);
          // print_string("El string append: ", string_append(c_message, ascii_to_string(mem_value)));
          var tempo : string = string_append(c_message, ascii_to_string(mem_value));
          // print_string("El tempo: ", tempo);
          c_message = tempo;
          // print_string("Contenido leido de momento: ", c_message);
        };
        index = index + 1;
      };
      if (c_message != "") then print_st(c_message);
      // print_endline("");
    };
    
  
}

function write_int() -> unit = {
  let read_int_val = read_int();
  wX(10, read_int_val);
}

function write_float() -> unit = {
  let read_float_val = read_float();
  wF(10, read_float_val);
}

function write_double() -> unit = {
  if (misa[D] == 0b1) then print_endline("MisaD activado");
                                            if (mstatus[FS] != 0b00) then print_endline("mstatus FS distinto de 0b00");
                                            if sizeof(flen) >= 64 then print_endline("Tamaño de flen >= 64");
  if (misa[F] == 0b1) then print_endline("MisaF activado");
  // if haveDoubleFPU() then print_endline("Tengo doble fpu");
  if sizeof(xlen) == 32 then {
    let low_32 : bits(32) =  read_double32_low();
    let high_32 :  bits(32)= read_double32_high();
    let concatenated : bits(64) = high_32 @ low_32;
    print_d(concatenated);
    wF_D(0b01010, concatenated);
  };
  if (sizeof(xlen) == 64) 
  then {
    let read_double_val = read_double64();
    wF_D(0b01010, read_double_val);
  };

  
}

function write_char() -> unit = {
  let read_char_val = read_char();
  wX(10, read_char_val);
}

function write_string() -> unit = {
  let size_string = rX(11); // tamaño maximo del string pasado por parametro
  var string_addr = rX(10); // direccion de memoria donde escribir el primer caracter
  let param = size_string[7..0];
  var index : bits(32) = zeros();

  let buffer : bits(8) = read_string(param);

  match mem_write_value(string_addr, 1, buffer, false, false, false) {
                MemValue(true)  => print_endline("almacenando caracter en memoria"),
                MemValue(false) => print_endline("No se puede guardar dicho valor en la direccion"),
                MemException(e) => { print_endline("Error en la escritura del string en memoria"); () }
              };
  string_addr = string_addr + 1;
  index = index + 1;
  while((unsigned(index) < unsigned(size_string))) do{
    let cha : bits(8) = read_s(index);
    match mem_write_value(string_addr, 1, cha, false, false, false) {
                MemValue(true)  => print_endline("almacenando caracter en memoria"),
                MemValue(false) => print_endline("No se puede guardar dicho valor en la direccion"),
                MemException(e) => { print_endline("Error en la escritura del string en memoria"); () }
              };
    
    string_addr = string_addr + 1;
    index = index + 1;
  }
}

function interpret_exception() -> unit = {
  let a7_val = unsigned(rX(17));
  let a0_val = rX(10);
  let a1_val = rX(11);
  let a2_val = rX(12);
  var f0_val : flenbits = zeros();
  if (sys_enable_fdext()) then {
    f0_val = rF(10);  };

  let result : unit = match a7_val{
    1 => if (0 >= unsigned(a0_val)) then print_int("ECALL UNSIGNED: ",unsigned(a0_val)) else print_int("ECALL SIGNED: ", signed(a0_val)), 
    2 => print_test(f0_val, bitzero),
    3 => print_test(f0_val, bitone),
    4 => print_message(a0_val, bitone),
    5 => write_int(),
    6 => write_float(),
    7 => write_double(),
    8 => write_string(),
    9 => print_endline("Reserva de memoria"),
    10 => (),
    11 => print_message(a0_val, bitzero),
    12 => write_char(),
    _ => print_endline("ERROR")
  }
  
}

/* used for traps and ECALL */
function prepare_trap_vector(p : Privilege, cause : Mcause) -> xlenbits = {

 /* print_endline("Hemos entrado en la excepcion");*/
  
  let tvec : Mtvec = match p {
                       Machine    => mtvec,
                       Supervisor => stvec,
                       User       => utvec
                     };

  match tvec_addr(tvec, cause) {
    Some(epc) => {
      interpret_exception();
      epc
    },
    None()    => internal_error(__FILE__, __LINE__, "Invalid tvec mode")
  }
}

/* xRET handling involves three functions:
 *
 * get_xret_target:     used to read the value of the xret target  (no control flow transfer)
 * set_xret_target:     used to write a value of the xret target   (no control flow transfer)
 * prepare_xret_target: used to get the value for control transfer to the xret target
 */

val get_xret_target : Privilege -> xlenbits
function get_xret_target(p) =
  match p {
    Machine    => mepc,
    Supervisor => sepc,
    User       => uepc
  }

val set_xret_target : (Privilege, xlenbits) -> xlenbits
function set_xret_target(p, value) = {
  let target = legalize_xepc(value);
  match p {
    Machine    => mepc = target,
    Supervisor => sepc = target,
    User       => uepc = target
  };
  target
}

val prepare_xret_target : (Privilege) -> xlenbits
function prepare_xret_target(p) =
  get_xret_target(p)

/* other trap-related CSRs */

function get_mtvec() -> xlenbits =
  mtvec.bits

function get_stvec() -> xlenbits =
  stvec.bits

function get_utvec() -> xlenbits =
  utvec.bits

function set_mtvec(value : xlenbits) -> xlenbits = {
  mtvec = legalize_tvec(mtvec, value);
  mtvec.bits
}

function set_stvec(value : xlenbits) -> xlenbits = {
  stvec = legalize_tvec(stvec, value);
  stvec.bits
}

function set_utvec(value : xlenbits) -> xlenbits = {
  utvec = legalize_tvec(utvec, value);
  utvec.bits
}
