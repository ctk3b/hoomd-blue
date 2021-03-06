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

// Maintainer: jglaser

/*! \file SnapshotSystemData.cc
    \brief Implements SnapshotSystemData related functions
 */

#include "SnapshotSystemData.h"
#include <boost/python.hpp>

using namespace boost::python;

template <class Real>
void SnapshotSystemData<Real>::replicate(unsigned int nx, unsigned int ny, unsigned int nz)
    {
    assert(nx > 0);
    assert(ny > 0);
    assert(nz > 0);

    // Update global box
    BoxDim old_box = global_box;
    Scalar3 L = global_box.getL();
    L.x *= (Scalar) nx;
    L.y *= (Scalar) ny;
    L.z *= (Scalar) nz;
    global_box.setL(L);

    unsigned int old_n = particle_data.size;
    unsigned int n = nx * ny *nz;

    // replicate snapshots
    if (has_particle_data)
        particle_data.replicate(nx, ny, nz, old_box, global_box);
    if (has_bond_data)
        bond_data.replicate(n,old_n);
    if (has_angle_data)
        angle_data.replicate(n,old_n);
    if (has_dihedral_data)
        dihedral_data.replicate(n,old_n);
    if (has_improper_data)
        improper_data.replicate(n,old_n);
    // replication of rigid data is currently pointless,
    // as RigidData cannot be re-initialized with a different number of rigid bodies
    if (has_rigid_data)
        rigid_data.replicate(n);
    }

template <class Real>
void SnapshotSystemData<Real>::broadcast(boost::shared_ptr<ExecutionConfiguration> exec_conf)
    {
    #ifdef ENABLE_MPI
    if (exec_conf->getNRanks() > 1)
        {
        bcast(global_box, 0, exec_conf->getMPICommunicator());
        }
    #endif
    }

// instantiate both float and double snapshots
template class SnapshotSystemData<float>;
template class SnapshotSystemData<double>;

void export_SnapshotSystemData()
    {
    class_<SnapshotSystemData<float>, boost::shared_ptr< SnapshotSystemData<float> > >("SnapshotSystemData_float")
    .def(init<>())
    .def_readwrite("_dimensions", &SnapshotSystemData<float>::dimensions)
    .def_readwrite("_global_box", &SnapshotSystemData<float>::global_box)
    .def_readwrite("particles", &SnapshotSystemData<float>::particle_data)
    .def_readwrite("bonds", &SnapshotSystemData<float>::bond_data)
    .def_readwrite("angles", &SnapshotSystemData<float>::angle_data)
    .def_readwrite("dihedrals", &SnapshotSystemData<float>::dihedral_data)
    .def_readwrite("impropers", &SnapshotSystemData<float>::improper_data)
    .def_readwrite("bodies", &SnapshotSystemData<float>::rigid_data)
    .def("replicate", &SnapshotSystemData<float>::replicate)
    .def("_broadcast", &SnapshotSystemData<float>::broadcast)
    ;

    implicitly_convertible<boost::shared_ptr< SnapshotSystemData<float> >, boost::shared_ptr< const SnapshotSystemData<float> > >();

    class_<SnapshotSystemData<double>, boost::shared_ptr< SnapshotSystemData<double> > >("SnapshotSystemData_double")
    .def(init<>())
    .def_readwrite("_dimensions", &SnapshotSystemData<double>::dimensions)
    .def_readwrite("_global_box", &SnapshotSystemData<double>::global_box)
    .def_readwrite("particles", &SnapshotSystemData<double>::particle_data)
    .def_readwrite("bonds", &SnapshotSystemData<double>::bond_data)
    .def_readwrite("angles", &SnapshotSystemData<double>::angle_data)
    .def_readwrite("dihedrals", &SnapshotSystemData<double>::dihedral_data)
    .def_readwrite("impropers", &SnapshotSystemData<double>::improper_data)
    .def_readwrite("bodies", &SnapshotSystemData<double>::rigid_data)
    .def("replicate", &SnapshotSystemData<double>::replicate)
    .def("_broadcast", &SnapshotSystemData<double>::broadcast)
    ;

    implicitly_convertible<boost::shared_ptr< SnapshotSystemData<double> >, boost::shared_ptr< const SnapshotSystemData<double> > >();
    }
