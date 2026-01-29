/*

Espacion reservado para la generacion de nuevas instrucciones por ejemplo
    myadd r0, r1 
    Comportamiento: r0 = r0 +r1
*/


union clause ast = CREATOR : (regidx, regidx, cop)

mapping encdec_creator : cop <-> bits(7) = {
    CREATOR_ADDI <-> 0b0001011
}
 
mapping clause encdec = CREATOR(rd, rs1, op)
    <-> 0b000000000000 @ rs1 @ 0b000 @ rd @ encdec_creator(op)

function clause execute CREATOR(rd, rs1, op) = {
    let rd_val = X(rd);
    let rs1_val = X(rs1);
    let result : xlenbits = match op {
        CREATOR_ADDI => rd_val + rs1_val
    };
    X(rd) = result;
    RETIRE_SUCCESS
}

mapping creator_mnemonic : cop <-> string = {
    CREATOR_ADDI <-> "myadd"
}

mapping clause assembly = CREATOR(rd, rs1, op)
    <-> creator_mnemonic(op) ^ spc() ^ reg_name(rd) ^ sep() ^ reg_name(rs1) 