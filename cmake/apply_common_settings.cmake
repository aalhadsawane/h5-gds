# set CPU architecture
include(${USER_MODULE_PATH}/set_target_cpu.cmake)

# set GPU architecture
include(${USER_MODULE_PATH}/set_target_gpu.cmake)

# find OpenMP
find_package(OpenMP)

# set compilation flags
include(${USER_MODULE_PATH}/set_compile_flag.cmake)

# find Boost
set(BOOST_INCLUDEDIR ${SEARCH_PATH})

if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.20)
  set(Boost_NO_WARN_NEW_VERSIONS ON)
endif(CMAKE_VERSION VERSION_GREATER_EQUAL 3.20)

set(Boost_USE_STATIC_LIBS OFF)
set(Boost_USE_DEBUG_LIBS OFF)
set(Boost_USE_RELEASE_LIBS ON)
set(Boost_USE_MULTITHREADED ON)
set(Boost_USE_STATIC_RUNTIME OFF)
find_package(Boost REQUIRED COMPONENTS program_options filesystem timer system)

# find ADIOS2 (only for h5gds project)
if(PROJECT_NAME STREQUAL "h5gds")
  # ADIOS2 depends on MPI::MPI_C, so we must enable C and find MPI
  enable_language(C)
  find_package(MPI REQUIRED)
  find_package(ADIOS2 REQUIRED)

  # Find HDF5 to ensure proper linking/rpath for shared libraries
  find_package(HDF5 REQUIRED COMPONENTS C)

  # Check for GDS VFD availability (for runtime environment setup)
  find_package(HDF5VFD_GDS REQUIRED COMPONENTS C)
  if(HDF5VFD_GDS_FOUND)
    message(STATUS "GDS VFD Library found at: ${HDF5VFD_GDS_LIBRARIES}")
    # We do not link it directly as ADIOS2 loads it dynamically via HDF5,
    # but finding it ensures the environment is correct.
  endif()
endif()

# link libraries
target_link_libraries(${PROJECT_NAME} PRIVATE
  ${Boost_LIBRARIES}
)

# Link ADIOS2 and HDF5 only for h5gds project
if(PROJECT_NAME STREQUAL "h5gds")
  target_link_libraries(${PROJECT_NAME} PRIVATE
    adios2::adios2
    ${HDF5_LIBRARIES}
  )
endif()

target_link_libraries(${PROJECT_NAME} PRIVATE
  # OpenMP
  $<$<AND:$<BOOL:${OpenMP_FOUND}>,$<NOT:$<CXX_COMPILER_ID:NVHPC>>>:${OpenMP_CXX_FLAGS}>

  # memory sanitizer
  $<$<BOOL:${USE_SANITIZER_ADDRESS}>:-fsanitize=address>
  $<$<BOOL:${USE_SANITIZER_LEAK}>:-fsanitize=leak>
  $<$<BOOL:${USE_SANITIZER_UNDEFINED}>:-fsanitize=undefined>
  $<$<BOOL:${USE_SANITIZER_THREAD}>:-fsanitize=thread>
)

# include directories
target_include_directories(${PROJECT_NAME} PRIVATE
  ${PROJECT_SOURCE_DIR}
  ${CMAKE_SOURCE_DIR}/src
)
target_include_directories(${PROJECT_NAME} SYSTEM PRIVATE
  ${Boost_INCLUDE_DIRS}
)

# add definitions
target_compile_definitions(${PROJECT_NAME} PUBLIC
  $<$<NOT:$<CONFIG:Debug>>:NDEBUG>
)
