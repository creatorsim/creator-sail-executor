CREATOR-SAIL-EXECUTOR
=============================
This repo contains the implementation of the full specification with Sail for RISC-V (32-bit and 64-bit) for CREATOR simulator. And the user can make their own version of the simulator editing the implementation of the architecture and instruction set through the ".sail" files and generate a new version to apply into CREATOR to execute programs which contains this new or edited instructions.

## Requirements

To use the repo, the user need to install previously the following tools:

- **Sail**, as instruction specification language for RISC-V instruction Set.
- **Emscripten/Emsdk**, a transpiler from high and low level language code to Web Environments.
- **GMP**, an arithmetic multiple precision library.

All of this tool require a minimum version to be used in this project. For both variants of the simulator needs the lastest version of Sail (0.17.1) to generate the implementation on a high/low level code like C/C++, and the user needs to download a version of GMP that needs to be compiled with emscripten to generate the library to be applied in the generation of the RISC-V simulator. The version of GMP lib that recommend is 6.3.0, and then be compiled with Emscripten.

The rest of the tools needs a minimum specific version depending on the variant of the RISC-V simulator wants to generate.

If the user wants to generate a 32-bit simulator for RISC-V architecture, it is needed to install emscripten (from apt-get in Linux f.e.) with the minimum version to *emcc* (3.1.5) and *emar* (13.0.1). For the 64-bit variant of the simulator needs to install a more recent version of emscripten. The reason is that lastest version of Emscripten allows transpile code to 64-bit binaries to executed in web environments. And depending on the distro there are not available from the apt-get repositories. The recommended version for 64-bit is to *emcc*, 4.0.3, and to *emar*, 21.0.0.

Now, it will show how to install each tool for the simulator compile process.

### Instruction specification language for RISC-V (Sail)

To install Sail, the user need to install OCaml/opam. Opam is a package manager which source code is in OCaml.

- Install commands:
```
# Tools required to install OCaml/Opam 

sudo apt update
sudo apt install -y opam m4 pkg-config zlib1g-dev libgmp-dev libncurses-dev libffi-dev python3 git

# Opam initalization

opam init
eval $(opam env)

# OCaml install

# This command only at the first time of use Opam
opam switch create 4.14.1 

# OCaml/Opam initialization
eval $(opam env)

```

This manager contains the implementation of Sail language that allows the user to use the tool.

To install Sail needs to run the following commands:

```
# Add Sail source code to opam
opam repo add sail https://github.com/rems-project/opam-repository.git
opam update

# Sail install with opam
opam install sail

# Check Sail version installed
sail -v
```

And now the user should use Sail to generate the code of the architecture and instruction set for the simulator.

### Transpiler from high and low level code to Web environments (Emscripten/Emsdk)

To 32-bit version, the instalation process are the following:

```
sudo apt-get install emscripten

# Check emcc (minimum 3.1.5) and emar (minimum 13.0.1) version

emcc -v
emar -V
```

To 64-bit version, the installation process are a bit longer than 32-bit version, and is the following:


```
# First get the emsdk repository and enter that directory
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk

# Fetch the latest version of the emsdk
git pull

# Download and install the SDK tools  (recommended 4.0.3 but can download/install the latest).
./emsdk install 4.0.3 # ./emsdk install latest 

# Make the "4.0.3/latest" SDK "active" for the current user. (writes .emscripten file)
./emsdk activate 4.0.3 # ./emsdk activate latest

# Activate PATH and other environment variables in the current terminal
# Also, if the user want, can be added to startup scripts

source ./emsdk_env.sh

# Finally check version for emcc (4.0.3) and emar (21.0.0)

emcc -v
emar -V
```
### GNU Multiple Precision Arithmetic Library (GMP)

First, need to download the version of the lib from this url: https://gmplib.org/#DOWNLOAD

Unzip it and inside on the repo, the following steps needs to be executed:

First create a directory for the build (just for a clean compilation process)

```
mkdir -p gmp_build
cd gmp-6.3.0
```

Now, the user must to configure different parameters:

```
export CFLAGS="-O3"
export CXXFLAGS="-O3"
```

To generate the library for Emscripten, the user must to use their commands to generate the compiled library for web environments (*emconfigure*, emscripten version of the *configure* command, and *emmake*, emscripten version of the *make* command)

```
emconfigure ../configure \
  --prefix="$(pwd)/../gmp_build" \
  --disable-assembly \
  --enable-static \
  --disable-shared

# Once configure process finished lets make and install the new library on the prefix directory

emmake make
emmake make install
```

Finally check at the prefix directory if the library was succesfully installed.

**Note**: To each variant of the simulator, the user must to generate a version of the library. The reason is that the 64-bit variant of the simulator needs to use 64-bit extension in memory and the default version of Emscripten was optimized to use 32-bit version. So in 64-bit version must to enable the 64-bit flag (MEMORY64).


## How to build it

Once all the necessary tools for generating the simulator have been installed, a script will be used for this purpose. The script is *sail_sim.sh* that there is at the root of the source code, and the script requires a series of parameters to be passed to it in order to generate the simulator.


RISC-V Variant that wants to generate:

```
RV32 / RV64
```
If it is to local or web environment
```
web / local
```
If the simulator must to support vector instructions
```
vector / ""
```

Cache directory for emscripten compilation process (required for 32-bit architecture)

```
/path/emscripten/cache
# The path of emscripten cache is at the emscripten source code 
```

GMP dir to use during the transpilation process
```
/gmp/build/path
```

There are the different examples to use the script:
```
./sail_sim.sh RV64 web /emcc/cache 
./sail_sim.sh RV64 web /emcc/cache /opt/gmp
./sail_sim.sh --arch RV64 --target web --cache /emcc/cache/path --gmp-dir /opt/gmp
  ```

## Output generated

Once is transpiled and generated our simulator, the output was stored at *binaries* directory of the source code.

This can be applied on our CREATOR project to simulate a new type of executor of the tool. 
