///
/// @file common.cuh
/// @author Yohei MIKI (The University of Tokyo)
/// @brief global settings
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#ifndef COMMON_CUH
#define COMMON_CUH

#include <cuda.h>

#ifndef NTHREADS
#define NTHREADS (512)
#endif  // NTHREADS

///
/// @brief datatypes
///
namespace type {
using pos = float4;     // datatype for particle position
using vel_xy = float2;  // datatype for particle velocity (x and y)
using vel_z = float;    // datatype for particle velocity (z)
using idx = uint64_t;   // datatype for particle ID
}  // namespace type

#endif  // COMMON_CUH
