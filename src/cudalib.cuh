///
/// @file cudalib.cuh
/// @author Yohei MIKI (The University of Tokyo)
/// @brief utility tools for CUDA programming
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#ifndef CUDALIB_CUH
#define CUDALIB_CUH

#define GRIDDIM_X1D (gridDim.x)
#define BLOCKDIM_X1D (blockDim.x)
#define BLOCKIDX_X1D (blockIdx.x)
#define THREADIDX_X1D (threadIdx.x)
#define GLOBALIDX_X1D ((THREADIDX_X1D) + (BLOCKIDX_X1D) * (BLOCKDIM_X1D))

///
/// @brief required block size for the given problem size and number of threads per thread-block
///
#define BLOCKSIZE(num, thread) (1 + (((num)-1) / (thread)))

#endif  // CUDALIB_CUH
