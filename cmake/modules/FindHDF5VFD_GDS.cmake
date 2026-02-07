# Try to find Virtual File Driver for GPUDirect Storage via HDF5, written by Yohei Miki
# search include directory
find_path(HDF5VFD_GDS_INCLUDE_DIR H5FDgds.h
  PATHS
  ENV VFD_GDS_INC
  ENV VFD_GDS_DIR
  ENV CPATH
  ${VFD_GDS_INC}
  ${VFD_GDS_DIR}
  ${CPATH}
  PATH_SUFFIXES
  include
)
set(HDF5VFD_GDS_INCLUDE_DIRS ${HDF5VFD_GDS_INCLUDE_DIR})

# search library path
find_library(HDF5VFD_GDS_LIBRARY
  NAMES
  hdf5_vfd_gds
  PATHS
  ENV VFD_GDS_LIB
  ENV VFD_GDS_DIR
  ENV LD_LIBRARY_PATH
  ${VFD_GDS_LIB}
  ${VFD_GDS_DIR}
  ${LD_LIBRARY_PATH}
  PATH_SUFFIXES
  lib
)
set(HDF5VFD_GDS_LIBRARIES ${HDF5VFD_GDS_LIBRARY})

# hide variables except in advanced mode
mark_as_advanced(HDF5VFD_GDS_INCLUDE_DIR HDF5VFD_GDS_LIBRARY)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(HDF5VFD_GDS
  REQUIRED_VARS
  HDF5VFD_GDS_INCLUDE_DIRS
  HDF5VFD_GDS_LIBRARIES
)
