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

#include <stdio.h>
#include <sys/time.h>
#include <algorithm>
#include <vector>
#include <iostream>

// safe call macros
#define CUDA_SAFE_CALL( call) do {                                         \
    cudaError err = call;                                                    \
    if( cudaSuccess != err) {                                                \
        fprintf(stderr, "Cuda error in file '%s' in line %i : %s.\n",        \
                __FILE__, __LINE__, cudaGetErrorString( err) );              \
    exit(EXIT_FAILURE);                                                      \
    } } while (0)

#define CUT_CHECK_ERROR(errorMessage) do {                                 \
    cudaThreadSynchronize();                                                \
    cudaError_t err = cudaGetLastError();                                    \
    if( cudaSuccess != err) {                                                \
        fprintf(stderr, "Cuda error: %s in file '%s' in line %i : %s.\n",    \
                errorMessage, __FILE__, __LINE__, cudaGetErrorString( err) );\
        exit(EXIT_FAILURE);                                                  \
    } } while (0)


//*************** parameters of the benchmark
unsigned int g_N;
float g_Lx;
float g_Ly;
float g_Lz;
float g_rcut;
const unsigned int g_Nmax = 256;    // Maximum number of particles each cell can hold
const float tweak_dist = 0.1f;

//*************** data structures
float4 *gh_pos, *gd_pos;            // particle positions
unsigned int g_Mx;  // X-dimension of the cell grid
unsigned int g_My;  // Y-dimension of the cell grid
unsigned int g_Mz;  // Z-dimension of the cell grid
unsigned int *gd_idxlist;   // \a Mx x \a My x \a Mz x \a Nmax 4D array holding the indices of the particles in each cell
unsigned int *gh_idxlist;   // \a Mx x \a My x \a Mz x \a Nmax 4D array holding the indices of the particles in each cell
unsigned int *gd_bin_size;  // number of particles in each bin
unsigned int *gh_bin_size;  // number of particles in each bin

unsigned int *gd_old_idxlist;   // old data for the above array (swapped on each update call)
unsigned int *gd_old_bin_size;  // old data for the above array (swapped on each update call)

uint4 *gd_bin_coords;   // pre-calculated bin coordinates for each bin
uint4 *gh_bin_coords;   // pre-calculated bin coordinates for each bin

unsigned int *g_ref_idxlist;    // reference idxlist for correctness comparison
unsigned int *g_ref_bin_size;   // reference bin_size for correctness comparison

//*************** functions for allocating and freeing the data structures
void allocate_data()
    {
    // allocate particle positions
    gh_pos = (float4 *)malloc(sizeof(float4) * g_N);
    CUDA_SAFE_CALL(cudaMalloc((void**)&gd_pos, sizeof(float4) * g_N));
    
    // determine grid dimensions
    g_Mx = int((g_Lx) / (g_rcut));
    g_My = int((g_Ly) / (g_rcut));
    g_Mz = int((g_Lz) / (g_rcut));
    g_Mx = std::min(g_Mx, (unsigned)30);
    g_My = std::min(g_My, (unsigned)30);
    g_Mz = std::min(g_Mz, (unsigned)30);
    g_Mx = std::max(g_Mx, (unsigned)1);
    g_My = std::max(g_My, (unsigned)1);
    g_Mz = std::max(g_Mz, (unsigned)1);

    // allocate bins
    unsigned int Nbins = g_Mx * g_My * g_Mz;
    gh_idxlist = (unsigned int *)malloc(Nbins * g_Nmax * sizeof(unsigned int));
    CUDA_SAFE_CALL(cudaMalloc((void**)&gd_idxlist, Nbins * g_Nmax * sizeof(unsigned int)));
    CUDA_SAFE_CALL(cudaMalloc((void**)&gd_old_idxlist, Nbins * g_Nmax * sizeof(unsigned int)));
    gh_bin_size = (unsigned int *)malloc(Nbins * sizeof(unsigned int));
    CUDA_SAFE_CALL(cudaMalloc((void**)&gd_bin_size, Nbins * g_Nmax * sizeof(unsigned int)));
    CUDA_SAFE_CALL(cudaMalloc((void**)&gd_old_bin_size, Nbins * g_Nmax * sizeof(unsigned int)));
    
    g_ref_idxlist = (unsigned int *)malloc(Nbins * g_Nmax * sizeof(unsigned int));
    g_ref_bin_size = (unsigned int *)malloc(Nbins * sizeof(unsigned int));
    
    gh_bin_coords = (uint4*)malloc(Nbins*sizeof(uint4));
    CUDA_SAFE_CALL(cudaMalloc((void**)&gd_bin_coords, Nbins*sizeof(uint4)));
    }

void free_data()
    {
    // free host memory
    free(gh_pos);
    free(gh_idxlist);
    free(gh_bin_size);
    free(g_ref_idxlist);
    free(g_ref_bin_size);
    free(gh_bin_coords);
    
    // free GPU memory
    CUDA_SAFE_CALL(cudaFree(gd_pos));
    CUDA_SAFE_CALL(cudaFree(gd_idxlist));
    CUDA_SAFE_CALL(cudaFree(gd_old_idxlist));
    CUDA_SAFE_CALL(cudaFree(gd_bin_size));
    CUDA_SAFE_CALL(cudaFree(gd_old_bin_size));
    CUDA_SAFE_CALL(cudaFree(gd_bin_coords));
    }

