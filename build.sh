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

# Check for CUDA_SAMPLES_DIR env var, or find/download them
if [ -n "$CUDA_SAMPLES_DIR" ]; then
    echo "Using external CUDA_SAMPLES_DIR: $CUDA_SAMPLES_DIR"
else
    # Define potential paths
    LEGACY_PATH="/work/jh250079/n14001/cuda-samples/Common"
    LOCAL_PATH="$(pwd)/dependencies/cuda-samples/Common"

    if [ -d "$LEGACY_PATH" ]; then
        CUDA_SAMPLES_DIR="$LEGACY_PATH"
        echo "Found CUDA samples at legacy path: $CUDA_SAMPLES_DIR"
    elif [ -d "$LOCAL_PATH" ]; then
        CUDA_SAMPLES_DIR="$LOCAL_PATH"
        echo "Found CUDA samples at local path: $CUDA_SAMPLES_DIR"
    else
        echo "CUDA samples not found. Downloading..."
        mkdir -p dependencies
        # Clone specific tag or default to master. Depth 1 for speed.
        git clone --depth 1 https://github.com/NVIDIA/cuda-samples.git dependencies/cuda-samples
        CUDA_SAMPLES_DIR="$LOCAL_PATH"
        echo "Downloaded CUDA samples to: $CUDA_SAMPLES_DIR"
    fi
fi

cmake -S . -B build \
    -DCUDA_SAMPLES_DIR=${CUDA_SAMPLES_DIR} \
    -DTARGET_GPU=NVIDIA_CC90 \
    -DUSE_SYSTEM_MALLOC=ON
