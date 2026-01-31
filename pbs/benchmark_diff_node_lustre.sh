#!/bin/bash
#PBS -q S
#PBS -l select=2:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_diff_node_lustre
#PBS -j oe

# =========================================================================================
# EXPERIMENT: Remote Lustre (Different-node context)
# DESCRIPTION:
#   Runs on 2 nodes.
#   Both write to the shared Lustre filesystem.
#   This measures aggregated bandwidth/latency from multiple client nodes.
# =========================================================================================

cd $PBS_O_WORKDIR

# DEFINABLE PATHS
OUTPUT_PATH="/lustre/home/$(whoami)/dat"

echo "Running Different-node Lustre benchmark..."
echo "Output Path: $OUTPUT_PATH"

mpirun -np 2 -N 1 ./build/bin/h5gds --output-path "$OUTPUT_PATH" --num 1048576
