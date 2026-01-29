# Verification and Testing Guide

This guide provides steps to verify the functionality and correctness of the `h5gds` tool after the MPI and custom path extensions.

## 1. Compilation Check

Ensure the project compiles correctly with MPI and HDF5.

```sh
mkdir -p build
cmake -S . -B build
cmake --build build -j
```

## 2. Basic Functionality Test (Single Rank)

Run a small test locally to verify that the tool still works in single-process mode and correctly creates output files in the specified path.

```sh
mkdir -p test_dat
./build/bin/h5gds --num 1024 --output-path ./test_dat
ls test_dat/*.h5
```

## 3. MPI and Multi-Path Verification

Verify that multiple ranks correctly target different output paths.

```sh
mkdir -p dat_rank0 dat_rank1
mpirun -np 2 ./build/bin/h5gds --num 1024 --output-path ./dat_rank0 --output-path ./dat_rank1
ls dat_rank0/*.h5
ls dat_rank1/*.h5
```

## 4. Source File Loading Verification

1.  Generate a file first.
2.  Use that file as a source for another run.

```sh
# Step 1: Generate source data
mkdir -p test_src
mpirun -np 1 ./build/bin/h5gds --num 2048 --output-path ./test_src --asis
# Identify the generated file (e.g., test_src/uuid_rank0.h5)
SRC_FILE=$(ls test_src/*_rank0.h5 | head -n 1)

# Step 2: Run benchmark using the source file
mkdir -p test_out
mpirun -np 1 ./build/bin/h5gds --source-file $SRC_FILE --output-path ./test_out --asis
```

## 5. Consistency Check

The tool performs a bit-wise consistency check between the data written to storage and the original data in GPU memory (unless `--skip` is used). If the tool exits with `EXIT_SUCCESS`, the verification passed.

To force a fail (if you want to test the checker), you could theoretically corrupt the file between write and read, but for normal verification, simply seeing the tool finish successfully is enough.

## 6. Aggregated Results Check

Verify that Rank 0 outputs the "Aggregated Results" summary to stdout. It should look like this:

```
--- Aggregated Results (2 ranks) ---
Total Data Size:  X bytes
Max Write Latency: Y s
Max Read Latency:  Z s
Aggregated Write Bandwidth: ... bytes/s
Aggregated Read Bandwidth:  ... bytes/s
```

## 7. CSV Log Verification

Check `log/h5gds_benchmark.csv` to ensure all ranks are appending their results.

```sh
cat log/h5gds_benchmark.csv
```
