// transform.js
export default function transformer(file, api) {
  const j = api.jscodeshift;
  const root = j(file.source);
  const program = root.get().node.program;

  // ============================================================
  // Helpers: imports (avoid duplicates with same source+specifiers)
  // ============================================================
  function normalizeSpecifiers(specifiers = []) {
    return specifiers
      .map((s) => {
        if (s.type === 'ImportSpecifier') {
          const imported = s.imported?.name || '';
          const local = s.local?.name || imported;
          return `named:${imported}=>${local}`;
        }
        if (s.type === 'ImportDefaultSpecifier') {
          return `default:${s.local?.name || ''}`;
        }
        if (s.type === 'ImportNamespaceSpecifier') {
          return `ns:${s.local?.name || ''}`;
        }
        return 'other';
      })
      .sort()
      .join('|');
  }

  function importExists(moduleName, specifiers) {
    const want = normalizeSpecifiers(specifiers);
    return (
      root
        .find(j.ImportDeclaration, { source: { value: moduleName } })
        .filter((p) => normalizeSpecifiers(p.node.specifiers) === want)
        .size() > 0
    );
  }

  function makeNamedImport(moduleName, names) {
    return j.importDeclaration(
      names.map((n) => j.importSpecifier(j.identifier(n))),
      j.literal(moduleName)
    );
  }

  // ============================================================
  // Helpers: top-level vars / exports
  // ============================================================
  function exportedVarExists(name) {
    return (
      root
        .find(j.ExportNamedDeclaration)
        .filter((p) => {
          const decl = p.node.declaration;
          if (!decl || decl.type !== 'VariableDeclaration') return false;
          return decl.declarations.some(
            (d) => d.id.type === 'Identifier' && d.id.name === name
          );
        })
        .size() > 0
    );
  }

  function makeExportedVar(name, initValue) {
    return j.exportNamedDeclaration(
      j.variableDeclaration('var', [
        j.variableDeclarator(j.identifier(name), initValue),
      ]),
      []
    );
  }

  function topLevelVarExists(name) {
    return (
      root
        .find(j.VariableDeclarator, { id: { type: 'Identifier', name } })
        .filter((p) => {
          // Ensure it's top-level (Program -> VariableDeclaration)
          const vd = p.parent?.node;
          const stmt = p.parent?.parent?.node;
          return (
            vd?.type === 'VariableDeclaration' &&
            stmt?.type === 'VariableDeclaration' // defensive
          );
        })
        .size() > 0 ||
      // also allow `var name;` as VariableDeclaration without declarator? (it always has declarator)
      root.find(j.VariableDeclaration).filter((p) =>
        p.node.declarations.some((d) => d.id.type === 'Identifier' && d.id.name === name)
      ).size() > 0
    );
  }

  // ============================================================
  // 1) Insert imports + `export var userMode32` + `var insn_number;`
  // ============================================================
  const desiredImports = [
    makeNamedImport('@/core/assembler/assembler.mjs', [
      'instructions',
      'tag_instructions',
    ]),
    makeNamedImport('@/core/register/registerOperations.mjs', [
      'readRegister',
      'writeRegister',
      'notifyRegisterUpdate',
    ]),
    makeNamedImport('@/core/register/registerLookup.mjs', [
      'crex_findReg_bytag',
      'crex_findReg',
    ]),
    makeNamedImport('@/core/core.mjs', [
      'status',
      'set_execution_mode',
      'PC_REG_INDEX',
      'REGISTERS',
      'getPC',
      'main_memory',
      'config_cache',
      'L1_cache_memory',
      'L1_I_cache_memory',
      'L1_D_cache_memory',
      'L2_D_cache_memory',
      'L2_I_cache_memory',
      'L2_cache_memory',
      'updateCacheMem',
    ]),
    makeNamedImport('@/core/assembler/assembler.mjs', ['setInstructions']),
    makeNamedImport('../../IO.mjs', ['display_print']),
    makeNamedImport('@/core/capi/syscall.mts', ['SYSCALL']),
    makeNamedImport('@/core/events.mts', ['coreEvents']),
    makeNamedImport('@/web/utils.mjs', ['show_notification']),
    makeNamedImport('@/web/utils.mjs', [
      'reset_disable',
      'instruction_disable',
      'run_disable',
      'stop_disable',
      'isFinished',
    ]),
    makeNamedImport('../../../core.mjs', ['architecture']),
    makeNamedImport('@/core/register/registerGlowState.mjs', [
      'clearAllRegisterGlows',
    ]),
  ];

  // insert imports after header/banner (leading comments / directives)
  let insertAt = 0;
  while (insertAt < program.body.length) {
    const node = program.body[insertAt];
    if (node.type === 'ImportDeclaration') break;

    // keep directive prologues like "use strict";
    if (node.type === 'ExpressionStatement' && node.expression?.type === 'Literal') {
      insertAt++;
      continue;
    }

    if (node.leadingComments && node.leadingComments.length > 0) {
      insertAt++;
      continue;
    }

    break;
  }

  const importsToInsert = [];
  for (const imp of desiredImports) {
    if (!importExists(imp.source.value, imp.specifiers || [])) {
      importsToInsert.push(imp);
    }
  }
  if (importsToInsert.length > 0) {
    program.body.splice(insertAt, 0, ...importsToInsert);
  }

  // export var userMode32 = false;
  if (!exportedVarExists('userMode32')) {
    // place after the last import
    let lastImportIndex = -1;
    program.body.forEach((node, idx) => {
      if (node.type === 'ImportDeclaration') lastImportIndex = idx;
    });
    program.body.splice(lastImportIndex + 1, 0, makeExportedVar('userMode32', j.literal(false)));
  }

  // var insn_number;
  if (!root.find(j.VariableDeclaration).filter((p) =>
    p.parent?.node?.type === 'Program' &&
    p.node.declarations.some((d) => d.id.type === 'Identifier' && d.id.name === 'insn_number')
  ).size()) {
    // put it right after userMode32 export if possible
    const exportIdx = program.body.findIndex(
      (n) =>
        n.type === 'ExportNamedDeclaration' &&
        n.declaration?.type === 'VariableDeclaration' &&
        n.declaration.declarations?.some((d) => d.id?.name === 'userMode32')
    );
    const insnDecl = j.variableDeclaration('var', [j.variableDeclarator(j.identifier('insn_number'), null)]);
    program.body.splice((exportIdx >= 0 ? exportIdx + 1 : insertAt), 0, insnDecl);
  }

  // ============================================================
  // 2) Insert init block inside: return function (Module) { ... }
  // ============================================================
  const initSnippet = `
document.app.$data.is_breakpoint = instructions[0].Break;
var pc_sail = crex_findReg_bytag("program_counter");
var pc_min = architecture.memory_layout.text.start;
var pc_max = architecture.memory_layout.text.end;
var hiden_executed, hiden_next_execute;

var registers_before_function = [
  { name: "t0", can_operate : false},
  { name: "t1", can_operate : false},
  { name: "t2", can_operate : false},
  { name: "t3", can_operate : false},
  { name: "t4", can_operate : false},
  { name: "t5", can_operate : false},
  { name: "t6", can_operate : false},
  { name: "s0", can_operate : false},
  { name: "s1", can_operate : false},
  { name: "s2", can_operate : false},
  { name: "s3", can_operate : false},
  { name: "s4", can_operate : false},
  { name: "s5", can_operate : false},
  { name: "s6", can_operate : false},
  { name: "s7", can_operate : false},
  { name: "s8", can_operate : false},
  { name: "s9", can_operate : false},
  { name: "s10", can_operate : false},
  { name: "s11", can_operate : false}
]
var callstack_convention = [];
var inside_function = false;
`;
  const initStatements = j(initSnippet).get().node.program.body;

  function functionBodyHasNeedle(fnBody, needle) {
    return fnBody.some((st) => j(st).toSource().includes(needle));
  }

  root
    .find(j.ReturnStatement, { argument: { type: 'FunctionExpression' } })
    .filter((p) => {
      const fn = p.node.argument;
      return (
        fn &&
        fn.type === 'FunctionExpression' &&
        fn.params?.length === 1 &&
        fn.params[0].type === 'Identifier' &&
        fn.params[0].name === 'Module'
      );
    })
    .forEach((p) => {
      const fn = p.node.argument;
      if (!functionBodyHasNeedle(fn.body.body, 'document.app.$data.is_breakpoint')) {
        fn.body.body.unshift(...initStatements);
      }
    });

  // ============================================================
  // 3) Insert big parsing/regex block before `var out = ...`
  // ============================================================
  const bigBlock = `

    // const instructionExp = /\[(\d+)\] \[(\w+)\]: 0x([0-9A-Fa-f]+) \(0x([0-9A-Fa-f]+)\) (\w+) ([^,]+), ([^,]+)(?:, (.+))?/;
    var instructionExp = /\[(\d+)\] \[(\w+)\]: 0x([0-9A-Fa-f]+) \(0x([0-9A-Fa-f]+)\) ([\w.]+)(?: ([^,]+), ([^,]+)(?:, (.+))?)?/;
    var registerExp = /([xf]\d+) (<-) 0x([0-9A-Fa-f]+)/; // /(x\d+) (<-|->) 0x([0-9A-Fa-f]+)/;
    var vectorExp = /(v\d+) (<-) 0x([0-9A-Fa-f]+)/;
    var memoryExp = /mem\[0x([0-9A-Fa-f]+)\]\s*(<-|->)\s*0x([0-9A-Fa-f]+)/;
    var CSRTypeExp = /(CSR\S*)\s+(\S+)\s+(\S+)\s+(0x)([\dA-Fa-f]{1,8})/;
    var CSRExp = /^(CSR)\s+(\w+)\s+(<-|->)\s+0x([0-9a-fA-F]+)(?:\s+(.*))?$/;
    var jumpExp = /Next_PC:\s*(0x[0-9a-fA-F]+)/;
    var cacheExp = /^\[(\d+)\]\s+(L1_I|L1_D|L1|L2|L2_I|L2_D):\s*\((0x[0-9A-Fa-f]+)\)\s$/;
    var configCacheExp = /^Configuration:\s*([A-Za-z_][A-Za-z0-9_]*)\s*<-\s*(\S+)\s*$/;

    // var displayExp = /^[A-Za-z\s]+:\s*(.*)$/;
    // var displayExp = /^([\w\s]+):\s*(.*)$/;
    var displayExp = /^ECALL\s+(SIGNED|UNSIGNED|STRING|CHAR|FLOAT|DOUBLE):\s*(.+)$/;
    var instoper = "";
    var syscall_print_code = -1;
    var prev_add_to_jump;

    function updateCacheStat(index, access, data="") {
      switch(access) {
        case "Cache L1 hit inst":
          if (instructions[index].L1_I == 0)
            instructions[index].L1_I = 3;
          else if (instructions[index].L1_I == 3)
            instructions[index].L1_I = 3;
          else if (instructions[index].L1_I == 4)
            instructions[index].L1_I = 1;
          break;
        case "Cache L1 miss inst":
          if (instructions[index].L1_I == 0)
            instructions[index].L1_I = 4;
          else if (instructions[index].L1_I == 4)
            instructions[index].L1_I = 4;
          else if (instructions[index].L1_I == 3)
            instructions[index].L1_I = 1;
          break;
        case "Cache L1 miss":
          if (instructions[index].L1_I == 0)
            instructions[index].L1_I = 4;
          else if (instructions[index].L1_I == 4)
            instructions[index].L1_I = 4;
          else if (instructions[index].L1_I == 3)
            instructions[index].L1_I = 1;
          break;
        case "Cache L1 hit data":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L1_D == 0)
              main_memory[parseInt(data, 16)].L1_D = 3;
            else if (main_memory[memindex].L1_D == 3)
              main_memory[parseInt(data, 16)].L1_D = 3;
            else if (main_memory[memindex].L1_D == 4)
              main_memory[parseInt(data, 16)].L1_D = 1;
          }
          if (instructions[index].L1_D == 0)
            instructions[index].L1_D = 3;
          else if (instructions[index].L1_D == 3)
            instructions[index].L1_D = 3;
          else if (instructions[index].L1_D == 4)
            instructions[index].L1_D = 1;
          break;
        case "Cache L1 miss data":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L1_D == 0)
              main_memory[parseInt(data, 16)].L1_D = 4;
            else if (main_memory[memindex].L1_D == 4)
              main_memory[parseInt(data, 16)].L1_D = 4;
            else if (main_memory[memindex].L1_D == 3)
              main_memory[parseInt(data, 16)].L1_D = 1;
          }
          if (instructions[index].L1_D == 0)
            instructions[index].L1_D = 4;
          else if (instructions[index].L1_D == 4)
            instructions[index].L1_D = 4;
          else if (instructions[index].L1_D == 3)
            instructions[index].L1_D = 1;
          break;
        case "Cache L1_I hit":
          if (instructions[index].L1_I == 0)
            instructions[index].L1_I = 3;
          else if (instructions[index].L1_I == 4)
            instructions[index].L1_I = 1;
          break;
        case "Cache L1_I miss":
          if (instructions[index].L1_I == 0)
            instructions[index].L1_I = 4;
          else if (instructions[index].L1_I == 3)
            instructions[index].L1_I = 1;
          else if (instructions[index].L1_I == 4)
            instructions[index].L1_I = 4;
          break;
        case "Cache L1_D hit":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L1_D == 0)
              main_memory[parseInt(data, 16)].L1_D = 3;
            else if (main_memory[memindex].L1_D == 3)
              main_memory[parseInt(data, 16)].L1_D = 3;
            else if (main_memory[memindex].L1_D == 4)
              main_memory[parseInt(data, 16)].L1_D = 1;
          }
          if (instructions[index].L1_D == 0)
            instructions[index].L1_D = 3;
          else if (instructions[index].L1_D == 3)
            instructions[index].L1_D = 3;
          else if (instructions[index].L1_D == 4)
            instructions[index].L1_D = 1;
          break;
        case "Cache L1_D miss":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L1_D == 0)
              main_memory[parseInt(data, 16)].L1_D = 4;
            else if (main_memory[memindex].L1_D == 4)
              main_memory[parseInt(data, 16)].L1_D = 4;
            else if (main_memory[memindex].L1_D == 3)
              main_memory[parseInt(data, 16)].L1_D = 1;
          }
          if (instructions[index].L1_D == 0)
            instructions[index].L1_D = 4;
          else if (instructions[index].L1_D == 4)
            instructions[index].L1_D = 4;
          else if (instructions[index].L1_D == 3)
            instructions[index].L1_D = 1;
          break;
        case "Cache L2 hit inst":
          if (instructions[index].L2_I == 0)
            instructions[index].L2_I = 3;
          else if (instructions[index].L2_I == 3)
            instructions[index].L2_I = 3;
          else if (instructions[index].L2_I == 4)
            instructions[index].L2_I = 1;
          break;
        case "Cache L2 miss inst":
          if (instructions[index].L2_I == 0)
            instructions[index].L2_I = 4;
          else if (instructions[index].L2_I == 4)
            instructions[index].L2_I = 4;
          else if (instructions[index].L2_I == 3)
            instructions[index].L2_I = 1;
          break;
        case "Cache L2_I hit":
          if (instructions[index].L2_I == 0)
            instructions[index].L2_I = 3;
          else if (instructions[index].L2_I == 3)
            instructions[index].L2_I = 3;
          else if (instructions[index].L2_I == 4)
            instructions[index].L2_I = 1;
          break;
        case "Cache L2_I miss":
          if (instructions[index].L2_I == 0)
            instructions[index].L2_I = 4;
          else if (instructions[index].L2_I == 4)
            instructions[index].L2_I = 4;
          else if (instructions[index].L2_I == 3)
            instructions[index].L2_I = 1;
          break;
        case "Cache L2 hit data":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L2_D == 0)
              main_memory[parseInt(data, 16)].L2_D = 3;
            else if (main_memory[memindex].L2_D == 3)
              main_memory[parseInt(data, 16)].L2_D = 3;
            else if (main_memory[memindex].L2_D == 4)
              main_memory[parseInt(data, 16)].L2_D = 1;
          }
          if (instructions[index].L2_D == 0)
            instructions[index].L2_D = 3;
          else if (instructions[index].L2_D == 3)
            instructions[index].L2_D = 3;
          else if (instructions[index].L2_D == 4)
            instructions[index].L2_D = 1;
          break;
        case "Cache L2 miss data":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L2_D == 0)
              main_memory[parseInt(data, 16)].L2_D = 4;
            else if (main_memory[memindex].L2_D == 4)
              main_memory[parseInt(data, 16)].L2_D = 4;
            else if (main_memory[memindex].L2_D == 3)
              main_memory[parseInt(data, 16)].L2_D = 1;
          }
          if (instructions[index].L2_D == 0)
            instructions[index].L2_D = 4;
          else if (instructions[index].L2_D == 4)
            instructions[index].L2_D = 4;
          else if (instructions[index].L2_D == 3)
            instructions[index].L2_D = 1;
          break;
        case "Cache L2_D hit":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L2_D == 0)
              main_memory[parseInt(data, 16)].L2_D = 3;
            else if (main_memory[memindex].L2_D == 3)
              main_memory[parseInt(data, 16)].L2_D = 3;
            else if (main_memory[memindex].L2_D == 4)
              main_memory[parseInt(data, 16)].L2_D = 1;
          }
          if (instructions[index].L2_D == 0)
            instructions[index].L2_D = 3;
          else if (instructions[index].L2_D == 3)
            instructions[index].L2_D = 3;
          else if (instructions[index].L2_D == 4)
            instructions[index].L2_D = 1;
          break;
        case "Cache L2_D miss":
          if(data !== "") {
            let lastv = parseInt(data[data.length - 1], 16);
            if (lastv < 4) data = data.slice(0, -1) + "0";
            else if (lastv < 8) data = data.slice(0, -1) + "4";
            else if (lastv < 12) data = data.slice(0, -1) +  "8";
            else data = data.slice(0, -1) + "C";
            let memindex = parseInt(data, 16);
            if (main_memory[memindex].L2_D == 0)
              main_memory[parseInt(data, 16)].L2_D = 4;
            else if (main_memory[memindex].L2_D == 4)
              main_memory[parseInt(data, 16)].L2_D = 4;
            else if (main_memory[memindex].L2_D == 3)
              main_memory[parseInt(data, 16)].L2_D = 1;
          }
          if (instructions[index].L2_D == 0)
            instructions[index].L2_D = 4;
          else if (instructions[index].L2_D == 4)
            instructions[index].L2_D = 4;
          else if (instructions[index].L2_D == 3)
            instructions[index].L2_D = 1;
          break;
      }

    }

    async function check_call_convention_temp_regs(instMatch) {
      if(((instMatch[7] != undefined && (instMatch[7].includes("t") || (instMatch[7].includes("s") && !instMatch[7].includes("sp")) ) ) || (instMatch[8] != undefined && (instMatch[8].includes("t") || (instMatch[8].includes("s") && !instMatch[8].includes("sp")) ))) && instMatch[6] !== undefined && inside_function) {
        if((instMatch[5] != "li" && instMatch[5] != "lui" && instMatch[5] != "la") ){
          for (var i = 0; i < callstack_convention[callstack_convention.length - 1].length; i++ ){
            (callstack_convention[callstack_convention.length - 1][i].name === instMatch[7] || callstack_convention[callstack_convention.length - 1][i].name === instMatch[8]) &&
            (callstack_convention[callstack_convention.length - 1][i].can_operate === false) ? show_notification("Possible failure in the parameter passing convention", "warning") : 0 ;
          }

            // callstack_convention[callstack_convention.length - 1].name

        }
      }
      if (instMatch[6] !== undefined && (instMatch[6].includes("t") || (instMatch[6].includes("s") && !instMatch[6].includes("sp"))) && inside_function) {
        for (var i = 0; i < callstack_convention[callstack_convention.length - 1].length; i++ ){
          callstack_convention[callstack_convention.length - 1][i].can_operate = (callstack_convention[callstack_convention.length - 1][i].name === instMatch[6]) ? true : callstack_convention[callstack_convention.length - 1][i].can_operate;
        }
      }
    }

    // var to_measure = "";
    var start_m, start_m;
    var cache_inst;

    function writeMemory(value, addr) {
      // Primero pasar el valor al formato hexadecimal por pares
      if (value.startsWith("0x"))
        value = value.slice(2);
      if (value.length % 2 !== 0)
        value = "0" + value;

      // const bytes = new Uint8Array(value.length / 2);
      for (let i = 0; i < value.length / 2; i ++) {
        main_memory.write((addr + BigInt(i)), Number("0x" + value.substring(i*2, i * 2 + 2)));
      }

      // if (memoMatch[2] === '<-'){
      //     switch(op){
      //       case 'sh': // Para almacenar un half
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'half');
      //       break;
      //       case 'sb': // Para almacenar un byte
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'byte');
      //       break;
      //       case 'sw': // Para almacenar un int/word
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'word');
      //       break;
      //       case 'fsw': // Para almacenar un float
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'float');
      //       break;
      //       case 'fsd': // Para almacenar un double
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'double');
      //       break;
      //       case 'vse8.v':
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'byte');
      //         break;
      //       case 'vse16.v':
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'half');
      //         break;
      //       case 'vse32.v':
      //       writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'word');
      //         break;
      //       case 'vse64.v':
      //         writeMemory(memoMatch[3], parseInt(memoMatch[1], 16), 'double');
      //         break;
      //       default:
      //         break;
      //     }
      //   }
    }

    Module['print'] = function (message) {
      if(message === "err call_convenction"){
        show_notification("Possible failure in the parameter passing convention", "warning");
      }

      var next_add_to_jump;
      let instMatch        = message.match(instructionExp);
      let regiMatch        = message.match(registerExp);
      let memoMatch        = message.match(memoryExp);
      let printMatch       = message.match(displayExp);
      let CSRMatch         = message.match(CSRTypeExp);
      let CSREMatch        = message.match(CSRExp);
      let vectorMatch      = message.match(vectorExp);
      let jumpMatch        = message.match(jumpExp);
      let cacheMatch       = message.match(cacheExp);
      let configCacheMatch = message.match(configCacheExp);

      if (message.startsWith("Cache") || message.startsWith("Next_PC:")){
        if (message.includes("Cache prefetch")) {
          let newpc = message.substring(15,message.length).toLowerCase();
          cache_inst = instructions.findIndex(insn => insn.Address === newpc);
        } else if (message.includes("Next_PC:")) {
          let newpc = message.substring(9, message.length).toLowerCase();
          cache_inst = instructions.findIndex(insn => insn.Address == newpc);
        }
        if (cache_inst != -1 && document.app.$data.execution_mode_run === 1) {
          let hexmatch = message.match(/0x[0-9A-Fa-f]+$/);
          if (hexmatch && !message.startsWith("Cache prefetch")) {
            let hexa = hexmatch[0];
            message = message.replace(/on:\s*0x[0-9A-Fa-f]+$/, "").trim();
            updateCacheStat(cache_inst, message, hexa);
          }else {
            updateCacheStat(cache_inst, message);
          }

        }
      }

      if (message === "May your execution has an infinity loop."){
        document.app.$data.execution_mode_run = 1;
        show_notification(message, "danger");
        instructions[hiden_executed]._rowVariant = "info";
        instructions[hiden_next_execute]._rowVariant = "success";
      }

      if (jumpMatch){
        const current_ins = instructions.findIndex(insn => insn.Address === (jumpMatch[1].toLowerCase()));

          for (var i = 0; i < instructions.length; i++){
            if(instructions[i]._rowVariant === "success" && document.app.$data.execution_mode_run !== 0) // ajustar lo del user mode
              instructions[i]._rowVariant = "";
          }
        if (current_ins !== -1) instructions[current_ins]._rowVariant = "success";
      }

      if (configCacheMatch) {
        // console.log(configCacheMatch);
        switch(configCacheMatch[1]) {
          case "L1_I_SIZE":
            config_cache.push({configuration: "Size L1_I", value: configCacheMatch[2] + " lines"});
            break;
          case "L1_D_SIZE":
            config_cache.push({configuration: "Size L1_D", value: configCacheMatch[2] + " lines"});
            break;
          case "L1_SIZE":
            config_cache.push({configuration: "Size L1", value: configCacheMatch[2] + " lines"});
            break;
          case "L2_I_SIZE":
            config_cache.push({configuration: "Size L2_I", value: configCacheMatch[2] + " lines"});
            break;
          case "L2_D_SIZE":
            config_cache.push({configuration: "Size L2_D", value: configCacheMatch[2] + " lines"});
            break;
          case "L2_SIZE":
            config_cache.push({configuration: "Size L2", value: configCacheMatch[2] + " lines"});
            break;
          case "Rep_policy":
            config_cache.push({configuration: "Replacement policy", value: configCacheMatch[2]});
            break;
          case "L1_I_BLOCK_SIZE":
            config_cache.push({configuration: "Size Cache L1_I block", value: configCacheMatch[2] + " bits"});
            break;
          case "L1_D_BLOCK_SIZE":
            config_cache.push({configuration: "Size Cache L1_D block", value: configCacheMatch[2] + " bits"});
            break;
          case "L1_BLOCK_SIZE":
            config_cache.push({configuration: "Size Cache L1 block", value: configCacheMatch[2] + " bits"});
            break;
          case "L2_I_BLOCK_SIZE":
            config_cache.push({configuration: "Size Cache L2_I block", value: configCacheMatch[2] + " bits"});
            break;
          case "L2_D_BLOCK_SIZE":
            config_cache.push({configuration: "Size Cache L2_D block", value: configCacheMatch[2] + " bits"});
            break;
          case "L2_BLOCK_SIZE":
            config_cache.push({configuration: "Size Cache L2 block", value: configCacheMatch[2] + " bits"});
            break;
        }
      }

      if (cacheMatch) {
        // console.log(cacheMatch);
        switch(cacheMatch[2]) {
          case "L1_I":
            updateCacheMem(parseInt(cacheMatch[1],10), cacheMatch[2], cacheMatch[3], document.app.$data.L1_I_size_block);
          break;
          case "L1_D":
            updateCacheMem(parseInt(cacheMatch[1],10), cacheMatch[2], cacheMatch[3], document.app.$data.L1_D_size_block);
            
          break;
          case "L1":
            updateCacheMem(parseInt(cacheMatch[1],10), cacheMatch[2], cacheMatch[3], document.app.$data.L1_size_block);
            
          break;
          case "L2_I":
            updateCacheMem(parseInt(cacheMatch[1],10), cacheMatch[2], cacheMatch[3], document.app.$data.L2_I_size_block);
            
          break;
          case "L2_D":
            updateCacheMem(parseInt(cacheMatch[1],10), cacheMatch[2], cacheMatch[3], document.app.$data.L2_D_size_block);
            
          break;
          case "L2":
            updateCacheMem(parseInt(cacheMatch[1],10), cacheMatch[2], cacheMatch[3], document.app.$data.L2_size_block);
            
          break;

        }
      }

      if(CSREMatch){
        console.log(CSREMatch);
        if (CSREMatch[2] !== "vtype" && CSREMatch[2] !== "vl"){
          let regtowrite = crex_findReg(CSREMatch[2]);
          if(regtowrite.match !== 0)
            writeRegister(CSREMatch[4], regtowrite.indexComp, regtowrite.indexElem);
        }
      }
      if (CSRMatch){
        if (CSRMatch[2] === "vtype"){
          var size_elem = parseInt(CSRMatch[5], 16).toString(2).padStart(32, '0');
          size_elem = size_elem.slice(26, 29);
          // console.log("Tamaño: ", size_elem);
          if(size_elem === "000"){
            document.app.$data.v_length = 8;
            // architecture.components[3].total_elements = 64;
          } else if (size_elem === "001") {
            document.app.$data.v_length = 16;
            // architecture.components[3].total_elements = 32;
          } else if (size_elem === "010"){
            document.app.$data.v_length = 32;
            // architecture.components[3].total_elements = 16;
          }else {
            document.app.$data.v_length = 64;
            // architecture.components[3].total_elements = 8;
          }
          // architecture.components[3].length_elem = length_vext;
        }
        else if (CSRMatch[2] === "vl"){
          // architecture.components[3].elems_op = parseInt(CSRMatch[5], 16);
        }
      }
      if (vectorMatch){
        let regtowrite = crex_findReg(vectorMatch[1]);
        writeRegister(vectorMatch[3], regtowrite.indexComp, regtowrite.indexElem);
      }

      if (instMatch && (parseInt(instMatch[3], 16) >= pc_min && parseInt(instMatch[3], 16) <= pc_max )){
        userMode32 = true;

        clearAllRegisterGlows();
        coreEvents.emit("step-about-to-execute");
        if (inside_function)
          check_call_convention_temp_regs(instMatch);

        //Actualizamos el pc
        writeRegister(BigInt(parseInt(instMatch[3], 16)), pc_sail.indexComp, pc_sail.indexElem);
        for (var i = 0; i < instructions.length; i++) {
          if (instructions[i]._rowVariant === "info")
            instructions[i]._rowVariant = "";
        }
        instoper = "";
        // console.log("PC actual:",pc_sail);


        console.log("Instruccion: ", instMatch);
        const current_ins = instructions.findIndex(insn => insn.Address === ("0x"+instMatch[3].toLowerCase()));
        if(prev_add_to_jump !== undefined){
          instructions[prev_add_to_jump]._rowVariant = "";
          prev_add_to_jump = undefined;
        }

        if (instructions[current_ins].loaded.includes("jalr")){
          var next_add = instructions[current_ins].loaded.split("\t");
          const match = next_add[1].match(/(-?\d+)\((\w+)\)/);
          var aux_reg = crex_findReg(match[2]);
          var aux_val = readRegister(aux_reg.indexComp, aux_reg.indexElem);

          next_add_to_jump = (aux_val + BigInt(parseInt(match[1], 10))).toString(16);
          next_add_to_jump = instructions.findIndex(insn => insn.Address === ("0x"+next_add_to_jump.toLowerCase()));
          prev_add_to_jump = current_ins;

          // var stack_entry_func = instructions[next_add_to_jump].label;
          // creator_callstack_enter(instructions[next_add_to_jump].Label);
          // track_stack_enter(instructions[next_add_to_jump].Label);
          // callstack_convention.push(structuredClone(registers_before_function));
          // inside_function = true;
        }
        if (instructions[current_ins].loaded.includes("jal") && !instructions[current_ins].loaded.includes("jalr")){
          var next_add = instructions[current_ins].loaded.split("\t");

        }
        if (instructions[current_ins].loaded.includes("ret") && !instructions[current_ins].loaded.includes("mret")){
          // Mirar el ra
          var aux_reg = crex_findReg("ra");
          next_add_to_jump = readRegister(aux_reg.indexComp, aux_reg.indexElem).toString(16);
          next_add_to_jump = instructions.findIndex(insn => insn.Address === ("0x"+next_add_to_jump.toLowerCase()));
          if (next_add_to_jump !== -1){
            prev_add_to_jump = current_ins;
            // track_stack_leave();
            // creator_callstack_leave();
            // callstack_convention.pop();
            // inside_function = (callstack_convention.length > 0);
          }else
            next_add_to_jump = undefined;
        }


        // Primero caso de paso a paso
        if (document.app.$data.execution_mode_run === 1){
          instructions[current_ins]._rowVariant = 'info';
          if (current_ins < instructions.length - 1 || next_add_to_jump !== undefined){
            instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)]._rowVariant = 'success';
            document.app.$data.is_breakpoint = instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)].Break;
          }
          if (current_ins > 0 || prev_add_to_jump !== undefined)
            instructions[(prev_add_to_jump !== undefined && prev_add_to_jump !== current_ins) ? prev_add_to_jump : ((current_ins > 0) ? current_ins -1 : 0)]._rowVariant = '';
        }
        // Para el caso de run without stop y la siguiente instruccion es un breakpoint
        else if (document.app.$data.execution_mode_run === 0){
          // se almacena el estado de la instruccion en caso de que haya una parada por infinity loop
          hiden_executed = current_ins;
          if (current_ins < instructions.length - 1  || next_add_to_jump !== undefined) {
            hiden_next_execute = (next_add_to_jump !== undefined) ? next_add_to_jump : current_ins + 1;
          } else
            hiden_next_execute = current_ins + 1;


          if (current_ins < instructions.length - 1 || next_add_to_jump !== undefined) {
            document.app.$data.is_breakpoint = instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)].Break;
          }
          if(document.app.$data.is_breakpoint){
            instructions[current_ins]._rowVariant = 'info';
            if (current_ins < instructions.length - 1  || next_add_to_jump !== undefined) {
              instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)]._rowVariant = 'success';
            }
            coreEvents.emit("pause-execution");
          }else {
            instructions[current_ins]._rowVariant = '';
          }
          if (current_ins > 0  || prev_add_to_jump !== undefined)
            instructions[(prev_add_to_jump !== undefined && prev_add_to_jump !== current_ins) ? prev_add_to_jump : ((current_ins > 0) ? current_ins -1 : 0)]._rowVariant = '';

        }
        else
          instructions[current_ins]._rowVariant = '';

        if (instMatch[5] === "ecall"){
          let argument_register = crex_findReg("a7"); // obtenemos el registro para ver que llamada al sistema es
          let syscall_code = readRegister(argument_register.indexComp, argument_register.indexElem); // Lectura del registro para obtener el valor

          switch(syscall_code){
            case 5n:
              if(document.app.$data.execution_mode_run === 0){
                insn_number = current_ins;
                instructions[current_ins]._rowVariant = "info";
                if (current_ins < instructions.length -1  || next_add_to_jump !== undefined)
                  instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)]._rowVariant = 'success';
                  // instructions[current_ins +1]._rowVariant = "success";
              }
              document.app.$data.last_execution_mode_run = document.app.$data.execution_mode_run;
              document.app.$data.execution_mode_run = 2;
              // last_execution_mode_run = document.app.$data.execution_mode_run;
              // document.app.$data.execution_mode_run = 2;
              // Manejo para enteros
              // capi_read_int('a0');
              SYSCALL.read('a0', "int");
              break;
            case 6n:
              if(document.app.$data.execution_mode_run === 0){
                insn_number = current_ins;
                instructions[current_ins]._rowVariant = "info";
                if (current_ins < instructions.length -1 || next_add_to_jump !== undefined)
                  instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)]._rowVariant = 'success';

                  // instructions[current_ins +1]._rowVariant = "success";
              }
              document.app.$data.last_execution_mode_run = document.app.$data.execution_mode_run;
              document.app.$data.execution_mode_run = 2;
              // last_execution_mode_run = document.app.$data.execution_mode_run;
              // document.app.$data.execution_mode_run = 2;
              // Manejo para floats
              // capi_read_float('fa0');
              SYSCALL.read("fa0", "float");
              break;
            case 7n:
              if(document.app.$data.execution_mode_run === 0){
                insn_number = current_ins;
                instructions[current_ins]._rowVariant = "info";
                if (current_ins < instructions.length -1 || next_add_to_jump !== undefined)
                  instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)]._rowVariant = 'success';

                  // instructions[current_ins +1]._rowVariant = "success";
              }
              document.app.$data.last_execution_mode_run = document.app.$data.execution_mode_run;
              document.app.$data.execution_mode_run = 2;
              // Manejo para double
              // capi_read_double('fa0');
              SYSCALL.read("fa0", "double");
              break;
            case 8n:
              if(document.app.$data.execution_mode_run === 0){
                insn_number = current_ins;
                instructions[current_ins]._rowVariant = "info";
                if (current_ins < instructions.length -1 || next_add_to_jump !== undefined)
                  instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)]._rowVariant = 'success';

                  // instructions[current_ins +1]._rowVariant = "success";
              }
              document.app.$data.last_execution_mode_run = document.app.$data.execution_mode_run;
              document.app.$data.execution_mode_run = 2;
              // Manejo para strings
              // capi_read_string('a0','a1');
              SYSCALL.read("a0", "string", "a1");
              break;

            case 12n:
              if(document.app.$data.execution_mode_run === 0){
                instructions[current_ins]._rowVariant = "info";
                if (current_ins < instructions.length -1 || next_add_to_jump !== undefined)
                  instructions[(next_add_to_jump !== undefined) ? next_add_to_jump : (current_ins + 1)]._rowVariant = 'success';
                  // instructions[current_ins +1]._rowVariant = "success";
              }
              document.app.$data.last_execution_mode_run = document.app.$data.execution_mode_run;
              document.app.$data.execution_mode_run = 2;
              // last_execution_mode_run = document.app.$data.execution_mode_run;
              // document.app.$data.execution_mode_run = 2;
              // Manejo para char
              // capi_read_char('a0');
              SYSCALL.read("a0", "char");
              break;
            default:
              // console.log("No hago nada.");
              syscall_print_code = syscall_code;
              break;
          }

          next_add_to_jump = undefined;
        }



        instoper = instMatch[5];
        setInstructions(instructions);
        // window.updateUI({ error: false, msg: "" });






      } else if (instMatch && (parseInt(instMatch[3], 16) <= pc_min || parseInt(instMatch[3], 16) >= pc_max ))
        userMode32 = false;

      if (regiMatch /*&& userMode === true*/) {
        // En caso de ser escritura '<-' pintamos el valor en el registro que corresponde
        if (regiMatch[2] === '<-'){
          let regtowrite = crex_findReg(regiMatch[1]);
          // console.log("Registro identificado: ", regtowrite);
          // if (regiMatch[1] !== 'x2')
          if (regtowrite.indexComp === 2){
            if (regiMatch[3].startsWith("0x")) regiMatch[3] = regiMatch[3].slice(2).replace(/^0+/, '');
            else regiMatch[3] = regiMatch[3].replace(/^0+/, '');
            if (regiMatch[3].length <= 8){
              regiMatch[3] = regiMatch[3].padStart(8, "0");
              writeRegister(BigInt("0x" + regiMatch[3]), regtowrite.indexComp, regtowrite.indexElem);
            }
            else{
                writeRegister(BigInt("0x" + regiMatch[3]), regtowrite.indexComp, regtowrite.indexElem);
            }

          }
          else
            writeRegister(BigInt(parseInt(regiMatch[3], 16)), regtowrite.indexComp, regtowrite.indexElem);
        }

      }

      if (memoMatch /*&& userMode === true*/) {
        if (memoMatch[2] === '<-'){
          // switch(instoper){
          //   case 'sh': // Para almacenar un half
          writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //   break;
          //   case 'sb': // Para almacenar un byte
          //   writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //   break;
          //   case 'sw': // Para almacenar un int/word
          //   writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //   break;
          //   case 'fsw': // Para almacenar un float
          //   writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //   break;
          //   case 'fsd': // Para almacenar un double
          //   writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //   break;
          //   case 'vse8.v':
          //   writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //     break;
          //   case 'vse16.v':
          //   writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //     break;
          //   case 'vse32.v':
          //   writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //     break;
          //   case 'vse64.v':
          //     writeMemory(memoMatch[3], BigInt(parseInt(memoMatch[1], 16)));
          //     break;
          //   default:
          //     break;
          // }

          // instoper = "";
        }

      }

      if(printMatch && syscall_print_code !== -1){

        let value_2_print = printMatch[2].trim();
        // console.log("Estoy dentro de ecall a imprimir");
        // console.log(message);
        // console.log("Valor a imprimir: ", value_2_print);
        switch(syscall_print_code){

          case 1n: // Print int
            // SYSCALL.print(Number(parseInt(value_2_print)), "int32");

            display_print(value_2_print);
            // display_print(full_print(parseInt(value_2_print), null, false));
            syscall_print_code = -1;
            break;
          case 2n: // Print float
            // SYSCALL.print(Number(parseFloat(value_2_print)), "float");
            display_print(value_2_print);
            // display_print(full_print(parseFloat(value_2_print), 0, true));
            syscall_print_code = -1;
            break;

          case 3n: // Print double
            // SYSCALL.print(Number(parseFloat(value_2_print)), "double");
            display_print(value_2_print);
            // display_print(full_print(parseFloat(value_2_print), 0, true));
            syscall_print_code = -1;
            break;

          case 4n: // Print String
            display_print(value_2_print);
            syscall_print_code = -1;
            break;

          case 11n: // Print char
            // SYSCALL.print(BigInt(value_2_print.charCodeAt(0)), char);
            display_print(value_2_print);
            syscall_print_code = -1;
            break;

          default: // Rest of syscall codes not able to print
          syscall_print_code = -1;
            break;

        }

      }

      console.log(message);

    }

    Module['printErr'] = function (message) {
      // if (message.includes("Execution:") || message.includes("Instructions:") || message.includes("Perf:"))
        // show_notification(message, "success");
      // else
      console.warn(message);
    }
`;
  const bigStatements = j(bigBlock).get().node.program.body;

  // locate the same `return function(Module){...}` and insert before var out
  root
    .find(j.ReturnStatement, { argument: { type: 'FunctionExpression' } })
    .filter((p) => p.node.argument?.params?.[0]?.name === 'Module')
    .forEach((p) => {
      const fn = p.node.argument;
      const body = fn.body.body;

      // if instructionExp already exists, assume block present
      const hasInstructionExp = body.some((st) => j(st).toSource().includes('var instructionExp'));
      if (hasInstructionExp) return;

      const outIdx = body.findIndex((st) => {
        if (st.type !== 'VariableDeclaration') return false;
        return st.declarations.some((d) => d.id.type === 'Identifier' && d.id.name === 'out');
      });
      if (outIdx >= 0) {
        body.splice(outIdx, 0, ...bigStatements);
      }
    });

  // ============================================================
  // 4) Replace `Module["FS"] = FS;` with stub if not exported
  // ============================================================
  const fsStubSnippet = `
if (!Object.getOwnPropertyDescriptor(Module, "FS"))
  Module["FS"] = () =>
    abort("'FS' was not exported. add it to EXPORTED_RUNTIME_METHODS (see the FAQ)");
`;
  const fsStubStatements = j(fsStubSnippet).get().node.program.body;

  root
    .find(j.ExpressionStatement, {
      expression: {
        type: 'AssignmentExpression',
        left: {
          type: 'MemberExpression',
          object: { type: 'Identifier', name: 'Module' },
        },
      },
    })
    .filter((p) => j(p.node).toSource() === 'Module["FS"] = FS;')
    .forEach((p) => {
      // replace with the two statements (if + assignment)
      j(p).replaceWith(fsStubStatements[0]);
      if (fsStubStatements[1]) {
        j(p).insertAfter(fsStubStatements[1]);
      }
    });

  // ============================================================
  // 5) Comment out dependenciesFulfilled assignment block (remove statement, add comment)
  // ============================================================
  root
    .find(j.ExpressionStatement, {
      expression: {
        type: 'AssignmentExpression',
        left: { type: 'Identifier', name: 'dependenciesFulfilled' },
        right: { type: 'FunctionExpression' },
      },
    })
    .forEach((p) => {
      const src = j(p.node).toSource();
      if (!src.includes('function runCaller')) return;

      // replace with an EmptyStatement carrying a block comment
      const empty = j.emptyStatement();
      empty.comments = [
        j.commentLine(' dependenciesFulfilled = function runCaller() {', true, false),
        j.commentLine('   if (!calledRun) run();', true, false),
        j.commentLine('   if (!calledRun) dependenciesFulfilled = runCaller;', true, false),
        j.commentLine(' };', true, false),
      ];
      j(p).replaceWith(empty);
    });

  // ============================================================
  // 6) In `function run(args)` insert `shouldRunNow = true;` at top
  // ============================================================
  const shouldRunStmt = j.expressionStatement(
    j.assignmentExpression('=', j.identifier('shouldRunNow'), j.literal(true))
  );

  root.find(j.FunctionDeclaration, { id: { name: 'run' } }).forEach((p) => {
    const body = p.node.body.body;
    const has = body.some((st) => j(st).toSource() === 'shouldRunNow = true;');
    if (!has) body.unshift(shouldRunStmt);
  });

  // ============================================================
  // 7) In doRun(): after initRuntime(); add FS.writeFile + args.shift; and remove readyPromiseResolve(Module);
  // ============================================================
  const writeElfSnippet = `
FS.writeFile("output.elf", args[0]);
args.shift();
`;
  const writeElfStatements = j(writeElfSnippet).get().node.program.body;

  root
    .find(j.FunctionDeclaration, { id: { name: 'run' } })
    .find(j.FunctionDeclaration, { id: { name: 'doRun' } })
    .forEach((p) => {
      const body = p.node.body.body;

      // insert after initRuntime();
      const initIdx = body.findIndex((st) => j(st).toSource() === 'initRuntime();');
      if (initIdx >= 0) {
        const hasWrite = body.some((st) => j(st).toSource().includes('FS.writeFile("output.elf"'));
        if (!hasWrite) {
          body.splice(initIdx + 1, 0, ...writeElfStatements);
        }
      }

      // remove readyPromiseResolve(Module);
      for (let i = 0; i < body.length; i++) {
        if (j(body[i]).toSource() === 'readyPromiseResolve(Module);') {
          // replace with commented empty statement
          const empty = j.emptyStatement();
          empty.comments = [j.commentLine(' readyPromiseResolve(Module);', true, false)];
          body[i] = empty;
          break;
        }
      }
    });

  // ============================================================
  // 8) Patch exit(): rename param to statusw, update uses, insert UI block, procExit(statusw)
  // ============================================================
  const exitUiBlock = `
          for (let i = 0; i < instructions.length; i++){
            instructions[i]._rowVariant = '';
          }
          status.run_program = -1; // program finished
          if (statusw !== 0){
            reset_disable.value = false;
            instruction_disable.value = true;
            run_disable.value = true;
            stop_disable.value = false;
            show_notification("Your program has finished with errors.", "danger");
          } else {
            reset_disable.value = false;
            instruction_disable.value = false;
            run_disable.value = false;
            stop_disable.value = true;
            isFinished.value = true;
          }`;
  const exitUiStatements = j(exitUiBlock).get().node.program.body;

  root.find(j.FunctionDeclaration, { id: { name: 'exit' } }).forEach((p) => {
    // rename first param if it exists and is Identifier
    if (p.node.params?.[0]?.type === 'Identifier' && p.node.params[0].name !== 'statusw') {
      p.node.params[0].name = 'statusw';
    }

    // replace identifier uses of `status` with `statusw` (within this function)
    j(p)
      .find(j.Identifier, { name: 'status' })
      .filter((idPath) => {
        // don't touch property keys, labels, or member properties
        const parent = idPath.parent.node;
        if (parent.type === 'MemberExpression' && parent.property === idPath.node && !parent.computed) return false;
        if (parent.type === 'Property' && parent.key === idPath.node && !parent.computed) return false;
        if (parent.type === 'FunctionDeclaration' || parent.type === 'FunctionExpression' || parent.type === 'ArrowFunctionExpression') return false;
        return true;
      })
      .forEach((idPath) => {
        idPath.node.name = 'statusw';
      });

    // insert UI block right after `if (!implicit) {` opening (only if not present)
    const body = p.node.body.body;
    const hasUi = body.some((st) => j(st).toSource().includes('status.run_program = -1'));
    if (!hasUi) {
      // find the IfStatement `if (keepRuntimeAlive()) { if (!implicit) { ... } }`
      const keepIf = body.find((st) => st.type === 'IfStatement' && j(st.test).toSource().includes('keepRuntimeAlive()'));
      if (keepIf && keepIf.consequent?.type === 'BlockStatement') {
        const innerIf = keepIf.consequent.body.find(
          (x) => x.type === 'IfStatement' && x.test?.type === 'UnaryExpression' && j(x.test).toSource().includes('!implicit')
        ) || keepIf.consequent.body.find(
          (x) => x.type === 'IfStatement' && j(x.test).toSource() === '!implicit'
        );
        if (innerIf && innerIf.consequent?.type === 'BlockStatement') {
          innerIf.consequent.body.unshift(...exitUiStatements);
        }
      }
    }
  });

  // ============================================================
  // 9) Final: replace `run();` after noInitialRun check with `// run();` and `readyPromiseResolve(Module);`
  // ============================================================
  root
    .find(j.ExpressionStatement, { expression: { type: 'CallExpression', callee: { type: 'Identifier', name: 'run' } } })
    .filter((p) => j(p.node).toSource() === 'run();')
    .forEach((p) => {
      // only do this for the bottom-most run(); (after shouldRunNow stuff)
      // heuristic: ensure it's preceded somewhere above by `if (Module["noInitialRun"]) shouldRunNow = false;`
      const stmtPath = p.parent;
      const body = stmtPath.node.body || program.body;
      const idx = body.indexOf(p.node);
      const window = body.slice(Math.max(0, idx - 5), idx).map((n) => j(n).toSource()).join('\n');
      if (!window.includes('if (Module["noInitialRun"]) shouldRunNow = false;')) return;

      const empty = j.emptyStatement();
      empty.comments = [j.commentLine(' run();', true, false)];
      j(p).replaceWith(empty);

      // insert readyPromiseResolve(Module); if missing right after
      const next = body[idx + 1];
      const hasReady = next && j(next).toSource() === 'readyPromiseResolve(Module);';
      if (!hasReady) {
        j(p).insertAfter(
          j.expressionStatement(
            j.callExpression(j.identifier('readyPromiseResolve'), [j.identifier('Module')])
          )
        );
      }
    });

  return root.toSource({ quote: 'double', trailingComma: true });
}