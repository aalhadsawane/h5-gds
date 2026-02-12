# Status Report: Porting h5gds to ADIOS2 on Miyabi

## Current Status
We are in the **ADIOS2 Build Configuration** phase.
The core ADIOS2 libraries (C, CXX, MPI, CUDA) are building successfully with CUDA support (`Features: ... CUDA : ON`).
However, the build fails during the linking stage of the utility tools (`bpls`, `adios2_reorganize`).

### The Problem
The build fails with linker errors:
`undefined reference to sys_icache_invalidate` in `libadios2_dill.so`.

**Root Cause:**
The `libdill` library (a dependency of `EVPath`, which is used by the default `BP5` engine and others like `SST`, `DataMan`) contains architecture-specific assembly code that is failing on the NVIDIA Grace Hopper (AArch64) environment with the current GCC compiler.

### Previous Attempts
1.  **Disable Dependent Engines:** We explicitly disabled `SST`, `DataMan`, `Campaign`, and `MHS` engines.
    *   **Result:** The build still failed because `BP5` (enabled by default) also depends on `EVPath`.
2.  **Disable EVPath Directly:** We attempted to set `-DADIOS2_USE_EVPath=OFF`.
    *   **Result:** CMake warned that `ADIOS2_USE_EVPath` is not a valid top-level option (it is controlled by engine enablement).

### Current Resolution Strategy
We have modified `scripts/build_adios2.sh` to explicitly disable **BP5** and other optional dependencies:
*   `-DADIOS2_USE_BP5=OFF`
*   `-DADIOS2_USE_SysVShMem=OFF`
*   `-DADIOS2_USE_UCX=OFF`
*   `-DADIOS2_USE_ZeroMQ=OFF`
*   `-DADIOS2_USE_ZFP=OFF`
*   `-DADIOS2_USE_SZ=OFF`

**Rationale:**
The target application `h5gds` only requires the **HDF5 engine**. By disabling `BP5` and other native ADIOS2 engines/features, we aim to completely remove the `EVPath` and `libdill` dependency, allowing the build to complete successfully.
