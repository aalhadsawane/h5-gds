#!/bin/bash
#PBS -q S
#PBS -l select=2:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_same_node_xfs
#PBS -j oe

cd $PBS_O_WORKDIR

# Each rank writes to its own local XFS SSD
mpirun -np 2 -N 1 ./build/bin/h5gds --output-path /local/xfs --num 1048576
