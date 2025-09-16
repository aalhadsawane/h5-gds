///
/// @file allocate.cuh
/// @author Yohei MIKI (The University of Tokyo)
/// @brief memory allocation
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE
///
#ifndef ALLOCATE_CUH
#define ALLOCATE_CUH

#include "common.cuh"

///
/// @brief allocate memory on GPU
///
/// @param[out] pos particle position
/// @param[out] vel_xy particle velocity (x and y)
/// @param[out] vel_z particle velocity (z)
/// @param[out] idx particle ID
/// @param[in] num number of particles
///
void allocate_particles(type::pos **pos, type::vel_xy **vel_xy, type::vel_z **vel_z, type::idx **idx, type::idx num);

///
/// @brief release memory on GPU
///
/// @param[in] pos particle position
/// @param[in] vel_xy particle velocity (x and y)
/// @param[in] vel_z particle velocity (z)
/// @param[in] idx particle ID
///
void release_particles(type::pos *pos, type::vel_xy *vel_xy, type::vel_z *vel_z, type::idx *idx);

#endif  // ALLOCATE_CUH
