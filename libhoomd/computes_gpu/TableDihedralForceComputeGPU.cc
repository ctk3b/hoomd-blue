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

// Maintainer: joaander

#include "TableDihedralForceComputeGPU.h"

#include <boost/python.hpp>
using namespace boost::python;
#include <boost/bind.hpp>
using namespace boost;

#include <stdexcept>

/*! \file TableDihedralForceComputeGPU.cc
    \brief Defines the TableDihedralForceComputeGPU class
*/

using namespace std;

/*! \param sysdef System to compute forces on
    \param table_width Width the tables will be in memory
    \param log_suffix Name given to this instance of the table potential
*/
TableDihedralForceComputeGPU::TableDihedralForceComputeGPU(boost::shared_ptr<SystemDefinition> sysdef,
                                     unsigned int table_width,
                                     const std::string& log_suffix)
    : TableDihedralForceCompute(sysdef, table_width, log_suffix)
    {
    // can't run on the GPU if there aren't any GPUs in the execution configuration
    if (!m_exec_conf->isCUDAEnabled())
        {
        m_exec_conf->msg->error() << "Creating a BondTableForceComputeGPU with no GPU in the execution configuration" << endl;
        throw std::runtime_error("Error initializing BondTableForceComputeGPU");
        }

     // allocate flags storage on the GPU
    GPUArray<unsigned int> flags(1, this->exec_conf);
    m_flags.swap(flags);

    m_tuner.reset(new Autotuner(32, 1024, 32, 5, 100000, "table_dihedral", this->m_exec_conf));
    }

/*! \post The table based forces are computed for the given timestep.

\param timestep specifies the current time step of the simulation

Calls gpu_compute_bondtable_forces to do the leg work
*/
void TableDihedralForceComputeGPU::computeForces(unsigned int timestep)
    {

    // start the profile
    if (m_prof) m_prof->push(m_exec_conf, "Dihedral Table");

    // access the particle data
    ArrayHandle<Scalar4> d_pos(m_pdata->getPositions(), access_location::device, access_mode::read);
    BoxDim box = m_pdata->getBox();

    // access the table data
    ArrayHandle<Scalar2> d_tables(m_tables, access_location::device, access_mode::read);

    ArrayHandle<Scalar4> d_force(m_force,access_location::device,access_mode::overwrite);
    ArrayHandle<Scalar> d_virial(m_virial,access_location::device,access_mode::overwrite);

        {
        // Access the dihedral data for reading
        ArrayHandle<group_storage<4> > d_gpu_dihedrallist(m_dihedral_data->getGPUTable(), access_location::device,access_mode::read);
        ArrayHandle<unsigned int> d_gpu_n_dihedrals(m_dihedral_data->getNGroupsArray(), access_location::device, access_mode::read);
        ArrayHandle<unsigned int> d_dihedrals_ABCD(m_dihedral_data->getGPUPosTable(), access_location::device, access_mode::read);


        // run the kernel on all GPUs in parallel
        m_tuner->begin();
        gpu_compute_table_dihedral_forces(d_force.data,
                             d_virial.data,
                             m_virial.getPitch(),
                             m_pdata->getN(),
                             d_pos.data,
                             box,
                             d_gpu_dihedrallist.data,
                             d_dihedrals_ABCD.data,
                             m_dihedral_data->getGPUTableIndexer().getW(),
                             d_gpu_n_dihedrals.data,
                             d_tables.data,
                             m_table_width,
                             m_table_value,
                             m_tuner->getParam(),
                             m_exec_conf->getComputeCapability());
        }


    if(m_exec_conf->isCUDAErrorCheckingEnabled())
        {
        CHECK_CUDA_ERROR();
        }

    m_tuner->end();

    if (m_prof) m_prof->pop(m_exec_conf);
    }

void export_TableDihedralForceComputeGPU()
    {
    class_<TableDihedralForceComputeGPU, boost::shared_ptr<TableDihedralForceComputeGPU>, bases<TableDihedralForceCompute>, boost::noncopyable >
    ("TableDihedralForceComputeGPU",
     init< boost::shared_ptr<SystemDefinition>,
     unsigned int,
     const std::string& >())
    ;
    }
