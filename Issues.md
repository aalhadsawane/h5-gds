# Status Report: Porting h5gds to ADIOS2 on Miyabi

## Current Status
We are in the **ADIOS2 Build Configuration** phase.
The core ADIOS2 libraries (C, CXX, MPI, CUDA) are building successfully with CUDA support (`Features: ... CUDA : ON`).

### The Problem
The build fails during the linking stage of the utility tools (`bpls`, `adios2_reorganize`).
Error: `undefined reference to sys_icache_invalidate` in `libadios2_dill.so`.
This is due to `libdill` (a dependency of `EVPath` which is used by `BP5` and `FFS`) having incompatible assembly for the Grace Hopper AArch64 environment.

### Resolution Strategy
1.  **Disable Utility Tools:**
    *   Since `h5gds` only requires the core libraries and the HDF5 engine, the utility tools (`bpls`, etc.) are not strictly necessary for the application to run.
    *   We have modified `scripts/build_adios2.sh` to patch `source/CMakeLists.txt` and disable `add_subdirectory(utils)`.
    *   This prevents the build system from attempting to link the failing executables, allowing the core libraries to install successfully.

2.  **Clean Build:**
    *   The build script now actively cleans the `dependencies/adios2-build` directory to ensure no stale CMake cache entries (like `ADIOS2_USE_SysVShMem=ON`) persist.

3.  **Engine Configuration:**
    *   We continue to explicitly disable optional engines (`SST`, `DataMan`, `Campaign`, `MHS`) to minimize dependencies.
    *   `BP5` is enabled by default in ADIOS2 2.11+ and cannot be easily disabled via CMake options, but by skipping the tools build, we avoid the link error associated with its transport layer (`dill`/`EVPath`).

### Next Steps
Run the updated `scripts/build_adios2.sh`. It should complete successfully and generate `adios2_env.sh`.
Then run `qsub build.pbs` to compile `h5gds`.
