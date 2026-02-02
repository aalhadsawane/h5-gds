#!/bin/bash
#PBS -q S
#PBS -l select=2:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_diff_node_xfs
#PBS -j oe

# =========================================================================================
# EXPERIMENT: Remote XFS (Different-node) via NFS over RDMA
# DESCRIPTION:
#   Runs on 2 nodes (Rank 0 on Node A, Rank 1 on Node B).
#   Rank 0 writes to Local XFS (Reference).
#   Rank 1 writes to Remote XFS (Target).
#
# PREREQUISITE:
#   You must mount Node A's /local/xfs on Node B at /mnt/remote_xfs (or similar).
#   See troubleshoot.md for details.
# =========================================================================================

cd $PBS_O_WORKDIR

# DEFINABLE PATHS
# Path for Rank 0 (Local)
LOCAL_PATH="/local/xfs"
# Path for Rank 1 (Remote - must be a mount point)
REMOTE_PATH="/mnt/remote_xfs"

echo "Running Different-node XFS benchmark..."
echo "Rank 0 writes to: $LOCAL_PATH"
echo "Rank 1 writes to: $REMOTE_PATH"

# The tool cycles through --output-path arguments based on rank.
# Rank 0 -> LOCAL_PATH
# Rank 1 -> REMOTE_PATH
mpirun -np 2 -N 1 ./build/bin/h5gds \
    --output-path "$LOCAL_PATH" \
    --output-path "$REMOTE_PATH" \
    --num 1048576
