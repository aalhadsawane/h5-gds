#!/bin/bash
#PBS -q gpu
#PBS -l elapstim_req=24:00:00
#PBS -b 1
#PBS -A GALAXY
#PBS -N h5gds_scr

NUM_MIN=1024
NUM_MAX=134217728
ELAPSE_MAX=600s
COMMON_OPTOIN=""
CUFILE_JSON=${PBS_O_WORKDIR}/disable_compat.json
# CUFILE_JSON=${PBS_O_WORKDIR}/force_compat.json

# job execution via NQSV
# set stdout and stderr

module purge
module load cuda/12.1.0
module use /work/CSPP/ymiki/opt/modules/compiler
module load cuda-samples/12.1
module use /work/CSPP/ymiki/opt/modules/lib
module load boost/1.81.0
module load hdf5/1.14.1-2
module load vfd-gds/1.0.2

# start logging
module list
lshw -class storage
TIME=`date`
echo "start: $TIME"

for MODE in 0 1
do
    if [ $MODE -eq 0 ]; then
        OPTION="--asis"
        DIR=asis
    fi
    if [ $MODE -eq 1 ]; then
        OPTION=""
        DIR=hyperslab
    fi
	mkdir -p ${PBS_O_WORKDIR}/${DIR}

    # make scratch region
    SCRATCH=/scr/$DIR
    mkdir -p $SCRATCH
    cd $SCRATCH

    # copy the software
    cp -r ${PBS_O_WORKDIR}/bin .
    cp -r ${PBS_O_WORKDIR}/dat .
    cp -r ${PBS_O_WORKDIR}/log .

	# configure GDS via JSON (force GDS or use compatible mode)
	export CUFILE_ENV_PATH_JSON=${CUFILE_JSON}

    # execute the job
    numactl --localalloc $CUDA_PATH/gds/tools/gdscheck -p

    # try asis first and copy; then, try hyperslab version
    for (( NUM = $NUM_MIN ; NUM <= $NUM_MAX ; NUM *= 2 ))
    do
        timeout ${ELAPSE_MAX} numactl --localalloc bin/h5gds ${COMMON_OPTOIN} $OPTION --num $NUM
		rsync -av log ${PBS_O_WORKDIR}/${DIR}
		rsync -av dat ${PBS_O_WORKDIR}/${DIR}
    done

    # copy results
    rsync -av ${SCRATCH} ${PBS_O_WORKDIR}
done

# finish logging
TIME=`date`
echo "finish: $TIME"

exit 0