void initialize_data()
    {
    // initialize particles randomly
    for (unsigned int i = 0; i < g_N; i++)
        {
        gh_pos[i].x = float((rand())/float(RAND_MAX) - 0.5)*g_Lx;
        gh_pos[i].y = float((rand())/float(RAND_MAX) - 0.5)*g_Ly;
        gh_pos[i].z = float((rand())/float(RAND_MAX) - 0.5)*g_Lz;
        gh_pos[i].w = 0.0f;
        }
        
    // copy particles to the device
    CUDA_SAFE_CALL(cudaMemcpy(gd_pos, gh_pos, sizeof(float4)*g_N, cudaMemcpyHostToDevice));
    
    // zero all other memory
    memset(gh_idxlist, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz*g_Nmax);
    memset(g_ref_idxlist, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz*g_Nmax);
    memset(gh_bin_size, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz);
    memset(g_ref_bin_size, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz);
    
    CUDA_SAFE_CALL(cudaMemset(gd_idxlist, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz*g_Nmax));
    CUDA_SAFE_CALL(cudaMemset(gd_old_idxlist, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz*g_Nmax));
    CUDA_SAFE_CALL(cudaMemset(gd_bin_size, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz));
    CUDA_SAFE_CALL(cudaMemset(gd_old_bin_size, 0, sizeof(unsigned int)*g_Mx*g_My*g_Mz));
    
    // initialize the bin coords
    for (unsigned int i = 0; i < g_Mx; i++)
        for (unsigned int j = 0; j < g_My; j++)
            for (unsigned int k = 0; k < g_Mz; k++)
                gh_bin_coords[i*(g_Mz*g_My) + j * g_Mz + k] = make_uint4(i,j,k,0);
                
    CUDA_SAFE_CALL(cudaMemcpy(gd_bin_coords, gh_bin_coords, g_Mx*g_My*g_Mz*sizeof(uint4), cudaMemcpyHostToDevice));
    }

// moves the particles a "little bit" randomly and copies the new positions to the device
void tweak_data()
    {
    float xhi = g_Lx / 2.0f;
    float xlo = -xhi;
    float yhi = g_Ly / 2.0f;
    float ylo = -yhi;
    float zhi = g_Lz / 2.0f;
    float zlo = -zhi;
    
    for (unsigned int i = 0; i < g_N; i++)
        {
        // OK, so it is a poorly distributed tweak. So what, it serves it's purpose.
        float x = float((rand())/float(RAND_MAX) - 0.5);
        float y = float((rand())/float(RAND_MAX) - 0.5);
        float z = float((rand())/float(RAND_MAX) - 0.5);
        float len = sqrt(x*x + y*y + z*z);
        x = x / len * tweak_dist;
        y = y / len * tweak_dist;
        z = z / len * tweak_dist;
        
        gh_pos[i].x += x;
        gh_pos[i].y += y;
        gh_pos[i].z += z;
        
        // fix up boundary conditions
        if (gh_pos[i].x >= xhi)
            gh_pos[i].x -= g_Lx;
        if (gh_pos[i].x <= xlo)
            gh_pos[i].x += g_Lx;
        if (gh_pos[i].y >= yhi)
            gh_pos[i].y -= g_Ly;
        if (gh_pos[i].y <= ylo)
            gh_pos[i].y += g_Ly;
        if (gh_pos[i].z >= zhi)
            gh_pos[i].z -= g_Lz;
        if (gh_pos[i].z <= zlo)
            gh_pos[i].z += g_Lz;
        }
        
    // update the data on the device
    cudaMemcpy(gd_pos, gh_pos, sizeof(float4)*g_N, cudaMemcpyHostToDevice);
    }

// sorts the data to mimic HOOMD's standard data pattern (sort of)
void sort_data()
    {
    std::vector< std::pair<unsigned int, unsigned int> > bin_list(g_N);
    // make even bin dimensions
    float binx = g_Lx / float(g_Mx);
    float biny = g_Ly / float(g_My);
    float binz = g_Lz / float(g_Mz);
    
    float xlo = -g_Lx/2.0f;
    float ylo = -g_Lx/2.0f;
    float zlo = -g_Lx/2.0f;
    
    // precompute scale factors to eliminate division in inner loop
    float scalex = 1.0f / binx;
    float scaley = 1.0f / biny;
    float scalez = 1.0f / binz;
    
    for (unsigned int i = 0; i < g_N; i++)
        {
        // find the bin each particle belongs in
        unsigned int ib = (unsigned int)((gh_pos[i].x-xlo)*scalex);
        unsigned int jb = (unsigned int)((gh_pos[i].y-ylo)*scaley);
        unsigned int kb = (unsigned int)((gh_pos[i].z-zlo)*scalez);
        
        // need to handle the case where the particle is exactly at the box hi
        if (ib == g_Mx)
            ib = 0;
        if (jb == g_My)
            jb = 0;
        if (kb == g_Mz)
            kb = 0;
            
        // update the bin
        unsigned int bin = ib*(g_Mz*g_My) + jb * g_Mz + kb;
        bin_list[i] = std::pair<unsigned int, unsigned int>(bin, i);
        }
    
    std::sort(bin_list.begin(), bin_list.end());
    float4 *tmp_pos = (float4*)malloc(sizeof(float4)*g_N);
    memcpy(tmp_pos, gh_pos, sizeof(float4)*g_N);
    
    for (unsigned int i = 0; i < g_N; i++)
        {
        unsigned int j = bin_list[i].second;
        gh_pos[i] = tmp_pos[j];
        }
    
    free(tmp_pos);
    // update the data on the device
    cudaMemcpy(gd_pos, gh_pos, sizeof(float4)*g_N, cudaMemcpyHostToDevice);
    }

