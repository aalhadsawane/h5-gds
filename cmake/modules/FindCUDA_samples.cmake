# Try to find CUDA samples, written by Yohei Miki
# search include directory
find_path(CUDA_samples_INCLUDE_DIR helper_cuda.h
  PATHS
  ENV CUDA_SAMPLES_INC
  ENV CUDA_SAMPLES_DIR
  ENV CPATH
  ${CUDA_SAMPLES_INC}
  ${CUDA_SAMPLES_DIR}
  ${CPATH}
  PATH_SUFFIXES
  include
)
set(CUDA_samples_INCLUDE_DIRS ${CUDA_samples_INCLUDE_DIR})

# hide variables except in advanced mode
mark_as_advanced(CUDA_samples_INCLUDE_DIR)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(CUDA_samples
  REQUIRED_VARS
  CUDA_samples_INCLUDE_DIRS
)
