// =============================================================================
// PROJECT CHRONO - http://projectchrono.org
//
// Copyright (c) 2016 projectchrono.org
// All right reserved.
//
// Use of this source code is governed by a BSD-style license that can be found
// in the LICENSE file at the top level of the distribution and at
// http://projectchrono.org/license-chrono.txt.
//
// =============================================================================
// Authors: Hammad Mazhar
// =============================================================================
//
// Description: Helper functions for cuda
// =============================================================================

#pragma once

#define num_threads_per_block 128

#include <cuda_runtime_api.h>
#include <cuda.h>

#include <cassert>
#include <vector>
#include "chrono_parallel/math/real.h"
#include "chrono_parallel/math/real3.h"
//
namespace chrono {

#define cudaCheck(x)                                                                \
    {                                                                               \
        cudaError_t err = x;                                                        \
        if (err != cudaSuccess) {                                                   \
            printf("Cuda error: %d in %s at %s:%d\n", err, #x, __FILE__, __LINE__); \
            assert(0);                                                              \
        }                                                                           \
    }

#define Check(x)                      \
    x;                                \
    cudaCheck(cudaPeekAtLastError()); \
    cudaCheck(cudaDeviceSynchronize());

#define BLOCKS(x) (x + num_threads_per_block - 1) / num_threads_per_block
#define CONFIG(x) BLOCKS(x), num_threads_per_block

// Used by cub
struct real3Min {
    inline CUDA_HOST_DEVICE real3 operator()(const real3& a, const real3& b) {
        return real3(chrono::Min(a[0], b[0]), chrono::Min(a[1], b[1]), chrono::Min(a[2], b[2]));
    }
};

struct real3Max {
    inline CUDA_HOST_DEVICE real3 operator()(const real3& a, const real3& b) {
        return real3(chrono::Max(a[0], b[0]), chrono::Max(a[1], b[1]), chrono::Max(a[2], b[2]));
    }
};

// code adopted from http://stackoverflow.com/questions/17371275/implementing-max-reduce-in-cuda
// ========================================================================================

#ifdef CHRONO_PARALLEL_USE_DOUBLE
#define ATOMIC_ADD(x, y) atomicAdd_d(x, y)
#else
#define ATOMIC_ADD(x, y) atomicAdd(x, y)
#endif

static CUDA_DEVICE double atomicAdd_d(double* address, double value) {
    unsigned long long int* address_as_ull = (unsigned long long int*)address;
    unsigned long long int old = *address_as_ull, assumed;
    do {
        assumed = old;
        old = atomicCAS(address_as_ull, assumed, __double_as_longlong(value + __longlong_as_double(assumed)));
    } while (assumed != old);
    return __longlong_as_double(old);
}

static CUDA_DEVICE double AtomicMax(double* address, double value) {
    unsigned long long int* address_as_ull = (unsigned long long int*)address;
    unsigned long long int old = *address_as_ull, assumed;

    while (value > __longlong_as_double(old)) {
        assumed = old;
        old = atomicCAS(address_as_ull, assumed, __double_as_longlong(value));
    }
    return __longlong_as_double(old);
}

static CUDA_DEVICE double AtomicMin(double* address, double value) {
    unsigned long long int* address_as_ull = (unsigned long long int*)address;
    unsigned long long int old = *address_as_ull, assumed;
    while (value < __longlong_as_double(old)) {
        assumed = old;
        old = atomicCAS(address_as_ull, assumed, __double_as_longlong(value));
    }
    return __longlong_as_double(old);
}

static inline CUDA_DEVICE float AtomicMax(float* address, float value) {
    int* address_as_int = (int*)address;
    int old = *address_as_int, assumed;

    while (value > __int_as_float(old)) {
        assumed = old;
        old = atomicCAS(address_as_int, assumed, __float_as_int(value));
    }

    return __int_as_float(old);
}

static inline CUDA_DEVICE float AtomicMin(float* address, float value) {
    int* address_as_int = (int*)address;
    int old = *address_as_int, assumed;

    while (value < __int_as_float(old)) {
        assumed = old;
        old = atomicCAS(address_as_int, assumed, __float_as_int(value));
    }

    return __int_as_float(old);
}

static inline CUDA_DEVICE void AtomicAdd(real3* pointer, real3 val) {
#ifdef CHRONO_PARALLEL_USE_DOUBLE
    atomicAdd_d(&pointer->x, val.x);
    atomicAdd_d(&pointer->y, val.y);
    atomicAdd_d(&pointer->z, val.z);
#else
    atomicAdd(&pointer->x, val.x);
    atomicAdd(&pointer->y, val.y);
    atomicAdd(&pointer->z, val.z);
#endif
}

static inline CUDA_DEVICE void AtomicMax(real3* pointer, real3 val) {
    AtomicMax(&pointer->x, val.x);
    AtomicMax(&pointer->y, val.y);
    AtomicMax(&pointer->z, val.z);
}

static inline CUDA_DEVICE void AtomicMin(real3* pointer, real3 val) {
    AtomicMin(&pointer->x, val.x);
    AtomicMin(&pointer->y, val.y);
    AtomicMin(&pointer->z, val.z);
}

// Scoped CUDA timer
struct CudaEventTimer {
    CudaEventTimer(cudaEvent_t start, cudaEvent_t stop, bool active, float& time)
        : mEnabled(active), mTime(time), mStart(start), mStop(stop) {
        if (mEnabled) {
            cudaCheck(cudaEventRecord(mStart, 0));
        }
    }

    ~CudaEventTimer() {
        if (mEnabled) {
            cudaCheck(cudaEventRecord(mStop, 0));
            cudaCheck(cudaEventSynchronize(mStop));

            elapsedTime = 0;
            cudaCheck(cudaEventElapsedTime(&elapsedTime, mStart, mStop));

            mTime += elapsedTime;
        }
    }

    bool mEnabled;
    float& mTime;
    float elapsedTime;
    cudaEvent_t mStart;
    cudaEvent_t mStop;
};
}
