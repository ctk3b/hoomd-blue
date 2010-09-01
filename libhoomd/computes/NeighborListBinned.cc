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

#include "NeighborListBinned.h"

#include <boost/python.hpp>
using namespace boost::python;

NeighborListBinned::NeighborListBinned(boost::shared_ptr<SystemDefinition> sysdef,
                                       Scalar r_cut,
                                       Scalar r_buff,
                                       boost::shared_ptr<CellList> cl)
    : NeighborList(sysdef, r_cut, r_buff), m_cl(cl)
    {
    // create a default cell list if one was not specified
    if (!m_cl)
        m_cl = boost::shared_ptr<CellList>(new CellList(sysdef));
    
    m_cl->setNominalWidth(r_cut + r_buff);
    m_cl->setRadius(1);
    m_cl->setComputeTDB(false);
    m_cl->setFlagIndex();
    }

NeighborListBinned::~NeighborListBinned()
    {
    }

void NeighborListBinned::setRCut(Scalar r_cut, Scalar r_buff)
    {
    NeighborList::setRCut(r_cut, r_buff);
    
    m_cl->setNominalWidth(r_cut + r_buff);
    }

void NeighborListBinned::buildNlist(unsigned int timestep)
    {
    m_cl->compute(timestep);
    
    // check that at least 3x3x3 cells are computed
    uint3 dim = m_cl->getDim();
    if (dim.x < 3 || dim.y < 3 || dim.z < 3)
        {
        cerr << endl << "***Error! NeighborListGPUBinned doesn't work on boxes where r_cut+r_buff is greater than 1/3 any box dimension" << endl << endl;
        throw runtime_error("Error computing neighbor list");
        }

    if (m_prof)
        m_prof->push(exec_conf, "compute");

    // precompute scale factor
    Scalar3 width = m_cl->getWidth();
    Scalar3 scale = make_scalar3(Scalar(1.0) / width.x,
                                 Scalar(1.0) / width.y,
                                 Scalar(1.0) / width.z);
    
    // acquire the particle data and box dimension
    const ParticleDataArraysConst& arrays = m_pdata->acquireReadOnly();
    const BoxDim& box = m_pdata->getBox();

    // start by creating a temporary copy of r_cut sqaured
    Scalar rmaxsq = (m_r_cut + m_r_buff) * (m_r_cut + m_r_buff);

    // precalculate box lenghts
    Scalar Lx = box.xhi - box.xlo;
    Scalar Ly = box.yhi - box.ylo;
    Scalar Lz = box.zhi - box.zlo;
    
    // access the cell list data arrays
    ArrayHandle<unsigned int> h_cell_size(m_cl->getCellSizeArray(), access_location::host, access_mode::read);
    ArrayHandle<Scalar4> h_cell_xyzf(m_cl->getXYZFArray(), access_location::host, access_mode::read);
    ArrayHandle<unsigned int> h_cell_adj(m_cl->getCellAdjArray(), access_location::host, access_mode::read);

    ArrayHandle<unsigned int> h_nlist(m_nlist, access_location::host, access_mode::overwrite);
    ArrayHandle<unsigned int> h_n_neigh(m_n_neigh, access_location::host, access_mode::overwrite);
    ArrayHandle<unsigned int> h_conditions(m_conditions, access_location::host, access_mode::readwrite);
    
    // access indexers
    Index3D ci = m_cl->getCellIndexer();
    Index2D cli = m_cl->getCellListIndexer();
    Index2D cadji = m_cl->getCellAdjIndexer();

    // for each particle
#pragma omp parallel for schedule(dynamic, 100)
    for (int i = 0; i < (int)arrays.nparticles; i++)
        {
        unsigned int cur_n_neigh = 0;
        
        Scalar3 my_pos = make_scalar3(arrays.x[i], arrays.y[i], arrays.z[i]);
        
        // find the bin each particle belongs in
        unsigned int ib = (unsigned int)((my_pos.x-box.xlo)*scale.x);
        unsigned int jb = (unsigned int)((my_pos.y-box.ylo)*scale.y);
        unsigned int kb = (unsigned int)((my_pos.z-box.zlo)*scale.z);
        
        // need to handle the case where the particle is exactly at the box hi
        if (ib == dim.x)
            ib = 0;
        if (jb == dim.y)
            jb = 0;
        if (kb == dim.z)
            kb = 0;
            
        // identify the bin
        unsigned int my_cell = ci(ib,jb,kb);
        
        // loop through all neighboring bins
        for (unsigned int cur_adj = 0; cur_adj < cadji.getW(); cur_adj++)
            {
            unsigned int neigh_cell = h_cell_adj.data[cadji(cur_adj, my_cell)];
                
            // check against all the particles in that neighboring bin to see if it is a neighbor
            unsigned int size = h_cell_size.data[neigh_cell];
            for (unsigned int cur_offset = 0; cur_offset < size; cur_offset++)
                {
                Scalar4 cur_xyzf = h_cell_xyzf.data[cli(cur_offset, neigh_cell)];
                
                Scalar3 neigh_pos = make_scalar3(cur_xyzf.x, cur_xyzf.y, cur_xyzf.z);
                unsigned int cur_neigh = __scalar_as_int(cur_xyzf.w);
                
                Scalar dx = my_pos.x - neigh_pos.x;
                if (dx >= Lx/2.0)
                    dx -= Lx;
                if (dx <= -Lx/2.0)
                    dx += Lx;
                    
                Scalar dy = my_pos.y - neigh_pos.y;
                if (dy >= Ly/2.0)
                    dy -= Ly;
                if (dy <= -Ly/2.0)
                    dy += Ly;
                    
                Scalar dz = my_pos.z - neigh_pos.z;
                if (dz >= Lz/2.0)
                    dz -= Lz;
                if (dz <= -Lz/2.0)
                    dz += Lz;
                    
                float dr_sq = dx*dx + dy*dy + dz*dz;
                
                if (dr_sq <= rmaxsq && i != (int)cur_neigh)
                    {
                    if (m_storage_mode == full || i < (int)cur_neigh)
                        {
                        if (cur_n_neigh < m_nlist_indexer.getH())
                            h_nlist.data[m_nlist_indexer(i, cur_n_neigh)] = cur_neigh;
                        else
                            h_conditions.data[0] = max(h_conditions.data[0], cur_n_neigh+1);
                        
                        cur_n_neigh++;
                        }
                    }
                }
            }
        
        h_n_neigh.data[i] = cur_n_neigh;
        }
    
    m_pdata->release();
    
    if (m_prof)
        m_prof->pop(exec_conf);
    }

void export_NeighborListBinned()
    {
    class_<NeighborListBinned, boost::shared_ptr<NeighborListBinned>, bases<NeighborList>, boost::noncopyable >
                     ("NeighborListBinned", init< boost::shared_ptr<SystemDefinition>, Scalar, Scalar, boost::shared_ptr<CellList> >())
                     ;
    }

