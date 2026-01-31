#!/bin/bash
#PBS -q S
#PBS -l select=2:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_same_node_xfs
#PBS -j oe

# =========================================================================================
# EXPERIMENT: Local XFS (Same-node)
# DESCRIPTION:
#   Runs on 2 nodes (1 process per node).
#   Each rank writes to its OWN local XFS storage (/local/xfs).
#   This measures the baseline performance where GPU and Storage are on the same node.
# =========================================================================================

cd $PBS_O_WORKDIR

# DEFINABLE PATHS
# Ensure /local/xfs exists and is writable on all nodes.
OUTPUT_PATH="/local/xfs"

echo "Running Same-node XFS benchmark..."
echo "Output Path: $OUTPUT_PATH (Each rank writes to its local storage)"

mpirun -np 2 -N 1 ./build/bin/h5gds --output-path "$OUTPUT_PATH" --num 1048576
