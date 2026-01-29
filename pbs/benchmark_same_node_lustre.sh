#!/bin/bash
#PBS -q S
#PBS -l select=1:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_same_node_lustre
#PBS -j oe

cd $PBS_O_WORKDIR

# Single node Lustre access
mpirun -np 1 -N 1 ./build/bin/h5gds --output-path /lustre/home/$(whoami)/dat --num 1048576