__global__ void fast_memclear_kernal(unsigned int *d_data, unsigned int N)
    {
    unsigned int idx = blockIdx.x * blockDim.x + threadIdx.x;
    d_data[idx] = 0;
    }


void rebin_particles_host(unsigned int *idxlist, unsigned int *bin_size, float4 *pos, unsigned int N, float Lx, float Ly, float Lz, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax);


//****************** verify gh_idxlist and gh_bin_size vs the reference ones
bool verify()
    {
    // generate the reference data
    rebin_particles_host(g_ref_idxlist, g_ref_bin_size, gh_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
    
    for (unsigned int bin = 0; bin < g_Mx*g_My*g_Mz; bin++)
        {
        // check bin sizes first
        if (gh_bin_size[bin] != g_ref_bin_size[bin])
            {
            printf("bin sizes differ for bin %d : %d != %d\n", bin, gh_bin_size[bin], g_ref_bin_size[bin]);
            return false;
            }
            
        // now check every single particle in the bins
        unsigned int size = gh_bin_size[bin];
        for (unsigned int ref_i = 0; ref_i < size; ref_i++)
            {
            unsigned int particle_i = g_ref_idxlist[bin*g_Nmax + ref_i];
            
            bool found = false;
            for (unsigned int j = 0; j < size; j++)
                {
                if (particle_i == gh_idxlist[bin*g_Nmax + j])
                    {
                    found = true;
                    break;
                    }
                }
            if (!found)
                {
                printf("particle %d not present in bin %d\n", particle_i, bin);
                return false;
                }
            }
        }
    return true;
    }

//****************** bins the data on the host from scratch
void rebin_particles_host(unsigned int *idxlist, unsigned int *bin_size, float4 *pos, unsigned int N, float Lx, float Ly, float Lz, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax)
    {
    // clear the bin sizes
    for (unsigned int i = 0; i < Mx*My*Mz; i++)
        bin_size[i] = 0;
        
    // make even bin dimensions
    float binx = Lx / float(Mx);
    float biny = Ly / float(My);
    float binz = Lz / float(Mz);
    
    float xlo = -Lx/2.0f;
    float ylo = -Lx/2.0f;
    float zlo = -Lx/2.0f;
    
    // precompute scale factors to eliminate division in inner loop
    float scalex = 1.0f / binx;
    float scaley = 1.0f / biny;
    float scalez = 1.0f / binz;
    
    // bin each particle
    for (unsigned int i = 0; i < N; i++)
        {
        // find the bin each particle belongs in
        unsigned int ib = (unsigned int)((pos[i].x-xlo)*scalex);
        unsigned int jb = (unsigned int)((pos[i].y-ylo)*scaley);
        unsigned int kb = (unsigned int)((pos[i].z-zlo)*scalez);
        
        // need to handle the case where the particle is exactly at the box hi
        if (ib == Mx)
            ib = 0;
        if (jb == My)
            jb = 0;
        if (kb == Mz)
            kb = 0;
            
        // update the bin
        unsigned int bin = ib*(Mz*My) + jb * Mz + kb;
        unsigned int size = bin_size[bin];
        if (size < Nmax)
            idxlist[bin*Nmax + size] = i;
        else
            {
            printf("Error, bins overflowed!\n");
            exit(1);
            }
        bin_size[bin]++;
        }
    }

// benchmark the host rebinning
float bmark_host_rebinning(bool include_memcpy, bool quiet=false)
    {
    // warm up
    rebin_particles_host(gh_idxlist, gh_bin_size, gh_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
    
    // verify results
    if (!verify())
        {
        printf("Invalid results in host bmark!\n");
        return 0.0f;
        }
        
    // benchmarks
    timeval start;
    gettimeofday(&start, NULL);
    
    unsigned int iters = 1000;
    for (unsigned int i = 0; i < iters; i++)
        {
        if (include_memcpy)
            cudaMemcpy(gh_pos, gd_pos, g_N*sizeof(unsigned int), cudaMemcpyDeviceToHost);
            
        rebin_particles_host(gh_idxlist, gh_bin_size, gh_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
        
        if (include_memcpy)
            {
            cudaMemcpy(gd_idxlist, gh_idxlist, g_Mx*g_My*g_Mz*g_Nmax*sizeof(unsigned int), cudaMemcpyHostToDevice);
            cudaMemcpy(gd_bin_size, gh_bin_size, g_Mx*g_My*g_Mz*sizeof(unsigned int), cudaMemcpyHostToDevice);
            }
        }
        
    timeval end;
    gettimeofday(&end, NULL);
    float t = (end.tv_sec - start.tv_sec)*1000.0f + (end.tv_usec - start.tv_usec)/1000.0f;
    float avg_t = t/float(iters);
    
    if (!quiet)
        {
        if (include_memcpy)
            printf("Host w/device memcpy: ");
        else
            printf("Host                : ");
        printf("%f ms\n", avg_t);
        }
    return avg_t;
    }

#if CUDA_ARCH >= 11

//*************************** simple method of binning on the GPU
// Run one thread per particle
// determine the bin that particle belongs in
// atomicInc the bin size
// write the particle into the bin
// done.
__global__ void rebin_simple_kernel(unsigned int *d_idxlist, unsigned int *d_bin_size, float4 *d_pos, unsigned int N, float xlo, float ylo, float zlo, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax, float scalex, float scaley, float scalez)
    {
    // read in the particle that belongs to this thread
    unsigned int idx = blockDim.x * blockIdx.x + threadIdx.x;
    if (idx >= N)
        return;
        
    float4 pos = d_pos[idx];
    
    // determine which bin it belongs in
    unsigned int ib = (unsigned int)((pos.x-xlo)*scalex);
    unsigned int jb = (unsigned int)((pos.y-ylo)*scaley);
    unsigned int kb = (unsigned int)((pos.z-zlo)*scalez);
    
    // need to handle the case where the particle is exactly at the box hi
    if (ib == Mx)
        ib = 0;
    if (jb == My)
        jb = 0;
    if (kb == Mz)
        kb = 0;
        
    unsigned int bin = ib*(Mz*My) + jb * Mz + kb;
    unsigned int size = atomicInc(&d_bin_size[bin], 0xffffffff);
    if (size < Nmax)
        d_idxlist[bin*Nmax + size] = idx;
    }

void rebin_particles_simple(unsigned int *idxlist, unsigned int *bin_size, float4 *pos, unsigned int N, float Lx, float Ly, float Lz, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax)
    {
    // run one particle per thread
    int block_size = 128;
    int n_blocks = (int)ceil(float(N)/(float)block_size);
    
    // make even bin dimensions
    float binx = Lx / float(Mx);
    float biny = Ly / float(My);
    float binz = Lz / float(Mz);
    
    float xlo = -Lx/2.0f;
    float ylo = -Lx/2.0f;
    float zlo = -Lx/2.0f;
    
    // precompute scale factors to eliminate division in inner loop
    float scalex = 1.0f / binx;
    float scaley = 1.0f / biny;
    float scalez = 1.0f / binz;
    
    // call the kernel
    //cudaMemset(gd_bin_size, 0, sizeof(unsigned int)*Mx*My*Mz);
    fast_memclear_kernal<<<(int)ceil(float(Mx*My*Mz)/(float)block_size), block_size>>>(gd_bin_size, Mx*My*Mz);
    rebin_simple_kernel<<<n_blocks, block_size>>>(idxlist, bin_size, pos, N, xlo, ylo, zlo, Mx, My, Mz, Nmax, scalex, scaley, scalez);
    }

// benchmark the device rebinning
float bmark_simple_rebinning(bool quiet=false)
    {
    // warm up
    rebin_particles_simple(gd_idxlist, gd_bin_size, gd_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
    CUT_CHECK_ERROR("kernel failed");
    // copy back from device
    CUDA_SAFE_CALL(cudaMemcpy(gh_idxlist, gd_idxlist, g_Mx*g_My*g_Mz*g_Nmax*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    CUDA_SAFE_CALL(cudaMemcpy(gh_bin_size, gd_bin_size, g_Mx*g_My*g_Mz*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    
    // verify results
    if (!verify())
        {
        printf("Invalid results in GPU/simple bmark!\n");
        return 0.0f;
        }
        
    // benchmarks
    float total_time = 0.0f;
    cudaEvent_t start, end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    
    
    unsigned int iters = 1000;
    for (unsigned int i = 0; i < iters; i++)
        {
        cudaEventRecord(start, 0);
        rebin_particles_simple(gd_idxlist, gd_bin_size, gd_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
        cudaEventRecord(end, 0);
        
        float tmp;
        cudaEventSynchronize(end);
        cudaEventElapsedTime(&tmp, start, end);
        total_time += tmp;
        }
        
    float avg_t = total_time/float(iters);
    
    // copy back from device
    CUDA_SAFE_CALL(cudaMemcpy(gh_idxlist, gd_idxlist, g_Mx*g_My*g_Mz*g_Nmax*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    CUDA_SAFE_CALL(cudaMemcpy(gh_bin_size, gd_bin_size, g_Mx*g_My*g_Mz*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    
    // verify results again to be sure
    if (!verify())
        {
        printf("Invalid results at end of GPU/simple bmark!\n");
        return 0.0f;
        }
        
    if (!quiet)
        {
        printf("GPU/simple          : ");
        printf("%f ms\n", avg_t);
        }
    return avg_t;
    }


//*************************** simple method of binning on the GPU - with sorting
// Run one thread per particle
// determine the bin that particle belongs in
// sort the particles based on the bin
// calculate the number of particles added to each bin in the sorted array
// atomicInc the bin size in global memory
// write the particle into the bin
// done.

// bitonic sort from CUDA SDK
template<class T> __device__ inline void swap(T & a, T & b)
    {
    T tmp = a;
    a = b;
    b = tmp;
    }

template<class T, unsigned int block_size> __device__ inline void bitonic_sort(T *shared)
    {
    unsigned int tid = threadIdx.x;
    
    // Parallel bitonic sort.
#pragma unroll
    for (int k = 2; k <= block_size; k *= 2)
        {
        // Bitonic merge:
#pragma unroll
        for (int j = k / 2; j>0; j /= 2)
            {
            int ixj = tid ^ j;
            
            if (ixj > tid)
                {
                if ((tid & k) == 0)
                    {
                    if (shared[tid] > shared[ixj])
                        {
                        swap(shared[tid], shared[ixj]);
                        }
                    }
                else
                    {
                    if (shared[tid] < shared[ixj])
                        {
                        swap(shared[tid], shared[ixj]);
                        }
                    }
                }
                
            __syncthreads();
            }
        }
    }

struct bin_id_pair
    {
    unsigned int bin;
    unsigned int id;
    unsigned int start_offset;  // pad to minimize bank conflicts
    };

__device__ inline bin_id_pair make_bin_id_pair(unsigned int bin, unsigned int id)
    {
    bin_id_pair res;
    res.bin = bin;
    res.id = id;
    res.start_offset = 0;
    return res;
    }

__device__ inline bool operator< (const bin_id_pair& a, const bin_id_pair& b)
    {
    if (a.bin == b.bin)
        return (a.id < b.id);
    else
        return (a.bin < b.bin);
    }

__device__ inline bool operator> (const bin_id_pair& a, const bin_id_pair& b)
    {
    if (a.bin == b.bin)
        return (a.id > b.id);
    else
        return (a.bin > b.bin);
    }

template<class T, unsigned int block_size> __device__ inline void scan_naive(T *temp)
    {
    int thid = threadIdx.x;
    
    int pout = 0;
    int pin = 1;
    
#pragma unroll
    for (int offset = 1; offset < block_size; offset *= 2)
        {
        pout = 1 - pout;
        pin  = 1 - pout;
        __syncthreads();
        
        temp[pout*block_size+thid] = temp[pin*block_size+thid];
        
        if (thid >= offset)
            temp[pout*block_size+thid] += temp[pin*block_size+thid - offset];
        }
        
    __syncthreads();
    // bring the data back to the initial array
    if (pout == 1)
        {
        pout = 1 - pout;
        pin  = 1 - pout;
        temp[pout*block_size+thid] = temp[pin*block_size+thid];
        __syncthreads();
        }
    }

template<unsigned int block_size> __global__ void rebin_simple_sort_kernel(unsigned int *d_idxlist, unsigned int *d_bin_size, float4 *d_pos, unsigned int N, float xlo, float ylo, float zlo, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax, float scalex, float scaley, float scalez)
    {
    // sentinel to label a bin as invalid
    const unsigned int INVALID_BIN = 0xffffffff;
    
    // read in the particle that belongs to this thread
    unsigned int idx = blockDim.x * blockIdx.x + threadIdx.x;
    
    float4 pos = make_float4(0.0f, 0.0f, 0.0f, 0.0f);
    if (idx < N)
        pos = d_pos[idx];
        
    // determine which bin it belongs in
    unsigned int ib = (unsigned int)((pos.x-xlo)*scalex);
    unsigned int jb = (unsigned int)((pos.y-ylo)*scaley);
    unsigned int kb = (unsigned int)((pos.z-zlo)*scalez);
    
    // need to handle the case where the particle is exactly at the box hi
    if (ib == Mx)
        ib = 0;
    if (jb == My)
        jb = 0;
    if (kb == Mz)
        kb = 0;
        
    unsigned int bin = ib*(Mz*My) + jb * Mz + kb;
    
    // if we are past the end of the array, mark the bin as invalid
    if (idx >= N)
        bin = INVALID_BIN;
        
    // load up shared memory
    __shared__ bin_id_pair bin_pairs[block_size];
    bin_pairs[threadIdx.x] = make_bin_id_pair(bin, idx);
    __syncthreads();
    
    // sort it
    bitonic_sort<bin_id_pair, block_size>(bin_pairs);
    
    // identify the breaking points
    __shared__ unsigned int unique[block_size*2+1];
    
    bool is_unique = false;
    if (threadIdx.x > 0 && bin_pairs[threadIdx.x].bin != bin_pairs[threadIdx.x-1].bin)
        is_unique = true;
        
    unique[threadIdx.x] = 0;
    if (is_unique)
        unique[threadIdx.x] = 1;
        
    // threadIdx.x = 0 is unique: but we don't want to count it in the scan
    if (threadIdx.x == 0)
        is_unique = true;
        
    __syncthreads();
    
    // scan to find addresses to write to
    scan_naive<unsigned int, block_size>(unique);
    
    // determine start location of each unique value in the array
    // save shared memory by reusing the temp data in the unique[] array
    unsigned int *start = &unique[block_size];
    
    if (is_unique)
        start[unique[threadIdx.x]] = threadIdx.x;
        
    // boundary condition: need one past the end
    if (threadIdx.x == 0)
        start[unique[block_size-1]+1] = block_size;
        
    __syncthreads();
    
    bool is_valid = (bin_pairs[threadIdx.x].bin < Mx*My*Mz);
    
    // now: each unique start point does it's own atomicAdd to find the starting offset
    // the is_valid check is to prevent writing to out of bounds memory at the tail end of the array
    if (is_unique && is_valid)
        bin_pairs[unique[threadIdx.x]].start_offset = atomicAdd(&d_bin_size[bin_pairs[threadIdx.x].bin], start[unique[threadIdx.x]+1] - start[unique[threadIdx.x]]);
        
    __syncthreads();
    
    // finally! we can write out all the particles
    // the is_valid check is to prevent writing to out of bounds memory at the tail end of the array
    unsigned int offset = bin_pairs[unique[threadIdx.x]].start_offset;
    if (offset + threadIdx.x - start[unique[threadIdx.x]] < Nmax && is_valid)
        d_idxlist[bin_pairs[threadIdx.x].bin*Nmax + offset + threadIdx.x - start[unique[threadIdx.x]]] = bin_pairs[threadIdx.x].id;
    }

void rebin_particles_simple_sort(unsigned int *idxlist, unsigned int *bin_size, float4 *pos, unsigned int N, float Lx, float Ly, float Lz, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax, unsigned int block_size)
    {
    // run one particle per thread
    int n_blocks = (int)ceil(float(N)/(float)block_size);
    
    // make even bin dimensions
    float binx = Lx / float(Mx);
    float biny = Ly / float(My);
    float binz = Lz / float(Mz);
    
    float xlo = -Lx/2.0f;
    float ylo = -Lx/2.0f;
    float zlo = -Lx/2.0f;
    
    // precompute scale factors to eliminate division in inner loop
    float scalex = 1.0f / binx;
    float scaley = 1.0f / biny;
    float scalez = 1.0f / binz;
    
    // call the kernel
    //cudaMemset(gd_bin_size, 0, sizeof(unsigned int)*Mx*My*Mz);
    fast_memclear_kernal<<<(int)ceil(float(Mx*My*Mz)/(float)block_size), block_size>>>(gd_bin_size, Mx*My*Mz);
    
    if (block_size == 32)
        rebin_simple_sort_kernel<32><<<n_blocks, block_size>>>(idxlist, bin_size, pos, N, xlo, ylo, zlo, Mx, My, Mz, Nmax, scalex, scaley, scalez);
    else if (block_size == 64)
        rebin_simple_sort_kernel<64><<<n_blocks, block_size>>>(idxlist, bin_size, pos, N, xlo, ylo, zlo, Mx, My, Mz, Nmax, scalex, scaley, scalez);
    else if (block_size == 128)
        rebin_simple_sort_kernel<128><<<n_blocks, block_size>>>(idxlist, bin_size, pos, N, xlo, ylo, zlo, Mx, My, Mz, Nmax, scalex, scaley, scalez);
    else if (block_size == 256)
        rebin_simple_sort_kernel<256><<<n_blocks, block_size>>>(idxlist, bin_size, pos, N, xlo, ylo, zlo, Mx, My, Mz, Nmax, scalex, scaley, scalez);
    else if (block_size == 512)
        rebin_simple_sort_kernel<512><<<n_blocks, block_size>>>(idxlist, bin_size, pos, N, xlo, ylo, zlo, Mx, My, Mz, Nmax, scalex, scaley, scalez);
    else
        {
        printf("invalid block size!\n");
        exit(1);
        }
    }

// benchmark the device rebinning
float bmark_simple_sort_rebinning(unsigned int block_size, bool quiet=false)
    {
    // warm up
    rebin_particles_simple_sort(gd_idxlist, gd_bin_size, gd_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax, block_size);
    CUT_CHECK_ERROR("kernel failed");
    // copy back from device
    CUDA_SAFE_CALL(cudaMemcpy(gh_idxlist, gd_idxlist, g_Mx*g_My*g_Mz*g_Nmax*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    CUDA_SAFE_CALL(cudaMemcpy(gh_bin_size, gd_bin_size, g_Mx*g_My*g_Mz*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    
    // verify results
    if (!verify())
        {
        printf("Invalid results in GPU/simple/sort bmark!\n");
        return 0.0f;
        }
        
    // benchmarks
    float total_time = 0.0f;
    cudaEvent_t start, end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    
    
    unsigned int iters = 1000;
    for (unsigned int i = 0; i < iters; i++)
        {
        cudaEventRecord(start, 0);
        rebin_particles_simple_sort(gd_idxlist, gd_bin_size, gd_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax, block_size);
        cudaEventRecord(end, 0);
        
        float tmp;
        cudaEventSynchronize(end);
        cudaEventElapsedTime(&tmp, start, end);
        total_time += tmp;
        }
        
    float avg_t = total_time/float(iters);
    
    // copy back from device
    CUDA_SAFE_CALL(cudaMemcpy(gh_idxlist, gd_idxlist, g_Mx*g_My*g_Mz*g_Nmax*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    CUDA_SAFE_CALL(cudaMemcpy(gh_bin_size, gd_bin_size, g_Mx*g_My*g_Mz*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    
    // verify results again to be sure
    if (!verify())
        {
        printf("Invalid results at end of GPU/simple/sort bmark!\n");
        return 0.0f;
        }
    
    if (!quiet)
        {
        printf("GPU/simple/sort/%3d : ", block_size);
        printf("%f ms\n", avg_t);
        }
    return avg_t;
    }


//*************************** simple update method of binning on the GPU
// Run one thread per bin
// loop through all particles in neighboring bins
// determine which of those particles belong in this bin, and write them there
// done.
texture<float4, 1, cudaReadModeElementType> pos_tex;
texture<unsigned int, 1, cudaReadModeElementType> in_bin_size_tex;
texture<unsigned int, 1, cudaReadModeElementType> in_idxlist_tex;

__global__ void update_simple_kernel(unsigned int *d_out_idxlist, unsigned int *d_out_bin_size, uint4* d_bin_coords, float xlo, float ylo, float zlo, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax, float scalex, float scaley, float scalez)
    {
    // find the coordinates of our bin
    unsigned int bin = blockIdx.x * blockDim.x + threadIdx.x;
    if (bin >= Mx*My*Mz)
        return;
    uint4 coords = d_bin_coords[bin];
    int bin_i = coords.x;
    int bin_j = coords.y;
    int bin_k = coords.z;
    
    // intialize the new particles in this bin to 0
    unsigned int bin_size = 0;
    
    // loop through all the neighboring bins and find particles that now belong in this bin
    for (int cur_i = bin_i - 1; cur_i <= bin_i+1; cur_i++)
        {
        int neigh_i = cur_i;
        if (neigh_i == -1)
            neigh_i = Mx-1;
        if (neigh_i == Mx)
            neigh_i = 0;
            
        for (int cur_j = bin_j - 1; cur_j <= bin_j+1; cur_j++)
            {
            int neigh_j = cur_j;
            if (neigh_j == -1)
                neigh_j = My-1;
            if (neigh_j == My)
                neigh_j = 0;
                
            for (int cur_k = bin_k - 1; cur_k <= bin_k+1; cur_k++)
                {
                int neigh_k = cur_k;
                if (neigh_k == -1)
                    neigh_k = Mz-1;
                if (neigh_k == Mz)
                    neigh_k = 0;
                    
                // determine the index of the neighboring bin
                unsigned int neigh_bin = neigh_i*(Mz*My) + neigh_j * Mz + neigh_k;
                
                // loop through all particles in that neighboring bin
                unsigned int neigh_bin_size = tex1Dfetch(in_bin_size_tex, neigh_bin);
                
                for (unsigned int cur_particle = 0; cur_particle < neigh_bin_size; cur_particle++)
                    {
                    // read in the current particle in the neighboring bin
                    unsigned int pidx = tex1Dfetch(in_idxlist_tex, neigh_bin*Nmax + cur_particle);
                    float4 pos = tex1Dfetch(pos_tex, pidx);
                    
                    // determine which bin the particle should be in
                    unsigned int ib = (unsigned int)((pos.x-xlo)*scalex);
                    unsigned int jb = (unsigned int)((pos.y-ylo)*scaley);
                    unsigned int kb = (unsigned int)((pos.z-zlo)*scalez);
                    
                    // need to handle the case where the particle is exactly at the box hi
                    if (ib == Mx)
                        ib = 0;
                    if (jb == My)
                        jb = 0;
                    if (kb == Mz)
                        kb = 0;
                        
                    unsigned int cur_bin = ib*(Mz*My) + jb * Mz + kb;
                    
                    // if that is this bin, add it to the bin
                    if (bin == cur_bin && bin_size < Nmax)
                        {
                        d_out_idxlist[bin*Nmax + bin_size] = pidx;
                        bin_size++;
                        }
                    }
                }
            }
        }
        
    d_out_bin_size[bin] = bin_size;
    }


void update_particles_simple(float4 *pos, unsigned int N, float Lx, float Ly, float Lz, unsigned int Mx, unsigned int My, unsigned int Mz, unsigned int Nmax)
    {
    // run one bin per thread
    int block_size = 256;
    int n_blocks = (int)ceil(float(Mx*My*Mz)/(float)block_size);
    
    // make even bin dimensions
    float binx = Lx / float(Mx);
    float biny = Ly / float(My);
    float binz = Lz / float(Mz);
    
    float xlo = -Lx/2.0f;
    float ylo = -Lx/2.0f;
    float zlo = -Lx/2.0f;
    
    // precompute scale factors to eliminate division in inner loop
    float scalex = 1.0f / binx;
    float scaley = 1.0f / biny;
    float scalez = 1.0f / binz;
    
    // swap the pointers
    unsigned int * tmp;
    tmp = gd_idxlist;
    gd_idxlist = gd_old_idxlist;
    gd_old_idxlist = tmp;
    
    tmp = gd_bin_size;
    gd_bin_size = gd_old_bin_size;
    gd_old_bin_size = tmp;
    
    // bind the textures
    cudaBindTexture(0, pos_tex, pos, sizeof(float4) * N);
    cudaBindTexture(0, in_bin_size_tex, gd_old_bin_size, sizeof(unsigned int) * Mx*My*Mz);
    cudaBindTexture(0, in_idxlist_tex, gd_old_idxlist, sizeof(unsigned int) * Mx*My*Mz*Nmax);
    
    // call the kernel
    update_simple_kernel<<<n_blocks, block_size>>>(gd_idxlist, gd_bin_size, gd_bin_coords, xlo, ylo, zlo, Mx, My, Mz, Nmax, scalex, scaley, scalez);
    }

// benchmark the device rebinning
void bmark_simple_updating()
    {
    // warm up
    rebin_particles_simple(gd_idxlist, gd_bin_size, gd_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
    CUT_CHECK_ERROR("kernel failed");
    update_particles_simple(gd_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
    
    // copy back from device
    CUDA_SAFE_CALL(cudaMemcpy(gh_idxlist, gd_idxlist, g_Mx*g_My*g_Mz*g_Nmax*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    CUDA_SAFE_CALL(cudaMemcpy(gh_bin_size, gd_bin_size, g_Mx*g_My*g_Mz*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    
    // verify results
    if (!verify())
        {
        printf("Invalid results in GPU/update bmark!\n");
        return;
        }
        
    // benchmarks
    float total_time = 0.0f;
    cudaEvent_t start, end;
    cudaEventCreate(&start);
    cudaEventCreate(&end);
    
    unsigned int iters = 1000;
    for (unsigned int i = 0; i < iters; i++)
        {
        tweak_data();
        
        cudaThreadSynchronize();
        
        cudaEventRecord(start, 0);
        update_particles_simple(gd_pos, g_N, g_Lx, g_Ly, g_Lz, g_Mx, g_My, g_Mz, g_Nmax);
        cudaEventRecord(end, 0);
        
        float tmp;
        cudaEventSynchronize(end);
        cudaEventElapsedTime(&tmp, start, end);
        total_time += tmp;
        }
        
    float avg_t = total_time/float(iters);
    
    // copy back from device
    CUDA_SAFE_CALL(cudaMemcpy(gh_idxlist, gd_idxlist, g_Mx*g_My*g_Mz*g_Nmax*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    CUDA_SAFE_CALL(cudaMemcpy(gh_bin_size, gd_bin_size, g_Mx*g_My*g_Mz*sizeof(unsigned int), cudaMemcpyDeviceToHost));
    
    // verify results again to be sure
    if (!verify())
        {
        printf("Invalid results at end of GPU/update bmark!\n");
        return;
        }
        
    printf("GPU/update          : ");
    printf("%f ms\n", avg_t);
    }

#endif

void bmark_grid()
    {
    g_N = 64000;

    std::vector<float> rcut_list;
    std::vector<float> phi_list;

    std::cout << "rcut = [";
    for (float rcut = 1.0f; rcut < 4.0f; rcut += 0.1f)
        {
        rcut_list.push_back(rcut);
        std::cout << rcut << " ";
        }
    std::cout << "];" << std::endl;
    
    std::cout << "phi = [";
    for (float phi = 0.01f; phi < 1.5f; phi += 0.1f)
        {
        phi_list.push_back(phi);
        std::cout << phi << " ";
        }
    std::cout << "];" << std::endl;

    std::cout << "btim = [";
    for (unsigned int i = 0; i < rcut_list.size(); i++)
        {
        g_rcut = rcut_list[i];

        for (unsigned int j = 0; j < phi_list.size(); j++)
            {
            float phi = phi_list[j];;
            float L = pow(float(M_PI/6.0)*float(g_N) / phi, 1.0f/3.0f);
            g_Lx = g_Ly = g_Lz = L;
    
            // setup
            allocate_data();
            initialize_data();
            sort_data();
    
            // normally, data in HOOMD is not perfectly sorted:
            for (unsigned int k = 0; k < 100; k++)
                tweak_data();
        
            float time = bmark_simple_rebinning();
            std::cout << time << " ";

            free_data();
            }
        std::cout << ";" << std::endl;
        }
    std::cout << "];" << std::endl;
    }

void bmark_N()
    {
    g_rcut = 3.1f;
    float phi = 0.20f;
    
    std::vector<unsigned int> N_list;
    for (unsigned int power = 2; power < 6 ; power++)
        {
        N_list.push_back(1*pow(10.0f,float(power)));
        N_list.push_back(2*pow(10.0f,float(power)));
        N_list.push_back(3*pow(10.0f,float(power)));
        N_list.push_back(4*pow(10.0f,float(power)));
        N_list.push_back(5*pow(10.0f,float(power)));
        N_list.push_back(6*pow(10.0f,float(power)));
        N_list.push_back(7*pow(10.0f,float(power)));
        N_list.push_back(8*pow(10.0f,float(power)));
        N_list.push_back(9*pow(10.0f,float(power)));
        }


    std::cout << "N = [";
    for (unsigned int i = 0; i < N_list.size(); i++)
        std::cout << N_list[i] << " ";
    std::cout << "];" << std::endl;

    std::cout << "btim = [";
    for (unsigned int i = 0; i < N_list.size(); i++)
        {
        g_N = N_list[i];
        float L = pow(float(M_PI/6.0)*float(g_N) / phi, 1.0f/3.0f);
        g_Lx = g_Ly = g_Lz = L;
    
        // setup
        allocate_data();
        initialize_data();
        sort_data();
    
        // normally, data in HOOMD is not perfectly sorted:
        for (unsigned int k = 0; k < 100; k++)
            tweak_data();
    
        //float time = bmark_host_rebinning(true, true);
        float time = bmark_simple_sort_rebinning(64, true);
        std::cout << time << " ";

        free_data();
        }
    std::cout << "];" << std::endl;
    }

int main(int argc, char **argv)
    {
    //bmark_grid();
    //bmark_N();

#if 1
    // choose defaults if no args specified
    float phi;
    if (argc == 1)
        {
        g_N = 64000;
        g_rcut = 3.8f;
        phi = 0.20f;
        }
    if (argc == 2)
        {
        g_N = atoi(argv[1]);
        g_rcut = 3.8f;
        phi = 0.20f;
        }
    if (argc == 3)
        {
        g_N = atoi(argv[1]);
        g_rcut = atof(argv[2]);
        phi = 0.20f;
        }
    if (argc == 4)
        {
        g_N = atoi(argv[1]);
        g_rcut = atof(argv[2]);
        phi = atof(argv[3]);
        }
        
    float L = pow(float(M_PI/6.0)*float(g_N) / phi, 1.0f/3.0f);
    g_Lx = g_Ly = g_Lz = L;
    
    // setup
    printf("Running gpu_binning microbenchmark: %d %f %f\n", g_N, g_rcut, phi);
    allocate_data();
    initialize_data();
    sort_data();
    
    // normally, data in HOOMD is not perfectly sorted:
    for (unsigned int i = 0; i < 100; i++)
        tweak_data();
        
    // run the various benchmarks
    bmark_host_rebinning(false);
    //bmark_host_rebinning(true);
#if CUDA_ARCH >= 11
    bmark_simple_rebinning();
    bmark_simple_sort_rebinning(32);
    bmark_simple_sort_rebinning(64);
    bmark_simple_sort_rebinning(128);
    bmark_simple_sort_rebinning(256);
    bmark_simple_sort_rebinning(512);
    /*bmark_simple_updating();*/
#endif
    
    free_data();
#endif
    
    return 0;
    }

