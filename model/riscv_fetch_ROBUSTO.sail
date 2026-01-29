/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Current fetch hooks for RISC-V extensions call extensions
 * to check PC validity *before* standard fetch processing checks.
 */

register debug_mode : bool = true
val debug_C =  pure {c: "stepbystep"} : unit -> bool
// val print_register_status = pure {c: "register_status"} : list(xlenbits) -> unit


struct check_divergence = {
  ra  : xlenbits,
  sp  : xlenbits,
  gp  : xlenbits,
  tp  : xlenbits,
  a0  : xlenbits, 
  a1  : xlenbits, 
  a2  : xlenbits, 
  a3  : xlenbits, 
  a4  : xlenbits, 
  a5  : xlenbits, 
  a6  : xlenbits, 
  a7  : xlenbits, 
  s0  : xlenbits, 
  s1  : xlenbits, 
  s2  : xlenbits, 
  s3  : xlenbits, 
  s4  : xlenbits, 
  s5  : xlenbits, 
  s6  : xlenbits, 
  s7  : xlenbits, 
  s8  : xlenbits, 
  s9  : xlenbits, 
  s10 : xlenbits,  
  s11 : xlenbits,  
  t0  : xlenbits, 
  t1  : xlenbits, 
  t2  : xlenbits, 
  t3  : xlenbits,  
  t4  : xlenbits, 
  t5  : xlenbits, 
  t6  : xlenbits
}

register divergence : check_divergence

struct value_divergence = {
  initialized : bool,
  divergence_counter : int,
  initial_diverg : bool
}

register values_to_check_divergence : value_divergence

val check_divergence_exec : unit -> bool
// val initialized : ref(bool)
// val divergence_counter : int

val start_divergence_counter : unit -> unit
function start_divergence_counter() -> unit = {
  if not(values_to_check_divergence.initialized) then{
    values_to_check_divergence.divergence_counter = 1;
    values_to_check_divergence.initialized = true;
    divergence.ra   = rX(1) ;
    divergence.sp   = rX(2) ;
    divergence.gp   = rX(3) ;
    divergence.tp   = rX(4) ;
    divergence.t0   = rX(5) ;
    divergence.t1   = rX(6) ;
    divergence.t2   = rX(7) ;
    divergence.s0   = rX(8) ;
    divergence.s1   = rX(9) ;
    divergence.a0   = rX(10);
    divergence.a1   = rX(11);
    divergence.a2   = rX(12);
    divergence.a3   = rX(13);
    divergence.a4   = rX(14);
    divergence.a5   = rX(15);
    divergence.a6   = rX(16);
    divergence.a7   = rX(17);
    divergence.s2   = rX(18);
    divergence.s3   = rX(19);
    divergence.s4   = rX(20);
    divergence.s5   = rX(21);
    divergence.s6   = rX(22);
    divergence.s7   = rX(23);
    divergence.s8   = rX(24);
    divergence.s9   = rX(25);
    divergence.s10  = rX(26);
    divergence.s11  = rX(27);
    divergence.t3   = rX(28);
    divergence.t4   = rX(29);
    divergence.t5   = rX(30);
    divergence.t6   = rX(31);

  } else {
    values_to_check_divergence.divergence_counter = ( values_to_check_divergence.divergence_counter % 1000) + 1;
    
  }
    
}

