# ADIOS2 Port - Build and Execution Instructions

This branch ports the codebase from direct HDF5 C-API usage to ADIOS2 C++ API, leveraging the HDF5 engine. This allows for cleaner code and native GPU support in I/O operations.

## Prerequisites

- **ADIOS2**: Built from source (see below) or available as a module.
- **HDF5**: With parallel support if MPI is used (e.g., `phdf5/1.14.6` or system `hdf5/1.14.6`).
- **HDF5 VFD GDS Plugin**: `libhdf5_vfd_gds.so` (available via `vfd-gds` module or project).
- **CUDA Toolkit**: For GPU compilation (e.g., `cuda/12.9`).

### 1. Build ADIOS2

Since ADIOS2 is not available as a standard module, you must build it from source. Run this as a job on a compute node (execute from the project root directory):

```bash
qsub build_adios2.pbs
```

This will:
- Automatically download and build ADIOS2 in the `dependencies/` folder.
- **Note:** It is safe to remove the `dependencies/` folder if you wish to trigger a fresh build. The scripts will re-download everything.
- Build ADIOS2 with HDF5 and CUDA support.
- Install to `dependencies/adios2/v2.10.2`.
- Generate `adios2_env.sh`.

**Wait for this job to complete before proceeding.**

### 2. Build Benchmark (`h5gds`)

Once ADIOS2 is ready, build the application code. Run this from the project root directory:

```bash
qsub build.pbs
```

This script (`build.sh` run via PBS) will:
- Load required modules.
- Source `adios2_env.sh`.
- Download CUDA samples into `dependencies/cuda-samples` if missing.
- Build the `h5gds` executable.

## Manual Build (Interactive)

If you prefer to build interactively (e.g., on a login node, if permitted):

1.  **Build ADIOS2**:
    ```bash
    ./scripts/build_adios2.sh .
    ```

2.  **Build Application**:
    ```bash
    ./build.sh
    ```
    ```bash
    mkdir build && cd build
    cmake .. \
        -DCUDA_SAMPLES_DIR=$(pwd)/../dependencies/cuda-samples/Common \
        -DTARGET_GPU=NVIDIA_CC90 \
        -DUSE_SYSTEM_MALLOC=ON
    ```

    The CMake configuration will:
    - Find ADIOS2 (`find_package(ADIOS2 REQUIRED)`).
    - Find the HDF5 GDS VFD library (to verify environment readiness).

3.  **Build**:
    ```bash
    make -j
    ```

    This produces the `h5gds` executable in `bin/`.

## Execution

The `job.pbs` script handles the execution environment for Miyabi.

### Submitting a Job

Execute the submission command from the project root directory:

```bash
qsub job.pbs
```

### Environment Configuration

The job script sets up the following critical environment variables for ADIOS2 to use the GDS VFD via HDF5:

1.  **`HDF5_PLUGIN_PATH`**: Points to the directory containing `libhdf5_vfd_gds.so`.
    - Defaults to `/work/jh250079/n14001/vfd-gds/build/bin` in `job.pbs`.
2.  **`HDF5_DRIVER`**: Sets the default HDF5 VFD driver.
    - `gds`: For GPUDirect Storage (gds-native, gds-compat modes).
    - `sec2`: For standard POSIX I/O.
    - This is set automatically in the job script loop.
3.  **`CUFILE_ENV_PATH_JSON`**: For GDS configuration (e.g., `disable_compat.json`).

### ADIOS2 Configuration (`adios2.xml`)

Runtime parameters are controlled via `adios2.xml` in the root directory. This file is copied to the run directory by `job.pbs`.

```xml
<io name="SimulationOutput">
    <engine type="HDF5">
        <parameter key="CollectiveMetadata" value="true"/>
        <parameter key="IdleH5" value="false"/>
    </engine>
</io>
```

To modify I/O behavior (e.g., chunking, buffering) without recompiling, edit this file.

### Parameter Sweep and Runtime Configuration

The benchmark code (`h5gds`) accepts command-line arguments (like `--cbuf`, `--vfd`) which are used by `job.pbs` to sweep through different configurations.

- **`--vfd`**: Selects the VFD driver. Supported values: `gds`, `sec2`, `direct`.
  - Sets the `HDF5_DRIVER` environment variable appropriately.
- **`--cbuf`**: Copy buffer size (bytes).
  - Passed to ADIOS2 engine as `BufferChunkSize`.
- **`--fblk`**: File block size (bytes).
  - Logged in benchmark CSV. Maps to HDF5 alignment where supported by ADIOS2 engine.
- **`--memb`**: Memory boundary (bytes).
  - Logged in benchmark CSV.
- **`--num`**: Number of particles.
- **`--skip`**: Skip verification.
- **`--xdmf`**: Generate XDMF visualization files.

This allows `job.pbs` to control the HDF5 backend performance tuning (chunking, VFD selection) automatically and produce a CSV output compatible with the original HDF5 benchmark.

## Output

Results are saved in `results/`.
- **CSV Logs**: `h5gds_benchmark_gpu0.csv` containing performance metrics (write/read latency, bandwidth).
- **HDF5 Files**: Temporary files (`dat/*.h5`) are created during the run and deleted afterwards.
- **XDMF Files**: If enabled, `dat/*.xdmf` files describe the HDF5 data for visualization (e.g., ParaView).

## Troubleshooting

- **"HDF5 Driver not found"**: Ensure `HDF5_PLUGIN_PATH` is correct and contains `libhdf5_vfd_gds.so`.
- **"ADIOS2 HDF5 Engine Error"**: Check `adios2.xml` syntax and ensuring `HDF5_DRIVER` is compatible with the build.
- **"Bad address" / Runtime Crash**: If you see `HDF5FDsec2.c ... Bad address`, it means ADIOS2 is trying to read GPU memory as CPU memory. This indicates **ADIOS2 was built without CUDA support**. Rebuild ADIOS2 using `scripts/build_adios2.sh` and ensure the `CUDA` component is found during `build.sh`.
- **Performance Issues**: Verify GDS is active using `nvidia-smi` or profiling tools. Ensure `HDF5_DRIVER=gds` is set.
