# HDF5-GDS Build Instructions and Architecture Fixes

This repository contains the source code for building `h5gds` (HDF5 with GPUDirect Storage) linked against a custom build of the ADIOS2 high-performance I/O framework. 

When compiling this stack on a 64-bit ARM Linux environment (AArch64, e.g., NVIDIA Grace CPU on the Miyabi cluster) with GPU support, the original repository code fails due to an ADIOS2 CMake component export bug and a C++ linker error. This document outlines the required fixes.

## 1. Fix 1: The Missing ADIOS2 CUDA Component Export
**The Bug:** The `h5gds` build system requires the ADIOS2 library to compile. In the original `h5gds` CMake files (specifically `apply_common_settings.cmake`), it searches for ADIOS2 using a strict requirement that includes the `CUDA` component. However, when ADIOS2 builds itself, its generated `adios2-config-common.cmake` file is flawed. While it internally acknowledges that it has CUDA enabled, it fails to define or export an actual `CUDA` "component" for downstream applications to link against. Because the `CUDA` component is missing from the exported list, CMake immediately fails the `h5gds` configuration phase.

**The Fix:** To resolve this, we patched the `h5gds` CMake configuration to drop the strict `CUDA` component requirement, as the ADIOS2 library is already fundamentally built with CUDA support under the hood. In `apply_common_settings.cmake`, the `find_package` requirement was modified to only require the `CXX` and `MPI` components, safely bypassing the missing `CUDA` component export.

## 2. Fix 2: The ADIOS2 `dill` Library Linker Error
ADIOS2 relies on a bundled third-party library called `dill` for Just-In-Time (JIT) compilation.  JIT compilation writes new machine code directly to memory (Data Cache), which then requires the CPU's Instruction Cache (I-Cache) to be cleared so the processor doesn't execute stale data.

**The Bug:** Inside the `dill` source code (`arm64.c`), the architecture check is flawed. When it detects an `ARM64` CPU, it incorrectly assumes the operating system is macOS (Apple Silicon). Because of this, it attempts to call a macOS-specific system function called `sys_icache_invalidate`. When compiling on Linux, this function does not exist in the standard GNU C Library (glibc). While the shared library will lazily compile and ignore the missing function, the strict C++ linker will immediately crash with an `undefined reference` error when trying to assemble the final `h5gds` executable.

**The Fix:** We intercepted the call to the Apple-specific function and routed it to the standard Linux GCC built-in cache clearing instruction. Inside `arm64.c`, the Apple environment check block was modified to explicitly define the `sys_icache_invalidate` function using `__builtin___clear_cache`. This provides the strict C++ linker with the real memory address it needs, allowing the final executable to build successfully.