function check_divergence_exec() -> bool = {
  let max_diverged : int = 27 ;
  var counter : int = 0;
  var is_diverged : bool = false;
  if (divergence.ra   == rX(1) ) then  { counter = counter + 1; divergence.ra   = rX(1) ;  } else { divergence.ra   = rX(1) ;}; 
  if (divergence.sp   == rX(2) ) then  { counter = counter + 1; divergence.sp   = rX(2) ;  } else { divergence.sp   = rX(2) ;};
  if (divergence.gp   == rX(3) ) then  { counter = counter + 1; divergence.gp   = rX(3) ;  } else { divergence.gp   = rX(3) ;};
  if (divergence.tp   == rX(4) ) then  { counter = counter + 1; divergence.tp   = rX(4) ;  } else { divergence.tp   = rX(4) ;};
  if (divergence.t0   == rX(5) ) then  { counter = counter + 1; divergence.t0   = rX(5) ;  } else { divergence.t0   = rX(5) ;};
  if (divergence.t1   == rX(6) ) then  { counter = counter + 1; divergence.t1   = rX(6) ;  } else { divergence.t1   = rX(6) ;};
  if (divergence.t2   == rX(7) ) then  { counter = counter + 1; divergence.t2   = rX(7) ;  } else { divergence.t2   = rX(7) ;};
  if (divergence.s0   == rX(8) ) then  { counter = counter + 1; divergence.s0   = rX(8) ;  } else { divergence.s0   = rX(8) ;};
  if (divergence.s1   == rX(9) ) then  { counter = counter + 1; divergence.s1   = rX(9) ;  } else { divergence.s1   = rX(9) ;};
  if (divergence.a0   == rX(10)) then  { counter = counter + 1; divergence.a0   = rX(10);  } else { divergence.a0   = rX(10);};
  if (divergence.a1   == rX(11)) then  { counter = counter + 1; divergence.a1   = rX(11);  } else { divergence.a1   = rX(11);};
  if (divergence.a2   == rX(12)) then  { counter = counter + 1; divergence.a2   = rX(12);  } else { divergence.a2   = rX(12);};
  if (divergence.a3   == rX(13)) then  { counter = counter + 1; divergence.a3   = rX(13);  } else { divergence.a3   = rX(13);};
  if (divergence.a4   == rX(14)) then  { counter = counter + 1; divergence.a4   = rX(14);  } else { divergence.a4   = rX(14);};
  if (divergence.a5   == rX(15)) then  { counter = counter + 1; divergence.a5   = rX(15);  } else { divergence.a5   = rX(15);};
  if (divergence.a6   == rX(16)) then  { counter = counter + 1; divergence.a6   = rX(16);  } else { divergence.a6   = rX(16);};
  if (divergence.a7   == rX(17)) then  { counter = counter + 1; divergence.a7   = rX(17);  } else { divergence.a7   = rX(17);};
  if (divergence.s2   == rX(18)) then  { counter = counter + 1; divergence.s2   = rX(18);  } else { divergence.s2   = rX(18);};
  if (divergence.s3   == rX(19)) then  { counter = counter + 1; divergence.s3   = rX(19);  } else { divergence.s3   = rX(19);};
  if (divergence.s4   == rX(20)) then  { counter = counter + 1; divergence.s4   = rX(20);  } else { divergence.s4   = rX(20);};
  if (divergence.s5   == rX(21)) then  { counter = counter + 1; divergence.s5   = rX(21);  } else { divergence.s5   = rX(21);};
  if (divergence.s6   == rX(22)) then  { counter = counter + 1; divergence.s6   = rX(22);  } else { divergence.s6   = rX(22);};
  if (divergence.s7   == rX(23)) then  { counter = counter + 1; divergence.s7   = rX(23);  } else { divergence.s7   = rX(23);};
  if (divergence.s8   == rX(24)) then  { counter = counter + 1; divergence.s8   = rX(24);  } else { divergence.s8   = rX(24);};
  if (divergence.s9   == rX(25)) then  { counter = counter + 1; divergence.s9   = rX(25);  } else { divergence.s9   = rX(25);};
  if (divergence.s10  == rX(26)) then  { counter = counter + 1; divergence.s10  = rX(26);  } else { divergence.s10  = rX(26);};
  if (divergence.s11  == rX(27)) then  { counter = counter + 1; divergence.s11  = rX(27);  } else { divergence.s11  = rX(27);}; 
  if (divergence.t3   == rX(28)) then  { counter = counter + 1; divergence.t3   = rX(28);  } else { divergence.t3   = rX(28);};
  if (divergence.t4   == rX(29)) then  { counter = counter + 1; divergence.t4   = rX(29);  } else { divergence.t4   = rX(29);};
  if (divergence.t5   == rX(30)) then  { counter = counter + 1; divergence.t5   = rX(30);  } else { divergence.t5   = rX(30);};
  if (divergence.t6   == rX(31)) then  { counter = counter + 1; divergence.t6   = rX(31);  } else { divergence.t6   = rX(31);};
  
  if (counter > max_diverged & values_to_check_divergence.initial_diverg) then { 
    is_diverged = true; 
  }
  else { 
    if (counter > max_diverged) then {
      values_to_check_divergence.initial_diverg = true; 
    } 
  };
  return is_diverged;

}


function isRVC(h : half) -> bool = not(h[1 .. 0] == 0b11)



