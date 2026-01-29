#!/bin/bash
#PBS -q S
#PBS -l select=2:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_diff_node_lustre
#PBS -j oe

cd $PBS_O_WORKDIR

# Two nodes accessing Lustre (shared parallel filesystem)
mpirun -np 2 -N 1 ./build/bin/h5gds --output-path /lustre/home/$(whoami)/dat --num 1048576
