#!/bin/bash
#PBS -q S
#PBS -l select=1:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_same_node_lustre
#PBS -j oe

# =========================================================================================
# EXPERIMENT: Local Lustre (Same-node context)
# DESCRIPTION:
#   Runs on 1 node.
#   Writes to the shared Lustre filesystem.
#   Note: "Local" here implies a single-client baseline access to the parallel filesystem.
# =========================================================================================

cd $PBS_O_WORKDIR

# DEFINABLE PATHS
# Ensure this path is on the Lustre filesystem
OUTPUT_PATH="/lustre/home/$(whoami)/dat"

echo "Running Same-node Lustre benchmark..."
echo "Output Path: $OUTPUT_PATH"

mpirun -np 1 -N 1 ./build/bin/h5gds --output-path "$OUTPUT_PATH" --num 1048576
