#!/bin/bash
#SBATCH -J h5gds
##SBATCH -p share-batch
##SBATCH --gres=gpu:1
#SBATCH -p batch
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --time=02:00:00

NUM_MIN=1024
NUM_MAX=134217728
ELAPSE_MAX=60s
COMMON_OPTOIN=""

# job execution via slurm
CUDA_VER=12.3
module purge
module load cuda/${CUDA_VER}
module load boost
module use $HOME/opt/modules/compiler
module load cuda-samples/${CUDA_VER}
module use $HOME/opt/modules/lib
module load hdf5
module load vfd-gds

# start logging
module list
lshw -class storage
TIME=`date`
echo "start: $TIME"

for GPU_ID in 0 1 2 3
do
	export CUDA_VISIBLE_DEVICES=$GPU_ID
	GPU_DIR=gpu${GPU_ID}
	TEMP=${SLURM_SUBMIT_DIR}/temp
	mkdir -p "${TEMP}"
	DUMP=${SLURM_SUBMIT_DIR}/nvme
	mkdir -p "${DUMP}"

    BUS_ID=`nvidia-smi --format=csv,noheader --query-gpu=gpu_bus_id -i $GPU_ID | awk -F ":" '{print "0000:" $2 ":" $3}' | tr '[:upper:]' '[:lower:]'`
    NUMA_NODE=`cat /sys/bus/pci/devices/$BUS_ID/numa_node`
    # echo "cpunodebind=$NUMA_NODE for GPU $GPU_ID"
	# nvidia-smi topo -m

	ROOT=/local1/${GPU_DIR}
	for HDF5_MODE in 0 1
	do
		if [ $HDF5_MODE -eq 0 ]; then
			OPTION="--asis"
			HDF5_TAG=asis
		fi
		if [ $HDF5_MODE -eq 1 ]; then
			OPTION=""
			HDF5_TAG=hyperslab
		fi

		for GDS_MODE in 0 1
		do
			if [ $GDS_MODE -eq 0 ]; then
				# configure GDS via JSON (force GDS)
				export CUFILE_ENV_PATH_JSON=${SLURM_SUBMIT_DIR}/disable_compat.json
				GDS_TAG=native
			fi
			if [ $GDS_MODE -eq 1 ]; then
				# configure GDS via JSON (use compatible mode)
				export CUFILE_ENV_PATH_JSON=${SLURM_SUBMIT_DIR}/force_compat.json
				GDS_TAG=compat
			fi
			DIR=${HDF5_TAG}/${GDS_TAG}

			# make scratch region
			SCRATCH=$ROOT/$DIR
			mkdir -p "$SCRATCH"
			cd $SCRATCH

			# copy the software
			cp -r ${SLURM_SUBMIT_DIR}/bin .
			cp -r ${SLURM_SUBMIT_DIR}/dat .
			cp -r ${SLURM_SUBMIT_DIR}/log .

			# execute the job
			numactl --localalloc $CUDA_DIR/gds/tools/gdscheck -p

			# try asis first and copy; then, try hyperslab version
			for (( NUM = $NUM_MIN ; NUM <= $NUM_MAX ; NUM *= 2 ))
			do
				timeout ${ELAPSE_MAX} numactl --cpunodebind=$NUMA_NODE --localalloc bin/h5gds ${COMMON_OPTOIN} $OPTION --num $NUM
				rsync -av log ${TEMP}/
				rsync -av dat ${TEMP}/
			done
		done
	done
	# copy results
	rsync -av ${ROOT} ${DUMP}/
	rm -rf ${ROOT}
	rm -rf ${TEMP}
done

# finish logging
TIME=`date`
echo "finish: $TIME"

exit 0
