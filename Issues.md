# Status Report: Porting h5gds to ADIOS2 on Miyabi

## Current Status
We are stuck at the **ADIOS2 Build Configuration** stage.

### The Problem
The `h5gds` application requires ADIOS2 to be built with **CUDA support** to enable native GPU pointer handling (`Put` from device memory).
However, the ADIOS2 build process (`scripts/build_adios2.sh`) finishes successfully but **fails to export the CUDA component**.

**Error Log (h5gds build):**
```
CMake Error ... Could NOT find ADIOS2: missing: CUDA
```

**ADIOS2 Configuration Log:**
```
-- Found adios2: ... found components: C CXX MPI
```
(Note: "CUDA" is missing from the found components list, even though `Cuda Compiler` was detected).

### Root Cause Analysis
1.  **CMake 3.31 Compatibility**: The Miyabi system uses CMake 3.31.1. This version strictly removes the `FindCUDA` module (Policy CMP0146).
    *   ADIOS2 v2.10.2 (stable) might still rely on legacy `FindCUDA` logic or checks that fail under CMake 3.31, causing it to silently disable the CUDA component during configuration.
2.  **Compiler Environment**: We are using `NVHPC` (nvc++) for C++ and `NVIDIA` (nvcc) for CUDA. Mixing these with standard GCC (for host compilation) requires careful flag setting (`CC=gcc`, `CXX=g++`) which we have applied, but the CMake configuration might still be rejecting the CUDA language enablement due to strict checks.

### Attempts & Outcomes
1.  **Original Build**: Failed with "Bad address" runtime error -> Diagnosis: ADIOS2 built without CUDA.
2.  **Forcing Flags**: Added `-DADIOS2_USE_CUDA=ON` and `-DCMAKE_CUDA_ARCHITECTURES=90` to build script. -> Result: Build succeeds, but CUDA component still missing.
3.  **Compiler Switch**: Switched `CC` and `CXX` to `gcc/g++` to match `nvcc` host compiler. -> Result: Build succeeds, CUDA compiler detected, but component *still* missing.

### Proposed Solution
1.  **Switch to ADIOS2 Master Branch**: The development branch of ADIOS2 likely contains fixes for CMake 3.31 compatibility and better CUDA toolkit detection (`FindCUDAToolkit` instead of `FindCUDA`).
2.  **Legacy Policy**: Attempt to force `-DCMAKE_POLICY_DEFAULT_CMP0146=OLD` to restore `FindCUDA` behavior if sticking to v2.10.2.

We will proceed with **Switching to ADIOS2 Master** as the most robust fix for modern CMake environments.

### Update: Linker Errors on AArch64
The build of ADIOS2 Master encountered a linker error:
`undefined reference to sys_icache_invalidate` in `libadios2_dill.so`.

**Root Cause:** The `libdill` library (used by SST, DataMan, Campaign engines) has architecture-specific code that is failing on the Grace Hopper (AArch64) environment with the GCC compiler version used.

**Resolution:** We have explicitly disabled optional engines that depend on `libdill`:
*   `-DADIOS2_USE_SST=OFF`
*   `-DADIOS2_USE_DataMan=OFF`
*   `-DADIOS2_USE_Campaign=OFF`
*   `-DADIOS2_USE_MHS=OFF`

This trims the build to the core functionality required for HDF5+CUDA support.
