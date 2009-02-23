/*
Highly Optimized Object-Oriented Molecular Dynamics (HOOMD) Open
Source Software License
Copyright (c) 2008 Ames Laboratory Iowa State University
All rights reserved.

Redistribution and use of HOOMD, in source and binary forms, with or
without modification, are permitted, provided that the following
conditions are met:

* Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names HOOMD's
contributors may be used to endorse or promote products derived from this
software without specific prior written permission.

Disclaimer

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER AND
CONTRIBUTORS ``AS IS''  AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS  BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
THE POSSIBILITY OF SUCH DAMAGE.
*/

// $Id$
// $URL$

/*! \file RigidData.cc
 	\brief Defines RigidData and related classes.
*/

#include "RigidData.h"
#include <cassert>

using namespace boost;
using namespace std;

#define TOLERANCE 1.0e-6
#define EPSILON 1.0e-7
#define MAXJACOBI 50

/*! \param particle_data ParticleData this use in initializing this RigidData

	\pre \a particle_data has been completeley initialized with all arrays filled out
	\post All data members in RigidData are completely initialized from the given info in \a particle_data
*/
RigidData::RigidData(boost::shared_ptr<ParticleData> particle_data)
	: m_pdata(particle_data)
	{
	// read the body array from particle_data and extract some information
	
	// initialization should set this to true if no rigid bodies were defined in the particle data
	bool no_rigid_bodies_defined = false;
	if (no_rigid_bodies_defined)
		{
		// stop now and leave this class as an uninitialized shell
		m_n_bodies = 0;
		return;
		}
	
	// initialize the number of bodies
	m_n_bodies = 10;		// 10 is placeholder value in template
	unsigned int nmax = 5;	// 5 is placeholder value in template
	
	// allocate memory via construct & swap to avoid the temporaries produced by the = operator
	GPUArray<Scalar4> moment_inertia(m_n_bodies, m_pdata->getExecConf());
	GPUArray<unsigned int> body_size(m_n_bodies, m_pdata->getExecConf());
	GPUArray<unsigned int> particle_tags(nmax, m_n_bodies, m_pdata->getExecConf());
	GPUArray<unsigned int> particle_indices(nmax, m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> particle_pos(nmax, m_n_bodies, m_pdata->getExecConf());

	GPUArray<Scalar4> com(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> vel(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> orientation(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> angmom(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> angvel(m_n_bodies, m_pdata->getExecConf());
	
	// swap the allocated GPUArray with the member variables
	m_moment_inertia.swap(moment_inertia);
	m_body_size.swap(body_size);
	m_particle_tags.swap(particle_tags);
	m_particle_indices.swap(particle_indices);
	m_particle_pos.swap(particle_pos);
		
	m_com.swap(com);
	m_vel.swap(vel);
	m_orientation.swap(orientation);
	m_angmom.swap(angmom);
	m_angvel.swap(angvel);
	
	// initialize the data
	initializeData();
	
	// initialize the index cace
	recalcIndices();
	
	// connect the sort signal
	m_sort_connection = m_pdata->connectParticleSort(bind(&RigidData::recalcIndices, this));	
	}

RigidData::~RigidData()
	{
	m_sort_connection.disconnect();
	}
		

/*!	\pre m_body_size has been filled with values
	\pre m_particle_tags hass been filled with values
	\pre m_particle_indices has been allocated
	\post m_particle_indices is updated to match the current sorting of the particle data
*/
void RigidData::recalcIndices()
	{
	// sanity check
	assert(m_pdata);
	assert(!m_particle_tags.isNull());
	assert(!m_particle_indices.isNull());
	assert(m_n_bodies <= m_particle_tags.getPitch());
	assert(m_n_bodies <= m_particle_indices.getPitch());
	assert(m_n_bodies == m_body_size.getNumElements());
	
	// get the particle data
	const ParticleDataArraysConst &arrays = m_pdata->acquireReadOnly();
	
	// get all the rigid data we need
	ArrayHandle<unsigned int> tags(m_particle_tags, access_location::host, access_mode::read);
	unsigned int tags_pitch = m_particle_tags.getPitch();
	
	ArrayHandle<unsigned int> indices(m_particle_indices, access_location::host, access_mode::readwrite);
	unsigned int indices_pitch = m_particle_indices.getPitch();
	
	ArrayHandle<unsigned int> body_size(m_body_size, access_location::host, access_mode::read);
	
	// for each body
	for (unsigned int body = 0; body < m_n_bodies; body++)
		{
		// for each particle in this body
		unsigned int len = body_size.data[body];
		assert(len <= m_particle_tags.getHeight() && len <= m_particle_indices.getHeight());
		for (unsigned int i = 0; i < len; i++)
			{
			// translate the tag to the current index
			unsigned int tag = tags.data[body*tags_pitch + i];
			unsigned int pidx = arrays.rtag[tag];
			indices.data[body*indices_pitch + i] = pidx;
			}
		}
		
	m_pdata->release();
	}
	
/*! \pre all data members have been allocated
	\post all data members are initialized with data from the particle data
*/
void RigidData::initializeData()
	{
	
	// get the particle data
	const ParticleDataArraysConst &arrays = m_pdata->acquireReadOnly();	
	
	// determine the number of rigid bodies
	unsigned int maxbody = arrays.body[0];
	for (unsigned int j = 0; j < arrays.nparticles; j++)
		{
		if (arrays.body[j] != NO_BODY)
			{
			if (maxbody < arrays.body[j]) 
				maxbody = arrays.body[j];
			}
		}
	
	m_n_bodies = maxbody + 1;	// arrays.body[j] is numbered from 0
	if (m_n_bodies <= 0) return;

	// allocate nbodies-size arrays
	GPUArray<Scalar> body_mass(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> moment_inertia(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> orientation(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> ex_space(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> ey_space(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> ez_space(m_n_bodies, m_pdata->getExecConf());
	GPUArray<unsigned int> body_imagex(m_n_bodies, m_pdata->getExecConf());
	GPUArray<unsigned int> body_imagey(m_n_bodies, m_pdata->getExecConf());
	GPUArray<unsigned int> body_imagez(m_n_bodies, m_pdata->getExecConf());
		
	GPUArray<Scalar4> com(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> vel(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> angmom(m_n_bodies, m_pdata->getExecConf());
	GPUArray<Scalar4> angvel(m_n_bodies, m_pdata->getExecConf());
		
	// determine the largest size of rigid bodies (nmax)
	GPUArray<unsigned int> body_size(m_n_bodies, m_pdata->getExecConf());
	ArrayHandle<unsigned int> body_size_handle(body_size, access_location::host, access_mode::readwrite);
	for (unsigned int body = 0; body < m_n_bodies; body++)
		body_size_handle.data[body] = 0;
		
	for (unsigned int j = 0; j < arrays.nparticles; j++)
		{
		unsigned int body = arrays.body[j];
		if (body != NO_BODY)
			body_size_handle.data[body]++;
		}	
	
	unsigned int nmax = 0;
	for (unsigned int body = 0; body < m_n_bodies; body++)
		if (nmax < body_size_handle.data[body])
			nmax = body_size_handle.data[body];	
	
	// determine body_mass, inertia tensor, com and vel	
	GPUArray<Scalar> inertia(6, m_n_bodies, m_pdata->getExecConf()); // the inertia tensor is symmetric, therefore we only need to store 6 elements
	ArrayHandle<Scalar> inertia_handle(inertia, access_location::host, access_mode::readwrite);
		
	ArrayHandle<Scalar> body_mass_handle(body_mass, access_location::host, access_mode::readwrite);
	ArrayHandle<Scalar4> moment_inertia_handle(moment_inertia, access_location::host, access_mode::readwrite);
	ArrayHandle<Scalar4> orientation_handle(orientation, access_location::host, access_mode::readwrite);
	ArrayHandle<Scalar4> ex_space_handle(ex_space, access_location::host, access_mode::readwrite);
	ArrayHandle<Scalar4> ey_space_handle(ey_space, access_location::host, access_mode::readwrite);
	ArrayHandle<Scalar4> ez_space_handle(ez_space, access_location::host, access_mode::readwrite);
	ArrayHandle<unsigned int> body_imagex_handle(body_imagex, access_location::host, access_mode::readwrite);
	ArrayHandle<unsigned int> body_imagey_handle(body_imagey, access_location::host, access_mode::readwrite);
	ArrayHandle<unsigned int> body_imagez_handle(body_imagez, access_location::host, access_mode::readwrite);
	ArrayHandle<Scalar4> com_handle(com, access_location::host, access_mode::readwrite);
	ArrayHandle<Scalar4> vel_handle(vel, access_location::host, access_mode::readwrite);
	
	for (unsigned int body = 0; body < m_n_bodies; body++)
	{
		body_mass_handle.data[body] = 0.0;
		com_handle.data[body].x = 0.0;
		com_handle.data[body].y = 0.0;
		com_handle.data[body].z = 0.0;
		vel_handle.data[body].x = 0.0;
		vel_handle.data[body].y = 0.0;
		vel_handle.data[body].z = 0.0;
		
		inertia_handle.data[6 * body] = 0.0;
		inertia_handle.data[6 * body + 1] = 0.0;
		inertia_handle.data[6 * body + 2] = 0.0;
		inertia_handle.data[6 * body + 3] = 0.0;
		inertia_handle.data[6 * body + 4] = 0.0;
		inertia_handle.data[6 * body + 5] = 0.0;
	}
		
	for (unsigned int j = 0; j < arrays.nparticles; j++)
	{
		if (arrays.body[j] == NO_BODY) continue;
		
		unsigned int body = arrays.body[j];
		Scalar mass_one = arrays.mass[j];
		body_mass_handle.data[body] += mass_one;
		
		com_handle.data[body].x += mass_one * arrays.x[j];
		com_handle.data[body].y += mass_one * arrays.y[j];
		com_handle.data[body].z += mass_one * arrays.z[j];
		
		vel_handle.data[body].x += mass_one * arrays.vx[j];
		vel_handle.data[body].y += mass_one * arrays.vy[j];
		vel_handle.data[body].z += mass_one * arrays.vz[j];
	}
	
	// com, vel and body images
	for (unsigned int body = 0; body < m_n_bodies; body++)
	{
		Scalar mass_body = body_mass_handle.data[body];
		com_handle.data[body].x /= mass_body;
		com_handle.data[body].y /= mass_body;
		com_handle.data[body].z /= mass_body;
		
		vel_handle.data[body].x /= mass_body;
		vel_handle.data[body].y /= mass_body;
		vel_handle.data[body].z /= mass_body;
		
		body_imagex_handle.data[body] = 0;
		body_imagey_handle.data[body] = 0;
		body_imagez_handle.data[body] = 0;
	}
	
	// determine the inertia tensor then diagonalize it
	for (unsigned int j = 0; j < arrays.nparticles; j++)
	{
		if (arrays.body[j] == NO_BODY) continue;
			
		unsigned int body = arrays.body[j];
		Scalar mass_one = arrays.mass[j];
			
		Scalar dx = arrays.x[j] - com_handle.data[body].x;
		Scalar dy = arrays.y[j] - com_handle.data[body].y;
		Scalar dz = arrays.z[j] - com_handle.data[body].z;
		
		inertia_handle.data[6 * body] += mass_one * (dy * dy + dz * dz);
		inertia_handle.data[6 * body + 1] += mass_one * (dz * dz + dx * dx);
		inertia_handle.data[6 * body + 2] += mass_one * (dx * dx + dy * dy);
		inertia_handle.data[6 * body + 3] -= mass_one * dx * dy;
		inertia_handle.data[6 * body + 4] -= mass_one * dy * dz;
		inertia_handle.data[6 * body + 5] -= mass_one * dx * dz;
	}
	
	// allocate temporary arrays: revision needed!
	Scalar **matrix, *evalues, **evectors;
	matrix = new Scalar*[3];
	evectors = new Scalar*[3];
	evalues = new Scalar[3];
	for (unsigned int j = 0; j < 3; j++) 
		{
		matrix[j] = new Scalar[3];
		evectors[j] = new Scalar[3];
		}
	
	for (unsigned int body = 0; body < m_n_bodies; body++)
		{
		matrix[0][0] = inertia_handle.data[6 * body];
		matrix[1][1] = inertia_handle.data[6 * body + 1];
		matrix[2][2] = inertia_handle.data[6 * body + 2];
		matrix[0][1] = matrix[1][0] = inertia_handle.data[6 * body + 3];
		matrix[1][2] = matrix[2][1] = inertia_handle.data[6 * body + 4];
		matrix[2][0] = matrix[0][2] = inertia_handle.data[6 * body + 5];
		
		int error = diagonalize(matrix, evalues, evectors);
		if (error == 0) cout << "Insufficient Jacobi iterations for diagonalization!\n";
		
		// obtain the moment inertia from eigen values
		moment_inertia_handle.data[body].x = evalues[0];
		moment_inertia_handle.data[body].y = evalues[1];
		moment_inertia_handle.data[body].z = evalues[2];
		
		// obtain the principle axes from eigen vectors
		ex_space_handle.data[body].x = evectors[0][0];
		ex_space_handle.data[body].y = evectors[1][0];
		ex_space_handle.data[body].z = evectors[2][0];
			
		ey_space_handle.data[body].x = evectors[0][1];
		ey_space_handle.data[body].y = evectors[1][1];
		ey_space_handle.data[body].z = evectors[2][1];
			
		ez_space_handle.data[body].x = evectors[0][2];
		ez_space_handle.data[body].y = evectors[1][2];
		ez_space_handle.data[body].z = evectors[2][2];
		
		// create the initial quaternion from the new body frame
		quaternionFromExyz(ex_space_handle.data[body], ey_space_handle.data[body], ez_space_handle.data[body], 
						   orientation_handle.data[body]);
		}
	
	// deallocate temporary memory
	delete [] evalues;
	
	for (unsigned int j = 0; j < 3; j++)
		{
		delete [] matrix[j];
		delete [] evectors[j];
		}
	
	delete [] evectors;
	delete [] matrix;
		
		
	// allocate nmax by m_n_bodies arrays
	GPUArray<unsigned int> particle_tags(nmax, m_n_bodies, m_pdata->getExecConf());
	ArrayHandle<unsigned int> particle_tags_handle(particle_tags, access_location::host, access_mode::readwrite); 
	GPUArray<unsigned int> particle_indices(nmax, m_n_bodies, m_pdata->getExecConf());
	ArrayHandle<unsigned int> particle_indices_handle(particle_indices, access_location::host, access_mode::readwrite); 
	GPUArray<Scalar4> particle_pos(nmax, m_n_bodies, m_pdata->getExecConf());		
	ArrayHandle<Scalar4> particle_pos_handle(particle_pos, access_location::host, access_mode::readwrite); 

	GPUArray<unsigned int> local_indices(m_n_bodies, m_pdata->getExecConf());
	ArrayHandle<unsigned int> local_indices_handle(local_indices, access_location::host, access_mode::readwrite); 
	for (unsigned int body = 0; body < m_n_bodies; body++)
			local_indices_handle.data[body] = 0;
		
	// determine the particle indices and particle tags
	for (unsigned int j = 0; j < arrays.nparticles; j++)
		{
		if (arrays.body[j] == NO_BODY) continue;
		
		// get the corresponding body
		unsigned int body = arrays.body[j];
		// get the current index in the body
		unsigned int current_localidx = local_indices_handle.data[body];
		// set the particle index to be this value
		particle_indices_handle.data[body * nmax + current_localidx] = j;
		// set the particle tag to be the tag of this particle
		particle_tags_handle.data[body * nmax + current_localidx] = arrays.tag[j];
		
		// determine the particle position in the body frame 
		// with ex_space, ey_space and ex_space vectors computed from the diagonalization
		Scalar dx = arrays.x[j] - com_handle.data[body].x;
		Scalar dy = arrays.y[j] - com_handle.data[body].y;
		Scalar dz = arrays.z[j] - com_handle.data[body].z;
		particle_pos_handle.data[body * nmax + current_localidx].x = dx * ex_space_handle.data[body].x + dy * ex_space_handle.data[body].y +
					dz * ex_space_handle.data[body].z;
		particle_pos_handle.data[body * nmax + current_localidx].y = dx * ey_space_handle.data[body].x + dy * ey_space_handle.data[body].y +
					dz * ey_space_handle.data[body].z;
		particle_pos_handle.data[body * nmax + current_localidx].z = dx * ez_space_handle.data[body].x + dy * ez_space_handle.data[body].y +
					dz * ez_space_handle.data[body].z; 
	
		// increment the current index by one
		local_indices_handle.data[body]++;
		}
	
	// swap the allocated GPUArray with the member variables
	m_body_mass.swap(body_mass);
	m_moment_inertia.swap(moment_inertia);
	m_body_size.swap(body_size);
	m_particle_tags.swap(particle_tags);
	m_particle_indices.swap(particle_indices);
	m_particle_pos.swap(particle_pos);
		
	m_orientation.swap(orientation);
	m_ex_space.swap(ex_space);
	m_ey_space.swap(ey_space);
	m_ez_space.swap(ez_space);
	m_body_imagex.swap(body_imagex);
	m_body_imagey.swap(body_imagey);
	m_body_imagez.swap(body_imagez);
		
	m_com.swap(com);
	m_vel.swap(vel);
	m_angmom.swap(angmom);
	m_angvel.swap(angvel);
	}

/*! Compute eigenvalues and eigenvectors of 3x3 real symmetric matrix based on Jacobi rotations
   adapted from Numerical Recipes jacobi() function (LAMMPS)
*/

int RigidData::diagonalize(Scalar **matrix, Scalar *evalues, Scalar **evectors)
{
	int i,j,k;
	Scalar tresh, theta, tau, t, sm, s, h, g, c, b[3], z[3];
	
	for (i = 0; i < 3; i++) 
		{
		for (j = 0; j < 3; j++) evectors[i][j] = 0.0;
		evectors[i][i] = 1.0;
		}
	
	for (i = 0; i < 3; i++) 
		{
		b[i] = evalues[i] = matrix[i][i];
		z[i] = 0.0;
		}
	
	for (int iter = 1; iter <= MAXJACOBI; iter++) 
		{
		sm = 0.0;
		for (i = 0; i < 2; i++)
			for (j = i+1; j < 3; j++)
				sm += fabs(matrix[i][j]);
		
		if (sm == 0.0) return 0;
		
		if (iter < 4) tresh = 0.2*sm/(3*3);
		else tresh = 0.0;
		
		for (i = 0; i < 2; i++) 
			{
			for (j = i+1; j < 3; j++) 
				{
				g = 100.0 * fabs(matrix[i][j]);
				if (iter > 4 && fabs(evalues[i]) + g == fabs(evalues[i])
					&& fabs(evalues[j]) + g == fabs(evalues[j]))
					matrix[i][j] = 0.0;
				else if (fabs(matrix[i][j]) > tresh)
					{
					h = evalues[j]-evalues[i];
					if (fabs(h)+g == fabs(h)) t = (matrix[i][j])/h;
					else 
						{
						theta = 0.5 * h / (matrix[i][j]);
						t = 1.0/(fabs(theta)+sqrt(1.0+theta*theta));
						if (theta < 0.0) t = -t;
						}
					
					c = 1.0/sqrt(1.0+t*t);
					s = t*c;
					tau = s/(1.0+c);
					h = t*matrix[i][j];
					z[i] -= h;
					z[j] += h;
					evalues[i] -= h;
					evalues[j] += h;
					matrix[i][j] = 0.0;
					for (k = 0; k < i; k++) rotate(matrix,k,i,k,j,s,tau);
					for (k = i+1; k < j; k++) rotate(matrix,i,k,k,j,s,tau);
					for (k = j+1; k < 3; k++) rotate(matrix,i,k,j,k,s,tau);
					for (k = 0; k < 3; k++) rotate(evectors,k,i,k,j,s,tau);
					}
				}
			}
		
		for (i = 0; i < 3; i++) 
			{
			evalues[i] = b[i] += z[i];
			z[i] = 0.0;
			}
		}
	
	return 1;
	}

/*! Perform a single Jacobi rotation
*/

void RigidData::rotate(Scalar **matrix, int i, int j, int k, int l, Scalar s, Scalar tau)
	{
	Scalar g = matrix[i][j];
	Scalar h = matrix[k][l];
	matrix[i][j] = g - s * (h + g * tau);
	matrix[k][l] = h + s * (g - h * tau);
	}

void RigidData::quaternionFromExyz(Scalar4 &ex_space, Scalar4 &ey_space, Scalar4 &ez_space, Scalar4 &quat)
	{
	
	// enforce 3 evectors as a right-handed coordinate system
	// flip 3rd evector if needed
	Scalar ez0, ez1, ez2; // Cross product of first two vectors
	ez0 = ex_space.y * ey_space.z - ex_space.z * ey_space.y;
	ez1 = ex_space.z * ey_space.x - ex_space.x * ey_space.z;
	ez2 = ex_space.x * ey_space.y - ex_space.y * ey_space.x;
	
	// then dot product with the third one
	if (ez0 * ez_space.x + ez1 * ez_space.y + ez2 * ez_space.z < 0.0) 
	{
		ez_space.x = -ez_space.x;
		ez_space.y = -ez_space.y;
		ez_space.z = -ez_space.z;
	}
	
	// squares of quaternion components
	Scalar q0sq = 0.25 * (ex_space.x + ey_space.y + ez_space.z + 1.0);
	Scalar q1sq = q0sq - 0.5 * (ey_space.y + ez_space.z);
	Scalar q2sq = q0sq - 0.5 * (ex_space.x + ez_space.z);
	Scalar q3sq = q0sq - 0.5 * (ex_space.x + ey_space.y);
	
	// some component must be greater than 1/4 since they sum to 1
	// compute other components from it
	if (q0sq >= 0.25) 
	{
		quat.x = sqrt(q0sq);
		quat.y = (ey_space.z - ez_space.y) / (4.0 * quat.x);
		quat.z = (ez_space.x - ex_space.z) / (4.0 * quat.x);
		quat.w = (ex_space.y - ey_space.x) / (4.0 * quat.x);
	} 
	else if (q1sq >= 0.25) 
	{
		quat.y = sqrt(q1sq);
		quat.x = (ey_space.z - ez_space.y) / (4.0 * quat.y);
		quat.z = (ey_space.x + ex_space.y) / (4.0 * quat.y);
		quat.w = (ex_space.z + ez_space.x) / (4.0 * quat.y);
	} 
	else if (q2sq >= 0.25) 
	{
		quat.z = sqrt(q2sq);
		quat.x = (ez_space.x - ex_space.z) / (4.0 * quat.z);
		quat.y = (ey_space.x + ex_space.y) / (4.0 * quat.z);
		quat.w = (ez_space.y + ey_space.z) / (4.0 * quat.z);
	} 
	else if (q3sq >= 0.25) 
	{
		quat.w = sqrt(q3sq);
		quat.x = (ex_space.y - ey_space.x) / (4.0 * quat.w);
		quat.y = (ez_space.x + ex_space.z) / (4.0 * quat.w);
		quat.z = (ez_space.y + ey_space.z) / (4.0 * quat.w);
	} 
	
	// Normalize
	Scalar norm = 1.0 / sqrt(quat.x * quat.x + quat.y * quat.y + quat.z * quat.z + quat.w * quat.w);
	quat.x *= norm;
	quat.y *= norm;
	quat.z *= norm;
	quat.w *= norm;
	
	}

