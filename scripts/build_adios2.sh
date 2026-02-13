#!/bin/bash
# ADIOS2 Build Script for Miyabi Supercomputer
# This script builds ADIOS2 from source as a user-space module.
#
# Requirements:
# - Internet access (for git clone)
# - CMake (3.20+)
# - HDF5 (with parallel support if using MPI)
# - CUDA (optional, but recommended for GPU support)

# --- Configuration ---
# Get the root directory of the project (assuming script is in scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# Determine target base directory
if [ -n "$1" ]; then
    BASE_DIR="$(readlink -f "$1")"
    echo "Using custom base directory: ${BASE_DIR}"
else
    BASE_DIR="${PROJECT_ROOT}"
    echo "Using default base directory (project root): ${BASE_DIR}"
fi

# Use master branch to ensure compatibility with CMake 3.31+ and modern CUDA detection
ADIOS2_VERSION="master"
INSTALL_DIR="${BASE_DIR}/dependencies/adios2/${ADIOS2_VERSION}"
BUILD_DIR="${BASE_DIR}/dependencies/adios2-build"
SOURCE_DIR="${BASE_DIR}/dependencies/adios2-src"

# --- Modules ---
# Adjust these based on 'module avail' output on Miyabi
module purge
# Load compiler and MPI first (required for HDF5)
module load nvidia/25.9
module load nv-hpcx/25.9

# Load dependencies
module load cmake/3.31.1
module load cuda/12.9
module load hdf5/1.14.6

echo "=== Environment ==="
module list
echo "CC=$CC"
echo "CXX=$CXX"
echo "FC=$FC"
echo "HDF5_ROOT=$HDF5_ROOT" # Check if module sets this
echo "CUDA_HOME=$CUDA_HOME"

# --- Clone ---
mkdir -p "${BASE_DIR}/dependencies"
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "Cloning ADIOS2 (${ADIOS2_VERSION})..."
    git clone --depth 1 https://github.com/ornladios/ADIOS2.git "${SOURCE_DIR}"
else
    echo "ADIOS2 source found at ${SOURCE_DIR}"
    # Pull latest changes if using master
    cd "${SOURCE_DIR}"
    # Reset to avoid conflicts if previously patched
    git reset --hard HEAD
    git pull
fi

# --- Patch ---
# Explicitly disable building utility tools (bpls, adios2_reorganize)
# because they fail to link due to missing 'sys_icache_invalidate' in libdill on AArch64.
# This does NOT affect the core libraries needed by h5gds.
echo "Patching ADIOS2 to disable utility tools build..."
sed -i 's/^[^#]*add_subdirectory(utils)/#add_subdirectory(utils)/' "${SOURCE_DIR}/source/CMakeLists.txt"

# --- Configure ---
echo "Configuring ADIOS2..."
# Clean build directory to ensure fresh configuration (fix for cached variables)
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Note: Adjust CMAKE_CXX_COMPILER if needed (e.g., nvc++)
# -DADIOS2_USE_HDF5=ON : Enable HDF5 engine
# -DADIOS2_USE_CUDA=ON : Enable GPU support
# -DADIOS2_USE_Fortran=OFF : Disable Fortran to save build time (unless needed)
# -DADIOS2_USE_Python=OFF : Disable Python bindings (unless needed)
# -DADIOS2_BUILD_EXAMPLES=OFF : Skip examples

# Ensure CUDA compiler is found
export CUDACXX=$(which nvcc)

# Use GCC for C/C++ to ensure compatibility with NVCC host compiler logic
export CC=gcc
export CXX=g++

cmake "${SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DADIOS2_USE_HDF5=ON \
    -DADIOS2_USE_CUDA=ON \
    -DCMAKE_CUDA_ARCHITECTURES=90 \
    -DADIOS2_USE_Fortran=OFF \
    -DADIOS2_USE_Python=OFF \
    -DADIOS2_USE_SST=OFF \
    -DADIOS2_USE_DataMan=OFF \
    -DADIOS2_USE_Campaign=OFF \
    -DADIOS2_USE_MHS=OFF \
    -DADIOS2_USE_SysVShMem=OFF \
    -DADIOS2_USE_UCX=OFF \
    -DADIOS2_USE_ZeroMQ=OFF \
    -DADIOS2_USE_ZFP=OFF \
    -DADIOS2_USE_SZ=OFF \
    -DADIOS2_BUILD_EXAMPLES=OFF \
    -DADIOS2_BUILD_TESTING=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON

# --- Debug Configuration ---
echo "=== CMake Configuration Debug Info ==="
grep "ADIOS2_HAVE_CUDA" CMakeCache.txt || echo "ADIOS2_HAVE_CUDA not found in cache"
grep "ADIOS2_HAVE_HDF5" CMakeCache.txt || echo "ADIOS2_HAVE_HDF5 not found in cache"
grep "CMAKE_CUDA_COMPILER" CMakeCache.txt || echo "CMAKE_CUDA_COMPILER not found in cache"
echo "======================================"

# --- Build & Install ---
echo "Building ADIOS2 (using $(nproc) threads)..."
make -j$(nproc)

echo "Installing to ${INSTALL_DIR}..."
make install

# --- Generate Environment Setup Script ---
ENV_FILE="${PROJECT_ROOT}/adios2_env.sh"
echo "Generating environment setup script: ${ENV_FILE}"

cat <<EOF > "${ENV_FILE}"
#!/bin/bash
# Auto-generated ADIOS2 environment setup script
# Uses \$HOME-relative path if applicable for portability
export ADIOS2_DIR=${INSTALL_DIR/#$HOME/\$HOME}
export PATH=\${ADIOS2_DIR}/bin:\${PATH}
export LD_LIBRARY_PATH=\${ADIOS2_DIR}/lib64:\${LD_LIBRARY_PATH}
export CMAKE_PREFIX_PATH=\${ADIOS2_DIR}:\${CMAKE_PREFIX_PATH}
echo "Loaded ADIOS2 environment from \${ADIOS2_DIR}"
EOF

chmod +x "${ENV_FILE}"

# --- Usage Instructions ---
echo ""
echo "=== Build Complete ==="
echo "Environment setup script created at: ${ENV_FILE}"
echo "To use this ADIOS2 installation, run:"
echo ""
echo "  source ${ENV_FILE}"
echo ""
echo "This file is automatically sourced by build.sh and job.pbs."
