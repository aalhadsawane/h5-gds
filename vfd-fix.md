diff --git a/CMakeLists.txt b/CMakeLists.txt
index 3b97a65..209ae10 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -1,4 +1,4 @@
-cmake_minimum_required(VERSION 3.23 FATAL_ERROR)
+cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

 # Setup cmake policies.
 foreach(policy
@@ -31,21 +31,23 @@ project(HDF5_VFD_GDS C)
 #------------------------------------------------------------------------------
 # Setup install and output Directories
 #------------------------------------------------------------------------------
+include(GNUInstallDirs)
+
 if(NOT HDF5_VFD_GDS_INSTALL_BIN_DIR)
-  set(HDF5_VFD_GDS_INSTALL_BIN_DIR ${CMAKE_INSTALL_PREFIX}/bin)
+  set(HDF5_VFD_GDS_INSTALL_BIN_DIR ${CMAKE_INSTALL_BINDIR})
 endif()
 if(NOT HDF5_VFD_GDS_INSTALL_LIB_DIR)
-  set(HDF5_VFD_GDS_INSTALL_LIB_DIR ${CMAKE_INSTALL_PREFIX}/lib)
+  set(HDF5_VFD_GDS_INSTALL_LIB_DIR ${CMAKE_INSTALL_LIBDIR})
 endif()
 if(NOT HDF5_VFD_GDS_INSTALL_INCLUDE_DIR)
   # Interface include will default to prefix/include
   set(HDF5_VFD_GDS_INSTALL_INTERFACE include)
-  set(HDF5_VFD_GDS_INSTALL_INCLUDE_DIR ${CMAKE_INSTALL_PREFIX}/include)
+  set(HDF5_VFD_GDS_INSTALL_INCLUDE_DIR ${CMAKE_INSTALL_INCLUDEDIR})
 else()
   set(HDF5_VFD_GDS_INSTALL_INTERFACE ${HDF5_VFD_GDS_INSTALL_INCLUDE_DIR})
 endif()
 if(NOT HDF5_VFD_GDS_INSTALL_DATA_DIR)
-  set(HDF5_VFD_GDS_INSTALL_DATA_DIR ${CMAKE_INSTALL_PREFIX}/share)
+  set(HDF5_VFD_GDS_INSTALL_DATA_DIR ${CMAKE_INSTALL_DATAROOTDIR})
 endif()

 # Setting this ensures that "make install" will leave rpaths to external
@@ -67,29 +69,16 @@ set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${HDF5_VFD_GDS_CMAKE_MODULE_PATH})
 #------------------------------------------------------------------------------
 # Locate CUDA
 #------------------------------------------------------------------------------
-find_package (CUDA REQUIRED)
-
-# Set Cufile installation directory to Cuda installation directory by default
-set (HDF5_VFD_GDS_CUFILE_DIR ${CUDA_TOOLKIT_ROOT_DIR} CACHE PATH "Cufile installation directory for Nvidia GDS support")

 # Try to locate cufile library
-find_library (HDF5_VFD_GDS_CUFILE_LIB
-  NAMES
-    cufile
-  HINTS
-    "${HDF5_VFD_GDS_CUFILE_DIR}/lib"
-    "${HDF5_VFD_GDS_CUFILE_DIR}/lib64"
-  REQUIRED
-)
+find_package(CUDAToolkit REQUIRED)

 set(HDF5_VFD_GDS_EXT_INCLUDE_DEPENDENCIES
   ${HDF5_VFD_GDS_EXT_INCLUDE_DEPENDENCIES}
-  ${CUDA_INCLUDE_DIRS}
+  ${CUDAToolkit_INCLUDE_DIRS}
 )
 set(HDF5_VFD_GDS_EXT_LIB_DEPENDENCIES
   ${HDF5_VFD_GDS_EXT_LIB_DEPENDENCIES}
-  ${CUDA_LIBRARIES}
-  ${HDF5_VFD_GDS_CUFILE_LIB}
 )

 #------------------------------------------------------------------------------
