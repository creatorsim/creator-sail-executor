#!/bin/bash 
set -euo pipefail

unset GMP_EM_DIR

MIN_SAIL_VERSION="0.17.1"
MIN_EMCC_32_VERSION="3.1.5"
MIN_EMCC_64_VERSION="4.0.3"
MIN_EMAR_32_VERSION="13.0.1"
MIN_EMAR_64_VERSION="21.0.0"
ARCHITECTURE=""                    # Required
TARGET=""                          # Required
CACHE_PATH=""                      # Required
GMP_EM_DIR=""                      # Optional
IS_VECTOR_AVAILABLE=""             # Optional

POSITIONAL=()

usage() {
  cat <<'EOF'
Use:
  sail_sim.sh RV64 web ~/emscripten_cache [GMP_EM_DIR]
  sail_sim.sh --arch RV64 --target web --cache /emcc/cache/path [--gmp-dir /gmp/dir/path]
  sail_sim.sh RV64 --target web /emcc/cache/path [--gmp-dir /gmp/dir/path]
  sail_sim.sh --arch RV64 local [--gmp-dir /gmp/dir/path]
  sail_sim.sh RV64 web --cache /emcc/cache/path [--gmp-dir /gmp/dir/path]
Examples:
  ./sail_sim.sh RV64 web /emcc/cache 
  ./sail_sim.sh RV64 web /emcc/cache /opt/gmp
  ./sail_sim.sh --arch RV64 --target web --cache /emcc/cache/path --gmp-dir /opt/gmp
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCHITECTURE="${2:-}"; shift 2 ;;
    --target)
      TARGET="${2:-}"; shift 2 ;;
    --cache)
      CACHE_PATH="${2:-}"; shift 2 ;;
    --vector)
      IS_VECTOR_AVAILABLE="${2:-}"; shift 2 ;;
    --gmp-dir|--gmp|--gmp_path)
      GMP_EM_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    --*)
      echo "Unknown option: $1"
      usage
      exit 1 ;;
    *)
      POSITIONAL+=("$1"); shift ;;
  esac
done

