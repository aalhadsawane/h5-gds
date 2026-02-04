# h5gds (ADIOS2 Port)

* Simple benchmark code for GPUDirect Storage (GDS) via ADIOS2 (HDF5 Engine)
* Developed by Yohei MIKI (Information Technology Center, The University of Tokyo)
* Released under the MIT license, see LICENSE for detail
* Copyright (c) 2023 Information Technology Center, The University of Tokyo

## How to compile

* Required software
  * [CMake](https://cmake.org/) (>= 3.20.0)
  * [Boost C++ Libraries](https://www.boost.org/)
  * [CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit) (with GDS support)
  * [CUDA Samples](https://github.com/nvidia/cuda-samples)
    * set path of directly contains `helper_cuda.h` as `CPATH`, `CUDA_SAMPLES_DIR`, or `CUDA_SAMPLES_INC` for CMake
    * otherwise, edit `cmake/modules/FindCUDA_samples.cmake` properly
  * [ADIOS2](https://github.com/ornladios/ADIOS2) (with HDF5 and CUDA support)
    * set path via `ADIOS2_ROOT` or `CMAKE_PREFIX_PATH`
  * [MPI](https://www.mpi-forum.org/) (for multi-node benchmarks)

* Configuration using CUI

  ```sh
  cmake -S . -B build [option]
  cd build
  make
  ```

* List of configure option(s)

  | input | note |
  | ---- | ---- |
  | `-DTARGET_GPU=[NVIDIA_CC90 NVIDIA_CC80 NVIDIA_CC86]` | target GPU architecture (e.g., NVIDIA_CC90 for NVIDIA H100) |

## How to run

* Execution (Single Process)

  ```sh
  bin/h5gds [option]
  ```

* Execution (Multi Process / Multi Node)

  ```sh
  mpirun -np 2 -N 1 bin/h5gds [option]
  ```

  * Execution in native mode (force to use GDS)

    ```sh
    CUFILE_JSON=./disable_compat.json mpirun -np 2 -N 1 bin/h5gds [option]
    ```

  * Execution in compatible mode (read/write via host CPU)

    ```sh
    CUFILE_JSON=./force_compat.json mpirun -np 2 -N 1 bin/h5gds [option]
    ```

* List of execution options
  * options have impact on benchmark score

    | input | note |
    | ---- | ---- |
    | `--num VALUE` | set VALUE as number of particles |

  * options have no impact on benchmark score

    | input | note |
    | ---- | ---- |
    | `--help` | show help message |
    | `--skip` | skip consistency check between read and original data |
    | `--virial VALUE` | set VALUE as the initial Virial ratio of the system |
    | `--radius VALUE` | set VALUE as the initial radius of the system |
    | `--mass VALUE` | set VALUE as the total mass of the system |
    | `--output-path PATH` | set PATH as directory to write benchmark files (default: `dat`). Can be specified multiple times for different ranks. |
    | `--input-path PATH` | set PATH as the file to read during read benchmark. If omitted, the file written in the write phase is used. |
    | `--source-file FILE` | load initial GPU data from FILE instead of generating it. Can be specified multiple times for different ranks. |

* Configuration via `adios2_config.xml`
    * The engine type and parameters (e.g., GDS settings) can be configured in `adios2_config.xml` located in the execution directory.

## Multi-node Benchmarking on Miyabi Supercomputer

This tool is extended to support performance comparisons between local and remote storage on Miyabi (GraceHopper architecture).

### Architecture Assumption

The tool is configured with a hardcoded assumption of **72 cores per node** (`MIYABI_CORES_PER_NODE`), matching the Miyabi system architecture. This is used to calculate:
*   **Node ID**: `mpi_rank / 72`
*   **Local Rank**: `mpi_rank % 72`
*   **GPU ID**: `local_rank % device_count` (since Miyabi has 1 GPU per node, this is typically 0).

### Example: Local XFS SSD vs Remote NFS-RDMA

To compare a local SSD (Rank 0) with a remote SSD mounted via NFS-RDMA (Rank 1):

```sh
mpirun -np 2 -N 1 bin/h5gds --output-path /local/xfs --output-path /mnt/remote_xfs --num 1048576
```

### Aggregated Results

Rank 0 will report aggregated results including:
*   Total data size across all ranks.
*   Maximum write/read latency.
*   Aggregated bandwidth (Total Size / Max Latency).

Detailed per-rank results are appended to `log/h5gds_benchmark.csv`.

## Output Files

*   **HDF5 Data**: `<output-path>/<uuid>_rank<rank>.h5`
    *   Written via ADIOS2 HDF5 Engine.
*   **Benchmark Log**: `log/h5gds_benchmark.csv` (includes per-rank statistics)

## Data types

* $N$-element arrays to represent $N$-body particles

  | quantity | data on GPU | ADIOS2 variable | Shape |
  | ---- | ---- | ---- | ---- |
  | position (x, y, z) <br> mass (w) | float4 pos[N] | `pos_mass` | [N, 4] |
  | velocity (x, y) <br> velocity(z) | float2 vel_xy[N] <br> float vel_z[N] | `vel_xy` <br> `vel_z` | [N, 2] <br> [N] |
  | particle ID | uint64_t idx[N] | `id` | [N] |
