# Troubleshooting and Experiment Guide

## TO BE DONE: CONFIGURE MOUNTS

**FOR THE "DIFFERENT-NODE XFS" EXPERIMENT (`pbs/benchmark_diff_node_xfs.sh`), YOU MUST CONFIGURE NETWORK MOUNTS.**

This experiment requires that a local XFS directory on one node is mounted via NFS (preferably over RDMA for performance) on the other node.

**Configuration Steps (Requires Admin/Root):**
1.  **Export on Node A:**
    *   Ensure `/local/xfs` exists on Node A.
    *   Export it via NFS (edit `/etc/exports`).
2.  **Mount on Node B:**
    *   Create a mount point, e.g., `/mnt/remote_xfs`.
    *   Mount Node A's export: `mount -t nfs -o rdma,port=20049 <NodeA_IP>:/local/xfs /mnt/remote_xfs`
3.  **Update Script:**
    *   Edit `pbs/benchmark_diff_node_xfs.sh` and set `REMOTE_PATH="/mnt/remote_xfs"`.

**If this is not configured, Rank 1 will likely fail with a "No such file or directory" error or simply write to the local disk if the directory exists (invalidating the "Remote" test).**

---

## Common Mistakes

### 1. "No such file or directory" Error
*   **Cause:** The output path specified via `--output-path` does not exist or the user does not have write permissions.
*   **Solution:** The tool now attempts to create the directory if it doesn't exist. However, it cannot create parents if permissions are denied. Ensure you have write access to the parent directory (e.g., `/lustre/home/user/`).

### 2. Incorrect Rank/GPU Assignment
*   **Cause:** Running with a custom number of processes per node (not 72) used to cause issues.
*   **Solution:** The code has been updated to use dynamic topology detection. Check the stdout log for "Rank X assigned to Node Y, Local Rank Z, GPU W". If `Local Rank` and `GPU` do not align with your expectation (e.g., usually GPU 0 for all if 1 GPU/node), check your MPI launch parameters.

### 3. Permissions on `/local/xfs`
*   **Cause:** `/local/xfs` is often a system directory.
*   **Solution:** Ensure the user running the job has ownership or write permissions on that directory.

---

## Steps to Reproduce Experiments

### 1. Compile the Code
On a login node (Miyabi):
```sh
mkdir -p build
cd build
cmake ..
make -j
```

### 2. Prepare Output Directories
Ensure the target directories defined in the PBS scripts exist or can be created.
*   `/local/xfs` (on compute nodes)
*   `/lustre/home/$(whoami)/dat`

### 3. Submit Jobs
Navigate to the `pbs` directory and submit the desired experiment.

**Same-Node XFS (Baseline):**
```sh
qsub pbs/benchmark_same_node_xfs.sh
```

**Different-Node XFS (Network Test):**
*   **Prerequisite:** Ensure mounts are set up (see above).
```sh
qsub pbs/benchmark_diff_node_xfs.sh
```

**Lustre Benchmarks:**
```sh
qsub pbs/benchmark_same_node_lustre.sh
qsub pbs/benchmark_diff_node_lustre.sh
```

### 4. Analyze Results
*   Check the standard output file (e.g., `h5gds_same_node_xfs.o<jobid>`) for the "Aggregated Results" summary.
*   Detailed per-rank statistics are appended to `log/h5gds_benchmark.csv`.
