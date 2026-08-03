// Author : Yash Deshpande
// Date : 31-07-2026
// Loads a matmul code object with hipModuleLoad and runs it on the GPU,
// checking the result against a CPU reference.
//
// ###############################################################################
// Compile : hipcc -O2 matmul_hipModuleLoad_code_obj.cpp -o matmul_hipModuleLoad_code_obj
// Execute : ./matmul_hipModuleLoad_code_obj [code-object] [N]
//
//   code-object  path to a matmul .hsaco (default: gfx942/matmul_gfx942.hsaco)
//   N            matrix dimension        (default: 512)
//
// The code object must contain the matmul kernel from matmul.hip; the host
// side here builds its argument buffer to that kernel's signature.
//
// Examples:
//   ./matmul_hipModuleLoad_code_obj
//   ./matmul_hipModuleLoad_code_obj gfx950/matmul_gfx950.hsaco
//   ./matmul_hipModuleLoad_code_obj gfx1250/matmul_gfx1250.hsaco 256
//
// Options:
//   --kernel=<name>   kernel symbol to launch
//                     (default: _Z13matmul_kernelPfS_S_j, the C++ mangled
//                      name of matmul_kernel in matmul.hip)
//   --full-kernarg    build the entire 288-byte kernarg segment by hand,
//                     including hidden arguments. Needed for hotswap-
//                     transpiled objects, whose metadata declares one opaque
//                     by_value blob and therefore gives HIP no hidden-argument
//                     offsets to populate. Not needed for hipcc-built objects.
//
// Note: a code object only loads on a matching GPU. On a gfx942 machine the
// gfx950 and gfx1250 objects fail at hipModuleLoad with
// "no kernel image is available for execution on the device" -- translate them
// to gfx942 with hotswap-transpile first.
// ###############################################################################

#include <hip/hip_runtime.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <string>
#include <vector>

