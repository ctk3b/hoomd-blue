/*
Highly Optimized Object-oriented Many-particle Dynamics -- Blue Edition
(HOOMD-blue) Open Source Software License Copyright 2009-2015 The Regents of
the University of Michigan All rights reserved.

HOOMD-blue may contain modifications ("Contributions") provided, and to which
copyright is held, by various Contributors who have granted The Regents of the
University of Michigan the right to modify and/or distribute such Contributions.

You may redistribute, use, and create derivate works of HOOMD-blue, in source
and binary forms, provided you abide by the following conditions:

* Redistributions of source code must retain the above copyright notice, this
list of conditions, and the following disclaimer both in the code and
prominently in any materials provided with the distribution.

* Redistributions in binary form must reproduce the above copyright notice, this
list of conditions, and the following disclaimer in the documentation and/or
other materials provided with the distribution.

* All publications and presentations based on HOOMD-blue, including any reports
or published results obtained, in whole or in part, with HOOMD-blue, will
acknowledge its use according to the terms posted at the time of submission on:
http://codeblue.umich.edu/hoomd-blue/citations.html

* Any electronic documents citing HOOMD-Blue will link to the HOOMD-Blue website:
http://codeblue.umich.edu/hoomd-blue/

* Apart from the above required attributions, neither the name of the copyright
holder nor the names of HOOMD-blue's contributors may be used to endorse or
promote products derived from this software without specific prior written
permission.

Disclaimer

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND/OR ANY
WARRANTIES THAT THIS SOFTWARE IS FREE OF INFRINGEMENT ARE DISCLAIMED.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// Maintainer: joaander / Everyone is free to add additional potentials

/*! \file AllDriverPotentialPairGPU.cuh
    \brief Declares driver functions for computing all types of pair forces on the GPU
*/

#ifndef __ALL_DRIVER_POTENTIAL_PAIR_GPU_CUH__
#define __ALL_DRIVER_POTENTIAL_PAIR_GPU_CUH__

#include "PotentialPairGPU.cuh"
#include "PotentialPairDPDThermoGPU.cuh"
#include "EvaluatorPairDPDThermo.h"
#include "EvaluatorPairDPDLJThermo.h"

//! Compute lj pair forces on the GPU with PairEvaluatorLJ
cudaError_t gpu_compute_ljtemp_forces(const pair_args_t& pair_args,
                                      const Scalar2 *d_params);

//! Compute gauss pair forces on the GPU with PairEvaluatorGauss
cudaError_t gpu_compute_gauss_forces(const pair_args_t& pair_args,
                                     const Scalar2 *d_params);

//! Compute slj pair forces on the GPU with PairEvaluatorGauss
cudaError_t gpu_compute_slj_forces(const pair_args_t& pair_args,
                                   const Scalar2 *d_params);

//! Compute yukawa pair forces on the GPU with PairEvaluatorGauss
cudaError_t gpu_compute_yukawa_forces(const pair_args_t& pair_args,
                                      const Scalar2 *d_params);

//! Compute morse pair forces on the GPU with PairEvaluatorMorse
cudaError_t gpu_compute_morse_forces(const pair_args_t& pair_args,
                                      const Scalar4 *d_params);

//! Compute dpd thermostat on GPU with PairEvaluatorDPDThermo
cudaError_t gpu_compute_dpdthermodpd_forces(const dpd_pair_args_t& args,
                                            const Scalar2 *d_params);

//! Compute dpd conservative force on GPU with PairEvaluatorDPDThermo
cudaError_t gpu_compute_dpdthermo_forces(const pair_args_t& pair_args,
                                         const Scalar2 *d_params);

//! Compute ewlad pair forces on the GPU with PairEvaluatorEwald
cudaError_t gpu_compute_ewald_forces(const pair_args_t& pair_args,
                                     const Scalar *d_params);

//! Compute moliere pair forces on the GPU with EvaluatorPairMoliere
cudaError_t gpu_compute_moliere_forces(const pair_args_t& pair_args,
                                       const Scalar2 *d_params);

//! Compute zbl pair forces on the GPU with EvaluatorPairZBL
cudaError_t gpu_compute_zbl_forces(const pair_args_t& pair_args,
                                   const Scalar2 *d_params);

//! Compute dpdlj thermostat on GPU with PairEvaluatorDPDThermo
cudaError_t gpu_compute_dpdljthermodpd_forces(const dpd_pair_args_t& args,
                                              const Scalar4 *d_params);

//! Compute dpdlj conservative force on GPU with PairEvaluatorDPDThermo
cudaError_t gpu_compute_dpdljthermo_forces(const pair_args_t& args,
                                           const Scalar4 *d_params);

//! Compute force shifted lj pair forces on the GPU with PairEvaluatorForceShiftedLJ
cudaError_t gpu_compute_force_shifted_lj_forces(const pair_args_t & args,
                                                const Scalar2 *d_params);

//! Compute mie potential pair forces on the GPU with PairEvaluatorMie
cudaError_t gpu_compute_mie_forces(const pair_args_t & args,
                                                const Scalar4 *d_params);

#endif
