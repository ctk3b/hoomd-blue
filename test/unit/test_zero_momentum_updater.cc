/*
Highly Optimized Object-oriented Many-particle Dynamics -- Blue Edition
(HOOMD-blue) Open Source Software License Copyright 2008, 2009 Ames Laboratory
Iowa State University and The Regents of the University of Michigan All rights
reserved.

HOOMD-blue may contain modifications ("Contributions") provided, and to which
copyright is held, by various Contributors who have granted The Regents of the
University of Michigan the right to modify and/or distribute such Contributions.

Redistribution and use of HOOMD-blue, in source and binary forms, with or
without modification, are permitted, provided that the following conditions are
met:

* Redistributions of source code must retain the above copyright notice, this
list of conditions, and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this
list of conditions, and the following disclaimer in the documentation and/or
other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of HOOMD-blue's
contributors may be used to endorse or promote products derived from this
software without specific prior written permission.

Disclaimer

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND CONTRIBUTORS ``AS IS''
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND/OR
ANY WARRANTIES THAT THIS SOFTWARE IS FREE OF INFRINGEMENT ARE DISCLAIMED.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// $Id$
// $URL$
// Maintainer: joaander

#ifdef WIN32
#pragma warning( push )
#pragma warning( disable : 4103 4244 )
#endif

#include <iostream>

#include <boost/shared_ptr.hpp>

#include "ZeroMomentumUpdater.h"

#include <math.h>

using namespace std;
using namespace boost;

//! label the boost test module
#define BOOST_TEST_MODULE ZeroMomentumUpdaterTests
#include "boost_utf_configure.h"

/*! \file zero_momentum_updater_test.cc
    \brief Unit tests for the ZeroMomentumUpdater class
    \ingroup unit_tests
*/

//! boost test case to verify proper operation of ZeroMomentumUpdater
BOOST_AUTO_TEST_CASE( ZeroMomentumUpdater_basic )
    {
#ifdef ENABLE_CUDA
    g_gpu_error_checking = true;
#endif
    
    // create a simple particle data to test with
    shared_ptr<SystemDefinition> sysdef(new SystemDefinition(2, BoxDim(1000.0), 4));
    shared_ptr<ParticleData> pdata = sysdef->getParticleData();
    
    ParticleDataArrays arrays = pdata->acquireReadWrite();
    arrays.x[0] = arrays.y[0] = arrays.z[0] = 0.0;
    arrays.vx[0] = 1.0; arrays.vy[0] = 2.0; arrays.vz[0] = 3.0;
    arrays.x[1] = arrays.y[1] = arrays.z[1] = 1.0;
    arrays.vx[1] = 4.0; arrays.vy[1] = 5.0; arrays.vz[1] = 6.0;
    pdata->release();
    
    // construct the updater and make sure everything is set properly
    shared_ptr<ZeroMomentumUpdater> zerop(new ZeroMomentumUpdater(sysdef));
    
    // run the updater and check the new temperature
    zerop->update(0);
    
    // check that the momentum is now zero
    arrays = pdata->acquireReadWrite();
    
    // temp variables for holding the sums
    Scalar sum_px = 0.0;
    Scalar sum_py = 0.0;
    Scalar sum_pz = 0.0;
    
    // note: assuming mass == 1 for now
    for (unsigned int i = 0; i < arrays.nparticles; i++)
        {
        sum_px += arrays.vx[i];
        sum_py += arrays.vy[i];
        sum_pz += arrays.vz[i];
        }
    pdata->release();
    
    // calculate the average
    Scalar avg_px = sum_px / Scalar(arrays.nparticles);
    Scalar avg_py = sum_py / Scalar(arrays.nparticles);
    Scalar avg_pz = sum_pz / Scalar(arrays.nparticles);
    
    MY_BOOST_CHECK_SMALL(avg_px, tol_small);
    MY_BOOST_CHECK_SMALL(avg_py, tol_small);
    MY_BOOST_CHECK_SMALL(avg_pz, tol_small);
    }

#ifdef WIN32
#pragma warning( pop )
#endif
