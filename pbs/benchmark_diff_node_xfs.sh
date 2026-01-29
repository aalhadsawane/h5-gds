#!/bin/bash
#PBS -q S
#PBS -l select=2:ncpus=72:ngpus=1:mpiprocs=1
#PBS -N h5gds_diff_node_xfs
#PBS -j oe

cd $PBS_O_WORKDIR

# Rank 0 writes to local XFS
# Rank 1 writes to Rank 0's XFS mounted via NFS over RDMA at /mnt/remote_xfs
mpirun -np 2 -N 1 ./build/bin/h5gds --output-path /local/xfs --output-path /mnt/remote_xfs --num 1048576
