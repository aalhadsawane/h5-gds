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

ADIOS2_VERSION="v2.10.2" # Using a stable release tag
INSTALL_DIR="${PROJECT_ROOT}/dependencies/adios2/${ADIOS2_VERSION}"
BUILD_DIR="${PROJECT_ROOT}/dependencies/adios2-build"
SOURCE_DIR="${PROJECT_ROOT}/dependencies/adios2-src"

# --- Modules ---
# Adjust these based on 'module avail' output on Miyabi
module purge
module load cmake/3.31.1
module load hdf5/1.14.6
module load cuda/12.9
module load mpi/nvidia/25.9 # Assuming NVHPC SDK or similar MPI
# If HDF5 is parallel (phdf5), use that instead of serial hdf5
# module load phdf5/1.14.6

echo "=== Environment ==="
module list
echo "CC=$CC"
echo "CXX=$CXX"
echo "FC=$FC"
echo "HDF5_ROOT=$HDF5_ROOT" # Check if module sets this
echo "CUDA_HOME=$CUDA_HOME"

# --- Clone ---
mkdir -p "${PROJECT_ROOT}/dependencies"
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "Cloning ADIOS2 (${ADIOS2_VERSION})..."
    git clone --depth 1 --branch ${ADIOS2_VERSION} https://github.com/ornladios/ADIOS2.git "${SOURCE_DIR}"
else
    echo "ADIOS2 source found at ${SOURCE_DIR}"
fi

# --- Configure ---
echo "Configuring ADIOS2..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Note: Adjust CMAKE_CXX_COMPILER if needed (e.g., nvc++)
# -DADIOS2_USE_HDF5=ON : Enable HDF5 engine
# -DADIOS2_USE_CUDA=ON : Enable GPU support
# -DADIOS2_USE_Fortran=OFF : Disable Fortran to save build time (unless needed)
# -DADIOS2_USE_Python=OFF : Disable Python bindings (unless needed)
# -DADIOS2_BUILD_EXAMPLES=OFF : Skip examples

cmake "${SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DADIOS2_USE_HDF5=ON \
    -DADIOS2_USE_CUDA=ON \
    -DADIOS2_USE_Fortran=OFF \
    -DADIOS2_USE_Python=OFF \
    -DADIOS2_BUILD_EXAMPLES=OFF \
    -DADIOS2_BUILD_TESTING=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON

# --- Build & Install ---
echo "Building ADIOS2 (using $(nproc) threads)..."
make -j$(nproc)

echo "Installing to ${INSTALL_DIR}..."
make install

# --- Usage Instructions ---
echo ""
echo "=== Build Complete ==="
echo "To use this ADIOS2 installation, add the following to your environment (e.g., .bashrc or job script):"
echo ""
echo "export ADIOS2_DIR=${INSTALL_DIR}"
echo "export PATH=\${ADIOS2_DIR}/bin:\${PATH}"
echo "export LD_LIBRARY_PATH=\${ADIOS2_DIR}/lib64:\${LD_LIBRARY_PATH}"
echo "export CMAKE_PREFIX_PATH=\${ADIOS2_DIR}:\${CMAKE_PREFIX_PATH}"
echo ""
echo "Or create a custom modulefile."
