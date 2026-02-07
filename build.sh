# Load required modules
module purge
module load nvidia/25.9
module load nv-hpcx/25.9
module load cmake/3.31.1
module load cuda/12.9
module load hdf5/1.14.6

# Set ADIOS2 environment (assuming default install from build script)
# Load generated environment script if present
if [ -f "adios2_env.sh" ]; then
    source "adios2_env.sh"
else
    echo "WARNING: adios2_env.sh not found. Assuming ADIOS2 is already in environment."
fi

# Check for CUDA_SAMPLES_DIR env var, default to legacy path if not set
if [ -z "$CUDA_SAMPLES_DIR" ]; then
    CUDA_SAMPLES_DIR="/work/jh250079/n14001/cuda-samples/Common"
    echo "WARNING: CUDA_SAMPLES_DIR not set. Using default: $CUDA_SAMPLES_DIR"
else
    echo "Using CUDA_SAMPLES_DIR: $CUDA_SAMPLES_DIR"
fi

cmake -S . -B build \
    -DCUDA_SAMPLES_DIR=${CUDA_SAMPLES_DIR} \
    -DTARGET_GPU=NVIDIA_CC90 \
    -DUSE_SYSTEM_MALLOC=ON