#define CHECK(expr)                                                            \
  do {                                                                         \
    hipError_t err_ = (expr);                                                  \
    if (err_ != hipSuccess) {                                                  \
      std::fprintf(stderr, "%s:%d: %s failed: %s (%d)\n", __FILE__, __LINE__,  \
                   #expr, hipGetErrorString(err_), (int)err_);                 \
      return 1;                                                                \
    }                                                                          \
  } while (0)

// Explicit arguments, matching the kernel's amdhsa.kernels metadata:
//   0 -> float *A, 8 -> float *B, 16 -> float *C, 24 -> unsigned int N
// Hidden arguments start at offset 32 and are filled in by HIP.
struct KernArgs {
  void *A;
  void *B;
  void *C;
  unsigned int N;
};

// Hidden-argument offsets, used only by --full-kernarg.
enum : size_t {
  KERNARG_TOTAL = 288,
  OFF_BLOCK_COUNT_X = 32,
  OFF_GROUP_SIZE_X = 44,
  OFF_REMAINDER_X = 50,
  OFF_GRID_DIMS = 96,
};

template <typename T> static void poke(unsigned char *buf, size_t off, T v) {
  std::memcpy(buf + off, &v, sizeof(T));
}

static void matmul_cpu(const float *A, const float *B, float *C, unsigned int N) {
  for (unsigned int row = 0; row < N; ++row)
    for (unsigned int col = 0; col < N; ++col) {
      float sum = 0.0f;
      for (unsigned int i = 0; i < N; ++i)
        sum += A[row * N + i] * B[i * N + col];
      C[row * N + col] = sum;
    }
}

int main(int argc, char **argv) {
  // Keep stdout in step with stderr so a failure diagnostic appears after the
  // header lines rather than before them when the output is piped.
  setvbuf(stdout, nullptr, _IOLBF, 0);

  const char *coPath = "gfx942/matmul_gfx942.hsaco";
  std::string kernelName = "_Z13matmul_kernelPfS_S_j";
  unsigned int N = 512;
  bool fullKernarg = false;

  int positional = 0;
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    if (arg.rfind("--kernel=", 0) == 0)
      kernelName = arg.substr(9);
    else if (arg == "--full-kernarg")
      fullKernarg = true;
    else if (arg.rfind("--", 0) == 0) {
      std::fprintf(stderr, "unknown option: %s\n", argv[i]);
      return 2;
    } else if (positional++ == 0)
      coPath = argv[i];
    else
      N = (unsigned int)std::atoi(argv[i]);
  }

  const unsigned blockDim = 32; // 32x32 threads, as in matmul.hip
  const unsigned gridDim = (N + blockDim - 1) / blockDim;

  hipDeviceProp_t props;
  CHECK(hipGetDeviceProperties(&props, 0));
  std::printf("device      : %s (%s)\n", props.name, props.gcnArchName);
  std::printf("code object : %s\n", coPath);
  std::printf("kernel      : %s\n", kernelName.c_str());
  std::printf("N=%u  block=%ux%u  grid=%ux%u\n", N, blockDim, blockDim, gridDim,
              gridDim);

  const size_t elems = (size_t)N * N;
  const size_t bytes = elems * sizeof(float);
  std::vector<float> hA(elems), hB(elems), hC(elems), hRef(elems);
  for (size_t i = 0; i < elems; ++i) {
    hA[i] = (float)((i * 7919) % 101) / 101.0f;
    hB[i] = (float)((i * 104729) % 97) / 97.0f;
  }

  float *dA = nullptr, *dB = nullptr, *dC = nullptr;
  CHECK(hipMalloc(&dA, bytes));
  CHECK(hipMalloc(&dB, bytes));
  CHECK(hipMalloc(&dC, bytes));
  CHECK(hipMemcpy(dA, hA.data(), bytes, hipMemcpyHostToDevice));
  CHECK(hipMemcpy(dB, hB.data(), bytes, hipMemcpyHostToDevice));
  // Poison the output so a kernel that does nothing cannot pass as correct.
  CHECK(hipMemset(dC, 0xFF, bytes));

  hipModule_t mod = nullptr;
  hipFunction_t fn = nullptr;
  CHECK(hipModuleLoad(&mod, coPath));
  std::printf("hipModuleLoad            : ok\n");
  CHECK(hipModuleGetFunction(&fn, mod, kernelName.c_str()));
  std::printf("hipModuleGetFunction     : ok\n");

  KernArgs args{dA, dB, dC, N};
  unsigned char rawArgs[KERNARG_TOTAL];
  void *argBuf = &args;
  size_t argSize = sizeof(args);

  if (fullKernarg) {
    std::memset(rawArgs, 0, sizeof(rawArgs));
    std::memcpy(rawArgs, &args, sizeof(args));
    poke<uint32_t>(rawArgs, OFF_BLOCK_COUNT_X, gridDim);
    poke<uint32_t>(rawArgs, OFF_BLOCK_COUNT_X + 4, gridDim);
    poke<uint32_t>(rawArgs, OFF_BLOCK_COUNT_X + 8, 1);
    poke<uint16_t>(rawArgs, OFF_GROUP_SIZE_X, (uint16_t)blockDim);
    poke<uint16_t>(rawArgs, OFF_GROUP_SIZE_X + 2, (uint16_t)blockDim);
    poke<uint16_t>(rawArgs, OFF_GROUP_SIZE_X + 4, 1);
    poke<uint16_t>(rawArgs, OFF_REMAINDER_X, (uint16_t)(N % blockDim));
    poke<uint16_t>(rawArgs, OFF_REMAINDER_X + 2, (uint16_t)(N % blockDim));
    poke<uint16_t>(rawArgs, OFF_GRID_DIMS, 2);
    argBuf = rawArgs;
    argSize = sizeof(rawArgs);
  }

  void *config[] = {HIP_LAUNCH_PARAM_BUFFER_POINTER, argBuf,
                    HIP_LAUNCH_PARAM_BUFFER_SIZE, &argSize,
                    HIP_LAUNCH_PARAM_END};

  hipEvent_t start, stop;
  CHECK(hipEventCreate(&start));
  CHECK(hipEventCreate(&stop));
  CHECK(hipEventRecord(start));
  CHECK(hipModuleLaunchKernel(fn, gridDim, gridDim, 1, blockDim, blockDim, 1, 0,
                              nullptr, nullptr, config));
  CHECK(hipEventRecord(stop));
  CHECK(hipDeviceSynchronize());
  float ms = 0.0f;
  CHECK(hipEventElapsedTime(&ms, start, stop));
  std::printf("hipModuleLaunchKernel    : ok (%.4f ms)\n", ms);

  CHECK(hipMemcpy(hC.data(), dC, bytes, hipMemcpyDeviceToHost));

  matmul_cpu(hA.data(), hB.data(), hRef.data(), N);
  size_t bad = 0;
  float worst = 0.0f;
  for (size_t i = 0; i < elems; ++i) {
    const float diff = std::fabs(hC[i] - hRef[i]);
    const float tol = 1e-3f * std::fmax(1.0f, std::fabs(hRef[i]));
    if (diff > tol) {
      if (bad < 5)
        std::printf("  MISMATCH [%zu] got=%g want=%g\n", i, hC[i], hRef[i]);
      ++bad;
    }
    worst = std::fmax(worst, diff);
  }
  std::printf("max abs diff             : %g\n", worst);
  std::printf("VERIFY                   : %s (%zu/%zu wrong)\n",
              bad ? "FAIL" : "PASS", bad, elems);

  CHECK(hipModuleUnload(mod));
  CHECK(hipFree(dA));
  CHECK(hipFree(dB));
  CHECK(hipFree(dC));
  return bad ? 1 : 0;
}
