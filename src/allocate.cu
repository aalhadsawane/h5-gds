///
/// @file allocate.cu
/// @author Yohei MIKI (The University of Tokyo)
/// @brief memory allocation
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#include <cuda.h>
#include <curand_mtgp32.h>  // defines THREAD_NUM
#include <helper_cuda.h>    // use checkCudaErrors()

#include <limits>       // std::numeric_limits
#include <type_traits>  // std::remove_reference_t

#include "allocate.cuh"
#include "common.cuh"  // NTHREADS

constexpr auto round_up(const size_t org, const size_t unit) {
  const size_t mod = org % unit;
  return ((mod == 0) ? org : (org + unit - mod));
}

#if defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU)
// GPU first touch: pages backed by the HBM GPU memory
__global__ void first_touch_gpu(type::pos *const pos, type::vel_xy *const vel_xy, type::vel_z *const vel_z, type::idx *const idx, const type::idx num) {
  cout << "GPU first touch" << endl;
  const auto i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < num) {
    pos[i] = type::pos{0.0F, 0.0F, 0.0F, 0.0F};
    vel_xy[i] = type::vel_xy{0.0F, 0.0F};
    vel_z[i] = type::vel_z{0.0F};
    idx[i] = std::numeric_limits<type::idx>::min();
  }
  cout << "GPU first touch done" << endl;
}
#endif  // defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU)

#if defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
// CPU first touch: pages backed by the CPU memory
void first_touch_cpu(type::pos *const pos, type::vel_xy *const vel_xy, type::vel_z *const vel_z, type::idx *const idx, const type::idx num) {
  for (type::idx i = 0; i < num; i++) {
    pos[i] = type::pos{0.0F, 0.0F, 0.0F, 0.0F};
    vel_xy[i] = type::vel_xy{0.0F, 0.0F};
    vel_z[i] = type::vel_z{0.0F};
    idx[i] = std::numeric_limits<type::idx>::min();
  }
}
#endif  // defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)

void allocate_particles(type::pos **pos, type::vel_xy **vel_xy, type::vel_z **vel_z, type::idx **idx, const type::idx num) noexcept(false) {
  auto size = round_up(num, NTHREADS);
  size = round_up(size, THREAD_NUM);  // for Mersenne Twister

#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
  // Standard GPU allocation with cudaMalloc
  checkCudaErrors(cudaMalloc((void **)pos, size * sizeof(std::remove_reference_t<decltype(**pos)>)));
  checkCudaErrors(cudaMalloc((void **)vel_xy, size * sizeof(std::remove_reference_t<decltype(**vel_xy)>)));
  checkCudaErrors(cudaMalloc((void **)vel_z, size * sizeof(std::remove_reference_t<decltype(**vel_z)>)));
  checkCudaErrors(cudaMalloc((void **)idx, size * sizeof(std::remove_reference_t<decltype(**idx)>)));

  // zero-clear arrays (for safety of massless particles)
  checkCudaErrors(cudaMemset(*pos, 0.0F, size * sizeof(std::remove_reference_t<decltype(**pos)>)));
  checkCudaErrors(cudaMemset(*vel_xy, 0.0F, size * sizeof(std::remove_reference_t<decltype(**vel_xy)>)));
  checkCudaErrors(cudaMemset(*vel_z, 0.0F, size * sizeof(std::remove_reference_t<decltype(**vel_z)>)));
  checkCudaErrors(cudaMemset(*idx, std::numeric_limits<std::remove_reference_t<decltype(**idx)>>::min(), size * sizeof(std::remove_reference_t<decltype(**idx)>)));
#else
  // Host malloc for unified memory (Grace Hopper)
  *pos = (type::pos *)malloc(size * sizeof(std::remove_reference_t<decltype(**pos)>));
  *vel_xy = (type::vel_xy *)malloc(size * sizeof(std::remove_reference_t<decltype(**vel_xy)>));
  *vel_z = (type::vel_z *)malloc(size * sizeof(std::remove_reference_t<decltype(**vel_z)>));
  *idx = (type::idx *)malloc(size * sizeof(std::remove_reference_t<decltype(**idx)>));

#if defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU)
  // GPU first touch: trigger page allocation on GPU
  std::cout << "GPU First touch kernel running" << std::endl;
  first_touch_gpu<<<(size + NTHREADS - 1) / NTHREADS, NTHREADS>>>(*pos, *vel_xy, *vel_z, *idx, size);
  checkCudaErrors(cudaDeviceSynchronize());
  std::cout << "GPU First touch kernel done" << std::endl;
#elif defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
  // CPU first touch: trigger page allocation on CPU
  std::cout << "CPU First touch kernel running" << std::endl;
  first_touch_cpu(*pos, *vel_xy, *vel_z, *idx, size);
  std::cout << "CPU First touch kernel done" << std::endl;
#endif
#endif
}

void release_particles(type::pos *pos, type::vel_xy *vel_xy, type::vel_z *vel_z, type::idx *idx) noexcept(false) {
#if !defined(HOST_MALLOC_AND_FIRST_TOUCH_GPU) && !defined(HOST_MALLOC_AND_FIRST_TOUCH_CPU)
  // Standard GPU deallocation
  checkCudaErrors(cudaFree(pos));
  checkCudaErrors(cudaFree(vel_xy));
  checkCudaErrors(cudaFree(vel_z));
  checkCudaErrors(cudaFree(idx));
#else
  // Host deallocation (both GPU and CPU first-touch modes use malloc)
  free(pos);
  free(vel_xy);
  free(vel_z);
  free(idx);
#endif
}
