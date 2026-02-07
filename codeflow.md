# Code Flow and Configuration Guide

This document describes the end-to-end data and control flow of the `h5gds` benchmark application, specifically how runtime parameters are propagated from the job scheduler to the ADIOS2/HDF5 backend.

## 1. Parameter Sweep (The Driver)

The benchmark is driven by `job.pbs`, which iterates through a defined set of configurations.

*   **Variables Iterated**:
    *   `VFD`: `sec2`, `gds-native`, `gds-compat`, `direct`.
    *   `NUM`: Number of particles (file size).
    *   `FBLK`: File block size (used for alignment/chunking concepts).
    *   `CBUF`: Copy buffer size.

*   **Environment Setup (in `job.pbs`)**:
    *   Inside the loop, the script sets crucial environment variables based on the current `VFD`:
        *   `HDF5_DRIVER`: Sets the underlying HDF5 Virtual File Driver (e.g., `gds`, `sec2`, `direct`).
        *   `CUFILE_ENV_PATH_JSON`: Points to GDS configuration files (`disable_compat.json` vs `force_compat.json`).
        *   `HDF5_PLUGIN_PATH`: Points to the directory containing `libhdf5_vfd_gds.so` (required for `gds` driver).

*   **Execution Command**:
    ```bash
    bin/h5gds --num $NUM --fblk $FBLK --cbuf $CBUF --vfd $ACTUAL_VFD
    ```

## 2. Application Logic (`src/h5gds.cu`)

The C++/CUDA application receives these arguments and initializes the I/O system.

### A. Initialization
1.  **Parse Arguments**: Uses `boost::program_options` to read `num`, `cbuf`, `fblk`, `vfd`, etc.
2.  **Memory Allocation**: Allocates GPU memory for particles (`pos`, `vel`, `id`) and generates initial data.
3.  **ADIOS2 Init**: Initializes `adios2::ADIOS` using `adios2.xml`.

### B. Parameter Application
The application bridges the command-line arguments to the ADIOS2 engine:

1.  **VFD Validation**:
    *   Checks the requested `vfd` (e.g., `gds`) against the active `HDF5_DRIVER` environment variable.
    *   Issues a warning if they mismatch (e.g., requesting `gds` when `HDF5_DRIVER` is unset or `sec2`), ensuring the environment is correctly configured by the script.

2.  **Engine Configuration**:
    *   Passes `cbuf` to the ADIOS2 engine as the `BufferChunkSize` parameter via `io.SetParameter()`.
    *   *Note*: `fblk` and `memb` are logged for CSV consistency but relying on ADIOS2/HDF5 defaults or environment variables for low-level alignment in this high-level API port.

### C. I/O Operations
1.  **Define Variables**: Defines standard arrays (`[N, 4]` float for positions, etc.).
2.  **Write Phase**:
    *   Calls `writer.Put()` passing **device pointers** directly.
    *   ADIOS2 HDF5 engine detects the GPU pointers and handles the transfer (or GDS write) based on the active `HDF5_DRIVER`.
3.  **Read Phase**:
    *   Reads data back into GPU memory using `reader.Get()`.
    *   Verifies data integrity on the GPU using `thrust`.

## 3. Configuration File (`adios2.xml`)

This file provides the baseline configuration for the ADIOS2 HDF5 engine. It is read at runtime.

*   **Engine Type**: Set to `HDF5`.
*   **Parameters**:
    *   `CollectiveMetadata`: `true` (optimization).
    *   `IdleH5`: `false`.
*   **Transport**: `File` (Library `HDF5`).

## 4. Output

*   **CSV Log**: `results/h5gds_benchmark_*.csv`. Contains performance metrics and effective parameters for every run in the sweep.
*   **Data Files**: Temporary `.h5` files (deleted after verification).
*   **Visualization**: `.xdmf` files (optional).

## Summary Diagram

```mermaid
graph TD
    A[job.pbs Loop] -->|Sets Env: HDF5_DRIVER, PLUGIN_PATH| B[Environment]
    A -->|Executes: h5gds --vfd --cbuf| C[h5gds Application]
    B --> C
    D[adios2.xml] -->|Configures Engine| C
    C -->|Validates VFD & Sets Params| E[ADIOS2 Engine]
    E -->|Uses HDF5 Lib| F[Storage (GDS/POSIX)]
    C -->|Logs| G[CSV Output]
```
