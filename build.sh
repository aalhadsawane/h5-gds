# Load required modules
module purge
module load cmake/3.31.1
module load hdf5/1.14.6
module load cuda/12.9

# Set ADIOS2 environment (assuming default install from build script)
export ADIOS2_DIR=${HOME}/opt/adios2/v2.10.2
export PATH=${ADIOS2_DIR}/bin:${PATH}
export LD_LIBRARY_PATH=${ADIOS2_DIR}/lib64:${LD_LIBRARY_PATH}
export CMAKE_PREFIX_PATH=${ADIOS2_DIR}:${CMAKE_PREFIX_PATH}

cmake -S . -B build \
    -DCUDA_SAMPLES_DIR=/work/jh250079/n14001/cuda-samples/Common \
    -DTARGET_GPU=NVIDIA_CC90 \
    -DUSE_SYSTEM_MALLOC=ON
