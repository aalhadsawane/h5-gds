# Status Report: Porting h5gds to ADIOS2 on Miyabi

## Current Status
**ADIOS2 Build Configuration: SUCCESS**

We have successfully built ADIOS2 (core libraries, MPI, CUDA, HDF5 engine) on the Miyabi supercomputer. The linker errors related to `libdill` / `EVPath` on AArch64 have been resolved.

### Build Fix Summary
The core issue was a linker error (`undefined reference to sys_icache_invalidate`) in `libadios2_dill.so`, which is a dependency of the ADIOS2 utility tools (`bpls`, `adios2_reorganize`).

**The Solution:**
We modified `scripts/build_adios2.sh` to patch the ADIOS2 source code (`source/CMakeLists.txt`) before configuration. Specifically, we commented out `add_subdirectory(utils)`.

**Rationale:**
*   The `h5gds` application only requires the **ADIOS2 C++ Library** and the **HDF5 Engine**, which are built by the core components.
*   The utility tools (and their problematic dependencies like `EVPath` / `libdill`) are not required for linking or running `h5gds`.
*   Disabling the `utils` directory prevents the build system from attempting to link the broken executables, allowing the core libraries (`libadios2_core`, `libadios2_core_mpi`, `libadios2_core_cuda`) to install successfully.

### Minor Observations
*   **adios2-config warning:** The build log shows a benign error: `chmod: cannot access .../bin/adios2-config`.
    *   This occurs because the `adios2-config` shell script generator (in `cmake/install/post`) expects the `bin` directory to be populated by the utility tools, which we disabled.
    *   **Impact:** Negligible. Our project uses CMake (`find_package(ADIOS2)`), which correctly locates `adios2-config.cmake` in `lib64/cmake/adios2`. The absence of the shell script wrapper does not affect us.

### Next Steps
Proceed to build the `h5gds` application using the installed ADIOS2 library:
```bash
qsub build.pbs
```