$ifdef _RV32S

  function fetch_I() -> FetchResult ={

  
    /* fetch PC check for extensions: extensions return a transformed PC to fetch,
    * but any exceptions use the untransformed PC.
    */
    match ext_fetch_check_pc(PC, PC) {
      Ext_FetchAddr_Error(e)   => F_Ext_Error(e),
      Ext_FetchAddr_OK(use_pc) => {
        // if (vector_to_store.index != 0) then clear_vector();
        if   (use_pc[0] != bitzero | (use_pc[1] != bitzero & not(extensionEnabled(Ext_C))))
        then F_Error(E_Fetch_Addr_Align(), PC)
        else match translateAddr(use_pc, Execute()) {
          TR_Failure(e, _)     => F_Error(e, PC),
          TR_Address(ppclo, _) => {
          


            if (cur_privilege == User & (signed(PC - 0x80000000) >= 0)) then {
              if (force_debug_divergence) then {
                print_endline("May your execution has an infinity loop.");
                force_debug_divergence = false;
                debug_mode = debug_C();
              }else {
                debug_mode = debug_C();
              }
            } else if (cur_privilege == User & (signed(PC - 0x80000000) < 0)) then {
              if (force_debug_divergence) then {
                // print_endline("May your execution has an infinity loop.");
                // force_debug_divergence = false;
                // debug_mode = debug_C();
                print_endline("Divergence execution detected: Aborted.");
                exit();
              };
              // else {
              //   debug_mode = debug_C();
              // }
            }
            
            
            else {
              if (((cur_privilege == Machine) & sizeof(xlen) == 32) & (signed(PC - 0x80000000) >= 0)) then {
                if (force_debug_divergence) then {
                  print_endline("May your execution has an infinity loop.");
                  force_debug_divergence = false;
                };
                debug_mode = debug_C();   
              } else if ((cur_privilege == Machine & sizeof(xlen) == 32) & ( signed(PC - 0x80000000) < 0) & ( signed(PC - 0x00001000) >= 0) & force_debug_divergence) then {
                  print_endline("Divergence execution detected: Aborted.");
                  exit();
              }

            };

          /* Definicion para 64 bits */
            /* split instruction fetch into 16-bit granules to handle RVC, as
            * well as to generate precise fault addresses in any fetch
            * exceptions.
            */


          // Aqui se tiene que hacer la comprobación de que la instruccion está almacenada en la caché
          
          // read_cache(Cache_inst, LL1, pc, 2) , por ejemplo
          

          // Si está lee de la cache el codigo de la instruccion y lo devuelve, si no lanzas el fallo y
          // escribes un bloque de caché (en 32 bits son 4 instrucciones en 64 bits son 8 instrucciones)
            print_reg("Cache prefetch " ^ BitStr(PC));
            match read_cache(Cache_inst, LL1, ppclo, 2) {
              (ilo, true) => {
                if   isRVC(ilo)
                then F_RVC(ilo)
                else {
                  PC_hi : xlenbits = PC + 2;
                  match ext_fetch_check_pc(PC, PC_hi) {
                    Ext_FetchAddr_Error(e)      => F_Ext_Error(e),
                    Ext_FetchAddr_OK(use_pc_hi) => {
                      match translateAddr(use_pc_hi, Execute()) {
                        TR_Failure(e, _)     => F_Error(e, PC_hi),
                        TR_Address(ppchi, _) => {
                          match read_cache(Cache_inst, LL1, ppchi, 2) {
                            (ihi, true) => F_Base(append(ihi, ilo))
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
           /* // match mem_read(Execute(), ppclo, 2, false, false, false) {
              MemException(e) => F_Error(e, PC),
              MemValue(ilo)   => {
                if   isRVC(ilo)
                then F_RVC(ilo)
                else {
                  // fetch PC check for the next instruction granule 
                  // print_endline("LEo aqui la instruccion.");
                  PC_hi : xlenbits = PC + 2;
                  match ext_fetch_check_pc(PC, PC_hi) {
                    Ext_FetchAddr_Error(e)      => F_Ext_Error(e),
                    Ext_FetchAddr_OK(use_pc_hi) => {
                      match translateAddr(use_pc_hi, Execute()) {
                        TR_Failure(e, _)     => F_Error(e, PC_hi),
                        TR_Address(ppchi, _) => {
                          match mem_read(Execute(), ppchi, 2, false, false, false) {
                            MemException(e) => F_Error(e, PC_hi),
                            MemValue(ihi)   => F_Base(append(ihi, ilo))
                          }
                        }
                      }
                    }
                  }
                }
              }
            }*/
          }
        }
      }
  }
}

  function fetch_A() -> FetchResult ={

  
    /* fetch PC check for extensions: extensions return a transformed PC to fetch,
    * but any exceptions use the untransformed PC.
    */
    match ext_fetch_check_pc(PC, PC) {
      Ext_FetchAddr_Error(e)   => F_Ext_Error(e),
      Ext_FetchAddr_OK(use_pc) => {
        // if (vector_to_store.index != 0) then clear_vector();
        if   (use_pc[0] != bitzero | (use_pc[1] != bitzero & not(extensionEnabled(Ext_C))))
        then F_Error(E_Fetch_Addr_Align(), PC)
        else match translateAddr(use_pc, Execute()) {
          TR_Failure(e, _)     => F_Error(e, PC),
          TR_Address(ppclo, _) => {
          


            if (cur_privilege == User & (signed(PC - 0x80000000) >= 0)) then {
              if (force_debug_divergence) then {
                print_endline("May your execution has an infinity loop.");
                force_debug_divergence = false;
                debug_mode = debug_C();
              }else {
                debug_mode = debug_C();
              }
            } else if (cur_privilege == User & (signed(PC - 0x80000000) < 0)) then {
              if (force_debug_divergence) then {
                // print_endline("May your execution has an infinity loop.");
                // force_debug_divergence = false;
                // debug_mode = debug_C();
                print_endline("Divergence execution detected: Aborted.");
                exit();
              };
              // else {
              //   debug_mode = debug_C();
              // }
            }
            
            
            else {
              if (((cur_privilege == Machine) & sizeof(xlen) == 32) & (signed(PC - 0x80000000) >= 0)) then {
                if (force_debug_divergence) then {
                  print_endline("May your execution has an infinity loop.");
                  force_debug_divergence = false;
                };
                debug_mode = debug_C();   
              } else if ((cur_privilege == Machine & sizeof(xlen) == 32) & ( signed(PC - 0x80000000) < 0) & ( signed(PC - 0x00001000) >= 0) & force_debug_divergence) then {
                  print_endline("Divergence execution detected: Aborted.");
                  exit();
              }

            };

          /* Definicion para 64 bits */
            /* split instruction fetch into 16-bit granules to handle RVC, as
            * well as to generate precise fault addresses in any fetch
            * exceptions.
            */


          // Aqui se tiene que hacer la comprobación de que la instruccion está almacenada en la caché
          
          // read_cache(Cache_inst, LL1, pc, 2) , por ejemplo
          

          // Si está lee de la cache el codigo de la instruccion y lo devuelve, si no lanzas el fallo y
          // escribes un bloque de caché (en 32 bits son 4 instrucciones en 64 bits son 8 instrucciones)

            match read_cache(Cache_all, LL1, ppclo, 2) {
              (ilo, true) => {
                if   isRVC(ilo)
                then F_RVC(ilo)
                else {
                  PC_hi : xlenbits = PC + 2;
                  match ext_fetch_check_pc(PC, PC_hi) {
                    Ext_FetchAddr_Error(e)      => F_Ext_Error(e),
                    Ext_FetchAddr_OK(use_pc_hi) => {
                      match translateAddr(use_pc_hi, Execute()) {
                        TR_Failure(e, _)     => F_Error(e, PC_hi),
                        TR_Address(ppchi, _) => {
                          match read_cache(Cache_all, LL1, ppchi, 2) {
                            (ihi, true) => F_Base(append(ihi, ilo))
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
            /*match mem_read(Execute(), ppclo, 2, false, false, false) {
              MemException(e) => F_Error(e, PC),
              MemValue(ilo)   => {
                if   isRVC(ilo)
                then F_RVC(ilo)
                else {
                  // fetch PC check for the next instruction granule
                  // print_endline("LEo aqui la instruccion.");
                  PC_hi : xlenbits = PC + 2;
                  match ext_fetch_check_pc(PC, PC_hi) {
                    Ext_FetchAddr_Error(e)      => F_Ext_Error(e),
                    Ext_FetchAddr_OK(use_pc_hi) => {
                      match translateAddr(use_pc_hi, Execute()) {
                        TR_Failure(e, _)     => F_Error(e, PC_hi),
                        TR_Address(ppchi, _) => {
                          match mem_read(Execute(), ppchi, 2, false, false, false) {
                            MemException(e) => F_Error(e, PC_hi),
                            MemValue(ihi)   => F_Base(append(ihi, ilo))
                          }
                        }
                      }
                    }
                  }
                }
              }
            }*/
          }
        }
      }
  }
}

$endif _RV32S




/* Definicion para 64 bits */
$ifdef _RV64S

  function fetch() -> FetchResult =
    /* fetch PC check for extensions: extensions return a transformed PC to fetch,
    * but any exceptions use the untransformed PC.
    */
    
    match ext_fetch_check_pc(PC, PC) {
      Ext_FetchAddr_Error(e)   => F_Ext_Error(e),
      Ext_FetchAddr_OK(use_pc) => {
        // if (vector_to_store.index != 0) then clear_vector();
        print_reg("use pc: " ^ BitStr(use_pc));
        if   (use_pc[0] != bitzero | (use_pc[1] != bitzero & not(extensionEnabled(Ext_C))))
        then F_Error(E_Fetch_Addr_Align(), PC)
        else match translateAddr(use_pc, Execute()) {
          TR_Failure(e, _)     => F_Error(e, PC),
          TR_Address(ppclo, _) => {

          /* Definicion para 64 bits */

          if (cur_privilege == User & ( signed(0x0000000000020000 - PC) > 0) & ( signed(PC) >= 0)) then {
            if (force_debug_divergence) then {
              print_endline("May your execution has an infinity loop.");
              force_debug_divergence = false;
              debug_mode = debug_C();
            }else {
              debug_mode = debug_C();
            }
          } else if (cur_privilege == User) /*& ( signed(0x0000000000020000 - PC) > 0) & ( signed(PC) >= 0))*/ then {
            if (force_debug_divergence) then {
              // print_endline("May your execution has an infinity loop.");
              // force_debug_divergence = false;
              // debug_mode = debug_C();
              print_endline("Divergence execution detected: Aborted.");
              exit();
            };
            // else {
            //   debug_mode = debug_C();
            // }
          }
          else{
            // print_reg("PC resta = "^ BitStr((PC - 0x0000A00000000000)));
            // print_reg("PC a leer: "^ BitStr(PC));
            if ((cur_privilege == Machine & sizeof(xlen) >= 64) & ( signed(0x0000000000020000 - PC) > 0) & ( signed(PC) >= 0)) then {
              if (force_debug_divergence) then {print_endline("May your execution has an infinity loop.");force_debug_divergence = false;};
                  debug_mode = debug_C();

                
            } else if ((cur_privilege == Machine & sizeof(xlen) >= 64) & ( signed(PC - 0xFFFFFFFF80000000) > 0) & force_debug_divergence) then {
              print_endline("Divergence execution detected: Aborted.");
              exit();
            };

          };

            /* split instruction fetch into 16-bit granules to handle RVC, as
            * well as to generate precise fault addresses in any fetch
            * exceptions.
            */

            // Sustitucion por funcion de prefectch
            print_endline("Leemos de cache");
            match read_cache(Cache_inst, LL1, ppclo, 2) {
              (ilo, true) => { print_endline("Cache leida");
                if   isRVC(ilo)
                then F_RVC(ilo)
                else {
                  PC_hi : xlenbits = PC + 2;
                  match ext_fetch_check_pc(PC, PC_hi) {
                    Ext_FetchAddr_Error(e)      => F_Ext_Error(e),
                    Ext_FetchAddr_OK(use_pc_hi) => {
                      match translateAddr(use_pc_hi, Execute()) {
                        TR_Failure(e, _)     => F_Error(e, PC_hi),
                        TR_Address(ppchi, _) => {
                          match read_cache(Cache_inst, LL1, ppchi, 2) {
                            (ihi, true) => F_Base(append(ihi, ilo))
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // match mem_read(Execute(), ppclo, 2, false, false, false) {
            //   MemException(e) => F_Error(e, PC),
            //   MemValue(ilo)   => {
            //     if   isRVC(ilo)
            //     then F_RVC(ilo)
            //     else {
            //       /* fetch PC check for the next instruction granule */
            //       PC_hi : xlenbits = PC + 2;
            //       match ext_fetch_check_pc(PC, PC_hi) {
            //         Ext_FetchAddr_Error(e)      => F_Ext_Error(e),
            //         Ext_FetchAddr_OK(use_pc_hi) => {
            //           match translateAddr(use_pc_hi, Execute()) {
            //             TR_Failure(e, _)     => F_Error(e, PC_hi),
            //             TR_Address(ppchi, _) => {
            //               match mem_read(Execute(), ppchi, 2, false, false, false) {
            //                 MemException(e) => F_Error(e, PC_hi),
            //                 MemValue(ihi)   => F_Base(append(ihi, ilo))
            //               }
            //             }
            //           }
            //         }
            //       }
            //     }
            //   }
            // }
          }
        }
      }
    }


$endif _RV64S