@@ -158,7 +147,7 @@ message(STATUS "Configuring ${HDF5_VFD_GDS_PACKAGE} v${HDF5_VFD_GDS_VERSION_FULL
 #------------------------------------------------------------------------------
 if(APPLE AND NOT HDF5_VFD_GDS_EXTERNALLY_CONFIGURED)
   # We are doing a unix-style install i.e. everything will be installed in
-  # CMAKE_INSTALL_PREFIX/bin and CMAKE_INSTALL_PREFIX/lib etc. as on other unix
+  # ${CMAKE_INSTALL_BINDIR} and ${CMAKE_INSTALL_LIBDIR} etc. as on other unix
   # platforms. We still need to setup CMAKE_INSTALL_NAME_DIR correctly so that
   # the binaries point to appropriate location for the libraries.

@@ -306,6 +295,34 @@ endif()
 #-----------------------------------------------------------------------------
 # Source
 #-----------------------------------------------------------------------------
+
+
+
+#------------------------------------------------------------------------------
+# Workaround: cuFile library is not an official CUDA CMake target
+#------------------------------------------------------------------------------
+find_library(CUFILE_LIB
+  NAMES cufile
+  PATHS ${CUDAToolkit_LIBRARY_DIR}
+        ${CUDAToolkit_LIBRARY_DIR}/stubs
+        /work/opt/local/aarch64/cores/cuda/12.6/lib64
+  NO_DEFAULT_PATH
+)
+
+if (NOT CUFILE_LIB)
+  message(FATAL_ERROR "Could not find libcufile.so — please ensure GDS is installed.")
+else()
+  message(STATUS "Found cuFile library at: ${CUFILE_LIB}")
+endif()
+
+# Make it a CMake imported target for consistency
+add_library(CUDA::cuFile UNKNOWN IMPORTED)
+set_target_properties(CUDA::cuFile PROPERTIES
+  IMPORTED_LOCATION ${CUFILE_LIB}
+  INTERFACE_INCLUDE_DIRECTORIES ${CUDAToolkit_INCLUDE_DIRS}
+)
+
+
 add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/src)

 #-----------------------------------------------------------------------------
[n14001@miyabi-g3 vfd-gds]$ git status
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   CMakeLists.txt

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        build/

no changes added to commit (use "git add" and/or "git commit -a")
[n14001@miyabi-g3 vfd-gds]$ git status
On branch master
Your branch is up to date with 'origin/master'.

Changes not staged for commit:
  (use "git add <file>..." to update what will be committed)
  (use "git restore <file>..." to discard changes in working directory)
        modified:   CMakeLists.txt

Untracked files:
  (use "git add <file>..." to include in what will be committed)
        build/

no changes added to commit (use "git add" and/or "git commit -a")
[n14001@miyabi-g3 vfd-gds]$ qstat
Miyabi scheduled stop time: 2025/10/29(Wed) 09:00:00 (Remain: 20days 13:59:51)

JOB_ID            JOB_NAME   STATUS    PROJECT    QUEUE           START_DATE       ELAPSE        TOKEN NODE MIG
902244            h5gds_job  RUNNING   jh250079   small-g         10/08 18:55:33   00:04:10        0.1    1   -
[n14001@miyabi-g3 vfd-gds]$ git diff HEAD~1 CMakeLists.txt
diff --git a/CMakeLists.txt b/CMakeLists.txt
index 3b97a65..209ae10 100644
--- a/CMakeLists.txt
+++ b/CMakeLists.txt
@@ -1,4 +1,4 @@
-cmake_minimum_required(VERSION 3.23 FATAL_ERROR)
+cmake_minimum_required(VERSION 3.25 FATAL_ERROR)

 # Setup cmake policies.
 foreach(policy
@@ -31,21 +31,23 @@ project(HDF5_VFD_GDS C)
 #------------------------------------------------------------------------------
 # Setup install and output Directories
 #------------------------------------------------------------------------------
+include(GNUInstallDirs)
+
 if(NOT HDF5_VFD_GDS_INSTALL_BIN_DIR)
-  set(HDF5_VFD_GDS_INSTALL_BIN_DIR ${CMAKE_INSTALL_PREFIX}/bin)
+  set(HDF5_VFD_GDS_INSTALL_BIN_DIR ${CMAKE_INSTALL_BINDIR})
 endif()
 if(NOT HDF5_VFD_GDS_INSTALL_LIB_DIR)
-  set(HDF5_VFD_GDS_INSTALL_LIB_DIR ${CMAKE_INSTALL_PREFIX}/lib)
+  set(HDF5_VFD_GDS_INSTALL_LIB_DIR ${CMAKE_INSTALL_LIBDIR})
 endif()
 if(NOT HDF5_VFD_GDS_INSTALL_INCLUDE_DIR)
   # Interface include will default to prefix/include
   set(HDF5_VFD_GDS_INSTALL_INTERFACE include)
-  set(HDF5_VFD_GDS_INSTALL_INCLUDE_DIR ${CMAKE_INSTALL_PREFIX}/include)
+  set(HDF5_VFD_GDS_INSTALL_INCLUDE_DIR ${CMAKE_INSTALL_INCLUDEDIR})
 else()
   set(HDF5_VFD_GDS_INSTALL_INTERFACE ${HDF5_VFD_GDS_INSTALL_INCLUDE_DIR})
 endif()
 if(NOT HDF5_VFD_GDS_INSTALL_DATA_DIR)
-  set(HDF5_VFD_GDS_INSTALL_DATA_DIR ${CMAKE_INSTALL_PREFIX}/share)
+  set(HDF5_VFD_GDS_INSTALL_DATA_DIR ${CMAKE_INSTALL_DATAROOTDIR})
 endif()

 # Setting this ensures that "make install" will leave rpaths to external
@@ -67,29 +69,16 @@ set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${HDF5_VFD_GDS_CMAKE_MODULE_PATH})
 #------------------------------------------------------------------------------
 # Locate CUDA
 #------------------------------------------------------------------------------