if [[ -z "$ARCHITECTURE" && ${#POSITIONAL[@]} -ge 1 ]]; then
  ARCHITECTURE="${POSITIONAL[0]}"
fi
if [[ -z "$TARGET" && ${#POSITIONAL[@]} -ge 2 ]]; then
  TARGET="${POSITIONAL[1]}"
fi
if [[ -z "$GMP_EM_DIR" && ${#POSITIONAL[@]} -ge 3 ]]; then
  GMP_EM_DIR="${POSITIONAL[2]}"
fi

# ------------------------------------
# Target and Architecture validation
# ------------------------------------
if [[ -z "$ARCHITECTURE" || -z "$TARGET" ]]; then
  echo "Not enough arguments"
  usage
  exit 1
fi

case "$ARCHITECTURE" in
  RV32|RV64) ;;
  *) echo "Invalid architecture: $ARCHITECTURE (use RV32 o RV64)"; exit 1 ;;
esac

case "$TARGET" in
  web|local) ;;
  *) echo "Invalid target: $TARGET (use web o local)"; exit 1 ;;
esac


# case "$IS_VECTOR_AVAILABLE" in
#   vector) ;;
#   *) echo "Invalid target: $TARGET (use vector)"; exit 1 ;;
# esac





get_sail_version() {
  local out
  out="$(sail -version 2>&1 || true)"

  local ver
  ver="$(printf '%s\n' "$out" | awk '/^Sail[[:space:]]+[0-9]/{print $2; exit}')"

  if [ -z "$ver" ]; then
    echo "Sail version cannot be detected. Complete out:"
    echo "$out"
    return 1
  fi

  printf '%s' "$ver"
}

get_emcc_version() {
    local out
    out="$(emcc -v 2>&1 || true)"

    local ver
    ver="$(printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"

    if [ -z "$ver" ]; then 
        echo "emcc version cannot be detected. Complete out:"
        echo "$out"
        return 1
    fi
    printf '%s' "$ver"
}

get_emar_version() {
  echo "getting emar version"
  local out
  out="$(emar -V 2>&1 || true)"

  local ver
  ver="$(printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)"

  if [ -z "$ver" ]; then 
    echo "emar version cannot be detected. Complete out:"
    echo "$out"
    return 1
  fi
  printf '%s' "$ver"

}

version_check() {
    local have="$1"
    local min="$2"
    [ "$(printf '%s\n'  "$min" "$have" | sort -V | head -n1)" = "$min" ]
}

# Check requirements 
echo "Checking dependencies..."

if ! command -v sail >/dev/null 2>&1; then 
    echo "Error: 'sail' is not installed or not included the PATH con bash command"
    echo "Install sail through opam or add the access path"
    exit 1
fi

echo "sail found: $(command -v sail)"

SAIL_VERSION="$(get_sail_version)"

if ! version_check "$SAIL_VERSION" "$MIN_SAIL_VERSION"; then
    echo "Sail >= $MIN_SAIL_VERSION required (detected $SAIL_VERSION)"
    exit 1
fi

echo "Sail checked"



GMP_OK=false

if [[ -n "$GMP_EM_DIR" ]]; then
  GMP_EM_DIR="${GMP_EM_DIR%/}"

  if [[ ! -f "$GMP_EM_DIR/include/gmp.h" ]]; then
    echo "gmp.h not found at $GMP_EM_DIR/include/gmp.h"
    exit 1
  fi

  # lib o lib64
  if [[ -f "$GMP_EM_DIR/lib/libgmp.a" || -f "$GMP_EM_DIR/lib/libgmp.so" ]]; then
    export CFLAGS="${CFLAGS:-} -I$GMP_EM_DIR/include"
    export LDFLAGS="${LDFLAGS:-} -L$GMP_EM_DIR/lib"
    echo "GMP using --gmp-dir: $GMP_EM_DIR (lib)"
    GMP_OK=true
  else
    echo "libgmp not found at $GMP_EM_DIR/lib either at $GMP_EM_DIR/lib64"
    exit 1
  fi
fi

# 1) Si no se pasó ruta, intenta pkg-config
if [[ "$GMP_OK" = false ]] && command -v pkg-config >/dev/null 2>&1; then
  if pkg-config --exists gmp; then
    echo "GMP found via pkg-config"
    export GMP_CFLAGS
    export GMP_LIBS
    GMP_CFLAGS="$(pkg-config --cflags gmp)"
    GMP_LIBS="$(pkg-config --libs gmp)"
    GMP_OK=true
  fi
fi

# 2) Si sigue sin estar, intenta sistema
if [[ "$GMP_OK" = false ]]; then
  if ldconfig -p 2>/dev/null | grep -q libgmp; then
    echo "GMP found on system (ldconfig)"
    GMP_OK=true
  fi
fi

if [[ "$GMP_OK" = false ]]; then
  echo "Error: GMP lib not found"
  exit 1
fi



EMCC_OK=false 

if command -v emcc >/dev/null 2>&1; then
    echo "emcc founded $(command -v emcc)"
    EMCC_OK=true
fi

if [ "$EMCC_OK" = false ]; then
    echo "Error: Emscripten (emcc) not installed or not activated."
    echo
    echo "Please install it through apt-get or via emsdk"
    echo
    exit 1
fi


EMCC_VERSION="$(get_emcc_version)"

#check which arch are
if [ "$ARCHITECTURE" == "RV32" ]; then
    echo "RISC-V 32 bits architecture selected"
    if [ "$IS_VECTOR_AVAILABLE" = "vector" ]; then 
      if ! version_check "$EMCC_VERSION" "$MIN_EMCC_64_VERSION"; then
        echo "emcc >= $MIN_EMCC_64_VERSION required (detected $EMCC_VERSION)"
        exit 1
      fi  
    else 
      if ! version_check "$EMCC_VERSION" "$MIN_EMCC_32_VERSION"; then
        echo "emcc >= $MIN_EMCC_32_VERSION required (detected $EMCC_VERSION)"
        exit 1
      fi
    fi
elif [ "$ARCHITECTURE" == "RV64" ]; then
    echo "RISC-V 32 bits architecture selected"
    if ! version_check "$EMCC_VERSION" "$MIN_EMCC_64_VERSION"; then
        echo "emcc >= $MIN_EMCC_64_VERSION required (detected $EMCC_VERSION)"
        exit 1
    fi
else 
    echo "Error: None architecture version are selected or undefined architecture: $ARCHITECTURE"
    echo "Please select one architecture variant (RV32 or RV64) to generate the architecture simulator"
    echo "Use ./sail_sim.sh -h or ./sail_sim.sh --help for more information"
    exit 1
fi






EMAR_OK=false

if command -v emar >/dev/null 2>&1; then
  echo "emar founded $(command -v emar)"
  EMAR_OK=true
fi

if [ "$EMAR_OK" = false ]; then

  echo "Error: Emscripten (emar) not installed or not activated."
  echo
  echo "Please install it through apt-get or via emsdk"
  echo
  exit 1
fi


EMAR_VERSION="$(get_emar_version)"

#check which arch are
if [ "$ARCHITECTURE" = "RV64" ]; then
    echo "RISC-V 64 bits architecture selected"
    if ! version_check "$EMAR_VERSION" "$MIN_EMAR_64_VERSION"; then
        echo "emar >= $MIN_EMAR_64_VERSION required (detected $EMAR_VERSION)"
        exit 1
    fi
elif [ "$ARCHITECTURE" = "RV32" ]; then
    echo "RISC-V 32 bits architecture selected"
    if [ "$IS_VECTOR_AVAILABLE" = "vector" ]; then 
      if ! version_check "$EMAR_VERSION" "$MIN_EMAR_64_VERSION"; then
        echo "emcc >= $MIN_EMAR_64_VERSION required (detected $EMAR_VERSION)"
        exit 1
      fi  
    else 
      if ! version_check "$EMAR_VERSION" "$MIN_EMAR_32_VERSION"; then
        echo "emar >= $MIN_EMAR_32_VERSION required (detected $EMAR_VERSION)"
        exit 1
      fi
    fi
else 
    echo "Error: None architecture version are selected or undefined architecture: $ARCHITECTURE"
    echo "Please select one architecture variant (RV32 or RV64) to generate the architecture simulator"
    echo "Use ./sail_sim.sh -h or ./sail_sim.sh --help for more information"
    exit 1
fi

# Now filter if want to generate the simulator to local environments or web environments


# Gen Sail simulator
echo "$ARCHITECTURE"
echo "$TARGET"
echo "$GMP_EM_DIR"
echo "$IS_VECTOR_AVAILABLE"
echo "$EMCC_VERSION"
echo "$EMAR_VERSION"
export GMP_EM_DIR

if [ "$CACHE_PATH" != "" ]; then
  export EM_CACHE=$CACHE_PATH
fi

if [[ "$ARCHITECTURE" = "RV64" && "$TARGET" = "web" ]]; then
  echo "Compile RISC-V 64 bits architecture on web environment"
  make clean
  make LOCAL=0 ARCHS=64 c_emulator/riscv_sim_RV64
  prettier -w c_emulator/riscv_sim_RV64.js
  # mv c_emulator/riscv_sim_RV64.js binaries/
  mv c_emulator/riscv_sim_RV64.wasm binaries/
elif [[ "$ARCHITECTURE" = "RV64" && "$TARGET" = "local" ]]; then
  echo "Compile RISC-V 64 bits architecture on local environment"
  make clean
  make LOCAL=1 ARCHS=64 c_emulator/riscv_sim_RV64
  # prettier -w c_emulator/riscv_sim_RV64
elif [[ "$ARCHITECTURE" = "RV32" && "$TARGET" = "web" ]]; then
  echo "Compile RISC-V 32 bits architecture on web environment"
  make clean
  if [ "$IS_VECTOR_AVAILABLE" = "vector" ]; then
    make LOCAL=0 ARCHS=32 VECT=1 c_emulator/riscv_sim_RV32
    mv ./c_emulator/riscv_sim_RV32.wasm binaries/riscv_sim_RV32vd.wasm
  else 
    make LOCAL=0 ARCHS=32 VECT=0 c_emulator/riscv_sim_RV32
    mv ./c_emulator/riscv_sim_RV32.wasm binaries/riscv_sim_RV32.wasm
  fi
  # prettier -w c_emulator/riscv_sim_RV32.js
  # mv ./c_emulator/riscv_sim_RV32.js binaries/
elif [[ "$ARCHITECTURE" = "RV32" && "$TARGET" = "local" ]]; then
  echo "Compile RISC-V 32 bits architecture on local environment"
  make clean
  if [ "$IS_VECTOR_AVAILABLE" = "vector" ]; then
    make LOCAL=1 ARCHS=32 VECT=1 c_emulator/riscv_sim_RV32
  else 
    make LOCAL=1 ARCHS=32 VECT=0 c_emulator/riscv_sim_RV32
  fi
else
  echo "Nothing to compile"
fi
