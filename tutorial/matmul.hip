// Author : Yash Deshpande
// Date : 29-12-2024
// Code Link: https://github.com/Yash-Desh/CUDA-Practice/blob/main/parallel_patterns/03_matmul/4_matmul.cu
// Tutor : Izzat El Hajj, AUB
// HIP port of matmul.cu

// ###############################################################################
// Compile : hipcc -O2 --offload-arch=gfx942 matmul.hip -o matmul_hip
// Execute : ./matmul_hip [N]        // N = matrix dimension, defaults to 1024
//
// Extracting a raw code object (.hsaco):
//   --genco emits a __CLANG_OFFLOAD_BUNDLE__, not an ELF, so it must be
//   unbundled. clang-offload-bundler is not on PATH; it ships with ROCm.
//
//   1. hipcc --genco --offload-arch=gfx942 matmul.hip -o matmul_gfx942.co
//   2. /opt/rocm/llvm/bin/clang-offload-bundler --type=o --unbundle \
//        --targets=hipv4-amdgcn-amd-amdhsa--gfx942 \
//        --input=matmul_gfx942.co --output=matmul_gfx942.hsaco
//
//   List the bundle's targets if the --targets string does not match:
//     /opt/rocm/llvm/bin/clang-offload-bundler --type=o --list \
//       --input=matmul_gfx942.co
//
//   The kernel is C++ mangled in the code object: _Z13matmul_kernelPfS_S_j
// ###############################################################################



#include <iostream>
#include <hip/hip_runtime.h>
#include <cstdlib> // atoi, malloc, free
#include <random>  // generate random numbers
#include <chrono>  // std::chrono namespace provides timer functions in C++, for CPU timing
#include <ratio>   // std::ratio provides easy conversions between metric units, for CPU timing

using std::chrono::duration;
using std::chrono::high_resolution_clock;

// prints all the elements of given array
void printArr(float *arr, int size)
{
    for (int i = 0; i < size; i++)
    {
        std::cout << arr[i] << " ";
    }
    std::cout << std::endl;
}


// performs matrix multiplication on the CPU
void matmul_cpu(float *A, float *B, float *C, unsigned int N)
{
    for(int row=0; row<N; row++)
    {
        for(int col=0; col<N; col++)
        {
            float sum = 0.0f;
            for(int i=0; i<N; i++)
            {
                sum += A[row * N + i] * B[i * N + col];
            }
            C[row * N + col] = sum;
        }
    }
}

__global__ void matmul_kernel(float *A, float *B, float *C, unsigned int N)
{
    // NOTE : 1 thread per output pixel
    unsigned int row = blockDim.y * blockIdx.y + threadIdx.y;
    unsigned int col = blockDim.x * blockIdx.x + threadIdx.x;

    if (row < N && col < N)
    {
        float sum = 0.0f;
        for (int i = 0; i < N; i++)
        {
            sum += A[row * N + i] * B[i * N + col];
        }
        C[row * N + col] = sum;
    }
}

void matmul_gpu(float *A, float *B, float *C, unsigned int N)
{
    // for timing purpose
    hipEvent_t start;
    hipEvent_t stop;
    hipEventCreate(&start);
    hipEventCreate(&stop);

    // Allocate memory on GPU
    float *A_d, *B_d, *C_d;
    hipMalloc((void **)&A_d, N * N * sizeof(float));
    hipMalloc((void **)&B_d, N * N * sizeof(float));
    hipMalloc((void **)&C_d, N * N * sizeof(float));

    // Copy data to GPU
    hipMemcpy(A_d, A, N * N * sizeof(float), hipMemcpyHostToDevice);
    hipMemcpy(B_d, B, N * N * sizeof(float), hipMemcpyHostToDevice);

    // Run Kernel
    dim3 numThreadsPerBlock(32, 32);
    dim3 numBlocks((N + numThreadsPerBlock.x - 1) / numThreadsPerBlock.x, (N + numThreadsPerBlock.y - 1) / numThreadsPerBlock.y);

    //////////////////////////////////////
    hipEventRecord(start);
    matmul_kernel<<<numBlocks, numThreadsPerBlock>>>(A_d, B_d, C_d, N);
    hipDeviceSynchronize();
    hipEventRecord(stop);
    hipEventSynchronize(stop);
    //////////////////////////////////////

    float ms;
    hipEventElapsedTime(&ms, start, stop);
    std::cout << "Total GPU Kernel time: " << ms << "ms\n";

    // Copy data from GPU
    hipMemcpy(C, C_d, N * N * sizeof(float), hipMemcpyDeviceToHost);

    // Deallocate memory on GPU
    hipFree(A_d);
    hipFree(B_d);
    hipFree(C_d);
}

int main(int argc, char **argv)
{
    hipDeviceSynchronize();

    // ######################### Allocate memory & initialize data #########################

    // Declare the host arrays
    unsigned int N = (argc > 1) ? atoi(argv[1]) : (1024);
    float *A = (float*)malloc(N * N * sizeof(float));
    float *B = (float*)malloc(N * N * sizeof(float));
    float *C = (float*)malloc(N * N * sizeof(float));

    // Generate Random Numbers
    std::random_device entropy_source;
    std::mt19937_64 generator(entropy_source());
    std::uniform_real_distribution<float> dist(-10.0, 10.0);

    // Initialize the arrays
    for (int i = 0; i < N*N; i++)
    {
        A[i] = dist(generator);
        B[i] = dist(generator);
    }
    // printArr(A, N * N);
    // printArr(B, N * N);

    // ######################### matrix multiplication on CPU #########################

    high_resolution_clock::time_point start_cpu;
    high_resolution_clock::time_point end_cpu;
    duration<double, std::milli> duration_sec;

    //////////////////////////////////////
    start_cpu = high_resolution_clock::now(); // Get the starting timestamp
    matmul_cpu(A, B, C, N);
    end_cpu = high_resolution_clock::now(); // Get the ending timestamp
    //////////////////////////////////////

    duration_sec = std::chrono::duration_cast<duration<double, std::milli>>(end_cpu - start_cpu);
    std::cout << "Total CPU time: " << duration_sec.count() << "ms\n";

    // ######################### matrix multiplication on GPU #########################
    hipEvent_t start_gpu;
    hipEvent_t stop_gpu;
    hipEventCreate(&start_gpu);
    hipEventCreate(&stop_gpu);

    //////////////////////////////////////
    hipEventRecord(start_gpu);
    matmul_gpu(A, B, C, N);
    hipEventRecord(stop_gpu);
    hipEventSynchronize(stop_gpu);
    //////////////////////////////////////

    // Get the elapsed time in milliseconds
    float ms;
    hipEventElapsedTime(&ms, start_gpu, stop_gpu);
    std::cout << "Total GPU time: " << ms << "ms\n";

    // free host memory
    free(A);
    free(B);
    free(C);

    return 0;
}