-find_package (CUDA REQUIRED)
-
-# Set Cufile installation directory to Cuda installation directory by default
-set (HDF5_VFD_GDS_CUFILE_DIR ${CUDA_TOOLKIT_ROOT_DIR} CACHE PATH "Cufile installation directory for Nvidia GDS support")

 # Try to locate cufile library
-find_library (HDF5_VFD_GDS_CUFILE_LIB
-  NAMES
-    cufile
-  HINTS
-    "${HDF5_VFD_GDS_CUFILE_DIR}/lib"
-    "${HDF5_VFD_GDS_CUFILE_DIR}/lib64"
-  REQUIRED
-)
+find_package(CUDAToolkit REQUIRED)

 set(HDF5_VFD_GDS_EXT_INCLUDE_DEPENDENCIES
   ${HDF5_VFD_GDS_EXT_INCLUDE_DEPENDENCIES}
-  ${CUDA_INCLUDE_DIRS}
+  ${CUDAToolkit_INCLUDE_DIRS}
 )
 set(HDF5_VFD_GDS_EXT_LIB_DEPENDENCIES
   ${HDF5_VFD_GDS_EXT_LIB_DEPENDENCIES}
-  ${CUDA_LIBRARIES}
-  ${HDF5_VFD_GDS_CUFILE_LIB}
 )

 #------------------------------------------------------------------------------
@@ -158,7 +147,7 @@ message(STATUS "Configuring ${HDF5_VFD_GDS_PACKAGE} v${HDF5_VFD_GDS_VERSION_FULL
 #------------------------------------------------------------------------------
 if(APPLE AND NOT HDF5_VFD_GDS_EXTERNALLY_CONFIGURED)
   # We are doing a unix-style install i.e. everything will be installed in
-  # CMAKE_INSTALL_PREFIX/bin and CMAKE_INSTALL_PREFIX/lib etc. as on other unix
+  # ${CMAKE_INSTALL_BINDIR} and ${CMAKE_INSTALL_LIBDIR} etc. as on other unix
   # platforms. We still need to setup CMAKE_INSTALL_NAME_DIR correctly so that
   # the binaries point to appropriate location for the libraries.

@@ -306,6 +295,34 @@ endif()
 #-----------------------------------------------------------------------------
 # Source
 #-----------------------------------------------------------------------------
+
+
+
+#------------------------------------------------------------------------------
+# Workaround: cuFile library is not an official CUDA CMake target
+#------------------------------------------------------------------------------
+find_library(CUFILE_LIB
+  NAMES cufile
+  PATHS ${CUDAToolkit_LIBRARY_DIR}
+        ${CUDAToolkit_LIBRARY_DIR}/stubs
+        /work/opt/local/aarch64/cores/cuda/12.6/lib64
+  NO_DEFAULT_PATH
+)
+
+if (NOT CUFILE_LIB)
+  message(FATAL_ERROR "Could not find libcufile.so — please ensure GDS is installed.")
+else()
+  message(STATUS "Found cuFile library at: ${CUFILE_LIB}")
+endif()
+
+# Make it a CMake imported target for consistency
+add_library(CUDA::cuFile UNKNOWN IMPORTED)
+set_target_properties(CUDA::cuFile PROPERTIES
+  IMPORTED_LOCATION ${CUFILE_LIB}
+  INTERFACE_INCLUDE_DIRECTORIES ${CUDAToolkit_INCLUDE_DIRS}
+)
+
+
 add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/src)

 #-----------------------------------------------------------------------------
