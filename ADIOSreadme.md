# ADIOS2 Port - Build and Execution Instructions

This branch ports the codebase from direct HDF5 C-API usage to ADIOS2 C++ API, leveraging the HDF5 engine. This allows for cleaner code and native GPU support in I/O operations.

## Prerequisites

- **ADIOS2**: Installed and available in the environment (e.g., `module load adios2`).
- **HDF5**: With parallel support if MPI is used.
- **HDF5 VFD GDS Plugin**: `libhdf5_vfd_gds.so` (available via `vfd-gds` project).
- **CUDA Toolkit**: For GPU compilation.

## Compilation

The build process is managed by CMake.

1.  **Load Modules**:
    ```bash
    module purge
    module load cuda
    module load adios2
    # Load HDF5 if not included in ADIOS2 module
    module load hdf5
    ```

2.  **Configure**:
    Run `build.sh` or execute CMake manually:
    ```bash
    mkdir build && cd build
    cmake .. \
        -DCUDA_SAMPLES_DIR=/path/to/cuda/samples \
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

## Output

Results are saved in `results/`.
- **CSV Logs**: `h5gds_benchmark_gpu0.csv` containing performance metrics (write/read latency, bandwidth).
- **HDF5 Files**: Temporary files (`dat/*.h5`) are created during the run and deleted afterwards.
- **XDMF Files**: If enabled, `dat/*.xdmf` files describe the HDF5 data for visualization (e.g., ParaView).

## Troubleshooting

- **"HDF5 Driver not found"**: Ensure `HDF5_PLUGIN_PATH` is correct and contains `libhdf5_vfd_gds.so`.
- **"ADIOS2 HDF5 Engine Error"**: Check `adios2.xml` syntax and ensuring `HDF5_DRIVER` is compatible with the build.
- **Performance Issues**: Verify GDS is active using `nvidia-smi` or profiling tools. Ensure `HDF5_DRIVER=gds` is set.
