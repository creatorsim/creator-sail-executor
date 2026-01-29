/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* The definition for the sequential model. */

val send_error = {c: "send_error_c"} : unit -> unit
function clause execute (RISCV_JALR(imm, rs1, rd)) = {
/* For the sequential model, the memory-model definition doesn't work directly
 * if rs1 = rd.  We would effectively have to keep a regfile for reads and another for
 * writes, and swap on instruction completion.  This could perhaps be optimized in
 * some manner, but for now, we just keep a reordered definition to improve simulator
 * performance.
 */
  if (unsigned(rs1) == 1 & unsigned(rd) == 0) then {
    if not(call_convention(2)) then { /* Send a signal to notify to the user that he doesn't follow the call convention in the function*/
      send_error(); 
    };
  } else if (unsigned(rs1) == 1 & unsigned(rd) == 1) then {
    if (call_convention(1)) then {
      print_endline("");
    };
  };
  let t : xlenbits = X(rs1) + sign_extend(imm);
  /* Extensions get the first checks on the prospective target address. */
  match ext_control_check_addr(t) {
    Ext_ControlAddr_Error(e) => {
      ext_handle_control_check_error(e);
      RETIRE_FAIL
    },
    Ext_ControlAddr_OK(addr) => {
      let target = [addr with 0 = bitzero];  /* clear addr[0] */
      if bit_to_bool(target[1]) & not(extensionEnabled(Ext_C)) then {
        handle_mem_exception(target, E_Fetch_Addr_Align());
        RETIRE_FAIL
      } else {
        X(rd) = get_next_pc();
        set_next_pc(target);
        RETIRE_SUCCESS
      }
    }
  }
}
