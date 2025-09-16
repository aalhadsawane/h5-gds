///
/// @file generate.cuh
/// @author Yohei MIKI (The University of Tokyo)
/// @brief generate initial-condition on GPU
///
/// @copyright Copyright (c) 2023 Information Technology Center, The University of Tokyo
///
/// The MIT License is applied to this software, see LICENSE.txt
///
#ifndef GENERATE_CUH
#define GENERATE_CUH

#include "common.cuh"

///
/// @brief Set the uniform sphere
///
/// @param[in] num number of N-body particles
/// @param[out] pos position and mass of N-body particles
/// @param[out] vxy velocity of N-body particles (x and y)
/// @param[out] vz velocity of N-body particles (z)
/// @param[out] id particle ID
/// @param[in] Mtot total mass of the sphere
/// @param[in] rad radius of the sphere
/// @param[in] virial Virial ratio of the system
/// @param[in] newton gravitational constant
///
void set_uniform_sphere(type::idx num, type::pos *pos, type::vel_xy *vel_xy, type::vel_z *vel_z, type::idx *id, type::vel_z Mtot, decltype(Mtot) rad, decltype(Mtot) virial, decltype(Mtot) newton);

#endif  // GENERATE_CUH
