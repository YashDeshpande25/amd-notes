# CUDA to HIP, and Extracting a Raw Code Object

- **Author:** Yash Deshpande
- **Date:** 31-07-2026
- **Model:** Claude Opus 5

Porting `matmul.cu` to HIP, running it on gfx942, and pulling a raw `.hsaco` out
of the HIP source so it can be fed to the hotswap transpiler.

For building the transpiler itself and translating the in-tree `vecadd` fixture,
see `topics/hotswap-transpile/martins-fork-llvm-build-and-validate.md`.

Machine: AMD Instinct MI300X, `gfx942:sramecc+:xnack-`, ROCm 7.2.1.

## 1. The port

`matmul.hip` is a one-to-one translation of `matmul.cu`. The kernel body, the
32x32 block shape, the CPU reference, and the timing structure are unchanged.
Only the runtime API names differ:

| CUDA | HIP |
| --- | --- |
| `#include <cuda.h>` | `#include <hip/hip_runtime.h>` |
| `cudaEvent_t` | `hipEvent_t` |
| `cudaEventCreate` / `Record` / `Synchronize` / `ElapsedTime` | `hipEventCreate` / `Record` / `Synchronize` / `ElapsedTime` |
| `cudaMalloc`, `cudaMemcpy`, `cudaFree` | `hipMalloc`, `hipMemcpy`, `hipFree` |
| `cudaMemcpyHostToDevice` / `DeviceToHost` | `hipMemcpyHostToDevice` / `DeviceToHost` |
| `cudaDeviceSynchronize` | `hipDeviceSynchronize` |

What does **not** change: `__global__`, `dim3`, `blockIdx` / `blockDim` /
`threadIdx`, and the `<<<blocks, threads>>>` launch syntax. HIP supports the
triple-chevron launch directly, so the kernel and its launch line are copied
verbatim.

One addition was needed: `#include <cstdlib>`, because `atoi`, `malloc`, and
`free` were previously arriving transitively through `<cuda.h>`.

## 2. Build and run

```bash
hipcc -O2 --offload-arch=gfx942 matmul.hip -o matmul_hip
./matmul_hip 512
```

```text
Total CPU time: 285.918ms
Total GPU Kernel time: 0.856827ms
Total GPU time: 23.4541ms
```

`--offload-arch` accepts repeats (`--offload-arch=gfx942 --offload-arch=gfx90a`)
for a multi-arch binary, or can be omitted so hipcc targets whatever GPU is
present at build time.

Two inherited quirks, both from the original `.cu` rather than the port:

- The compiler emits `nodiscard` warnings on every unchecked `hipError_t`. HIP
  marks those returns as must-check; CUDA does not. Harmless, but an error-check
  macro would silence them and catch real failures.
- `matmul_gpu` writes into the same `C` the CPU just filled and never compares
  the two, so the program times both paths but validates neither. A separate
  `C_gpu` buffer plus a diff would fix it.

## 3. Getting a raw code object

This takes **two** steps. `hipcc --genco` does not produce an ELF — it produces a
`__CLANG_OFFLOAD_BUNDLE__`, which `llvm-readelf` rejects with
`The file was not recognized as a valid object file`. The bundle must be
unbundled.

```bash
# 1. device-only compile -> offload bundle
hipcc --genco --offload-arch=gfx942 matmul.hip -o matmul_gfx942.co

# 2. extract the raw code object from the bundle
/opt/rocm/llvm/bin/clang-offload-bundler --type=o --unbundle \
  --targets=hipv4-amdgcn-amd-amdhsa--gfx942 \
  --input=matmul_gfx942.co --output=matmul_gfx942.hsaco
```

Two things that bite:

- **`clang-offload-bundler` is not on `PATH`.** It ships with ROCm at
  `/opt/rocm/llvm/bin/`.
- **The `--targets` string must match the bundle exactly**, including the
  `hipv4-` prefix, which is easy to omit.

List the entries if unsure:

```bash
/opt/rocm/llvm/bin/clang-offload-bundler --type=o --list --input=matmul_gfx942.co
```

```text
hipv4-amdgcn-amd-amdhsa--gfx942
host-x86_64-unknown-linux-gnu-
```

`--genco` only needs *compiler* support for the target, not the hardware, so a
gfx1250 code object can be produced on this gfx942 machine.

### `.co` vs `.hsaco` is a naming convention, not a format

No tool dispatches on the extension. The hotswap README's smoke test uses
`amd/comgr/test-lit/vecadd_gfx950.co`, and that file *is* a raw ELF — it is only
our `--genco` output that is a bundle. Three files, same directory, two formats:

| File | Magic | Actually is |
| --- | --- | --- |
| `amd/comgr/test-lit/vecadd_gfx950.co` | `ELF` | Raw AMDGPU code object |
| `gfx942/matmul_gfx942.co` | `__CLANG_OFFLOAD_BUNDLE__` | Bundle |
| `gfx942/matmul_gfx942.hsaco` | `ELF` | Raw AMDGPU code object |

The wrapping is a property of `--genco`, not of the `.co` name: `--genco` exists
to hold several architectures plus a host entry in one file, and it wraps even
for a single target. Writing `-o matmul.hsaco` would produce a bundle called
`.hsaco`. It works the other way too — `hotswap-transpile --output=` always
writes a raw ELF whatever you name it.

Check the content, not the name:

```bash
file <path>        # "ELF 64-bit LSB shared object, AMD GPU architecture" vs "data"
head -c 24 <path>  # ELF magic vs __CLANG_OFFLOAD_BUNDLE__
```

Rough convention in practice: `.hsaco` almost always means a raw code object,
`.co` is used for both, and bundles are what compiler drivers emit.
`llvm-readelf -h` failing with "not recognized as a valid object file" is the
signal to unbundle.

## 4. Verify the result

```bash
llvm-readelf -h matmul_gfx942.hsaco
```

```text
OS/ABI:       AMDGPU - HSA
ABI Version:  4
Type:         DYN (Shared object file)
Machine:      EM_AMDGPU
Flags:        0x54c, gfx942, xnack, sramecc
```

```bash
llvm-objdump --syms matmul_gfx942.hsaco
```

```text
0000000000001900 g  F .text    .protected _Z13matmul_kernelPfS_S_j
00000000000008c0 g  O .rodata  .protected _Z13matmul_kernelPfS_S_j.kd
```

Note the **C++ mangled name**, `_Z13matmul_kernelPfS_S_j`. Unlike the OpenCL-built
`vecadd` fixture, this kernel is not `extern "C"`, so that mangled string is what
`HSA_HOTSWAP_TRANSLATE_KERNEL` and `hipModuleGetFunction` need. Marking the
kernel `extern "C"` gives a clean `matmul_kernel` instead.

Sizes for reference: the bundle is 9,992 bytes, the extracted code object 5,896.

## 5. Generate the assembly file

**Two separate commands are needed** — one for the instructions, one for the
metadata. Neither tool gives both.

### 5a. Instructions (`llvm-objdump`)

```bash
/home/ydeshpan/my_repos/llvm-project-builds/2026-07-30/bin/llvm-objdump \
  -d matmul_gfx942.hsaco > matmul_gfx942.s
```

No `--mcpu` or arch flag is needed — `llvm-objdump` reads the target out of the
ELF header. Use `-D` instead of `-d` to also disassemble `.rodata`, which decodes
the 64-byte kernel descriptor back into a full `.amdhsa_kernel` directive block.

### 5b. Metadata (`llvm-readelf --notes`)

```bash
/home/ydeshpan/my_repos/llvm-project-builds/2026-07-30/bin/llvm-readelf \
  --notes matmul_gfx942.hsaco > matmul_gfx942.meta.yaml
```

The kernel metadata — `amdhsa.kernels`, the `.args` list with offsets and value
kinds, `.wavefront_size`, `amdhsa.target` — is msgpack inside the `.note`
section. `llvm-objdump` has no msgpack decoder: with `-D` it does visit `.note`
but tries to disassemble the bytes as instructions and emits garbage. Only
`llvm-readelf --notes` decodes it.

(A compiler-emitted `.s`, such as the transpiler's `HSA_HOTSWAP_DUMP_DIR` dump,
carries an `.amdgpu_metadata` block because LLVM's AsmPrinter writes it out from
the in-memory module. `llvm-objdump` works the other way round, reconstructing
text from a finished binary, and does not synthesize that block.)

**Use the build-tree `llvm-objdump`, not the one on `PATH`.** `/usr/bin/llvm-objdump`
is Ubuntu LLVM 18.1.3, which predates gfx1250: it handles gfx942 fine but
*segfaults* on a gfx1250 object with a crash backtrace.

Note this produces a **listing**, not reassemblable source — instruction
encodings appear in trailing `//` comments and branch targets are numeric rather
than labels. For assembler-ready `.s`, run the transpiler with
`HSA_HOTSWAP_DUMP_DIR` set; but that emits the assembly of the *translated*
kernel, not of the input.

## 6. Feed it to the transpiler

```bash
BD=/home/ydeshpan/my_repos/llvm-project-builds/2026-07-30
$BD/tools/comgr/test-lit/hotswap-transpile \
  matmul_gfx942.hsaco \
  amdgcn-amd-amdhsa--gfx942 \
  amdgcn-amd-amdhsa--gfx950 \
  --output=/tmp/matmul_gfx950.co
```

```text
transpiler: Kernel '_Z13matmul_kernelPfS_S_j' kernarg_segment_size=288
RESULT_INFO: success=1 cache_hit=0 cache_lookup=disabled cache_write=not_attempted source_gfx=gfx942 target_gfx=gfx950 kernel_name= lifted=42 total=42 cache_key=
RESULT: SUCCESS bytes=4488
```

`lifted=42 total=42` — every instruction translated. This gives a second test
case beyond `vecadd`: 42 instructions with a real loop, versus vecadd's 23
straight-line ones.

## 7. Run a code object with hipModuleLoad

`matmul_hipModuleLoad_code_obj.cpp` loads a matmul code object at runtime,
launches it, and checks the result against a CPU reference. It is host-only
code — no `--offload-arch`, because the device code comes from the file passed
in. The output buffer is pre-poisoned with `0xFF` so a kernel that does nothing
cannot pass as correct.

```bash
hipcc -O2 matmul_hipModuleLoad_code_obj.cpp -o matmul_hipModuleLoad_code_obj
./matmul_hipModuleLoad_code_obj                                  # default: gfx942, N=512
./matmul_hipModuleLoad_code_obj gfx942/matmul_gfx942.hsaco 256
```

```text
device      : AMD Instinct MI300X (gfx942:sramecc+:xnack-)
code object : gfx942/matmul_gfx942.hsaco
kernel      : _Z13matmul_kernelPfS_S_j
N=512  block=32x32  grid=16x16
hipModuleLoad            : ok
hipModuleGetFunction     : ok
hipModuleLaunchKernel    : ok (0.2206 ms)
max abs diff             : 2.28882e-05
VERIFY                   : PASS (0/262144 wrong)
```

Options: `--kernel=<name>` to launch a different symbol (default is the mangled
`_Z13matmul_kernelPfS_S_j`), and `--full-kernarg`, explained below.

### A code object only loads on a matching GPU

The gfx950 and gfx1250 objects fail here, which is the entire premise of
hotswap:

```text
hipModuleLoad failed: no kernel image is available for execution on the device (209)
```

Translate first, then they run. The round trip, gfx950 object to gfx942 and
execute:

```bash
$BD/tools/comgr/test-lit/hotswap-transpile \
  gfx950/matmul_gfx950.hsaco \
  amdgcn-amd-amdhsa--gfx950 amdgcn-amd-amdhsa--gfx942 \
  --output=/tmp/matmul_x942.co

./matmul_hipModuleLoad_code_obj /tmp/matmul_x942.co 256 --full-kernarg
```

```text
hipModuleLaunchKernel    : ok (0.1338 ms)
max abs diff             : 1.52588e-05
VERIFY                   : PASS (0/65536 wrong)
```

A real matmul, translated across architectures, numerically correct on hardware.

### Why `--full-kernarg` is needed for transpiled objects

For a hipcc-built object the metadata declares typed arguments *and* hidden
arguments, so passing the 28-byte explicit struct is enough — HIP fills the
hidden fields at their declared offsets. A hotswap-transpiled object declares a
single opaque 288-byte `by_value` blob and no hidden arguments, so HIP has
nothing to populate. `--full-kernarg` makes the host build all 288 bytes itself,
including block counts, group sizes, and remainders.

### Gotcha

The first positional argument is always the code object path, so
`./matmul_hipModuleLoad_code_obj 256` tries to load a file named `256` and
reports `file not found (301)`. To change only `N`, pass the object path too.

## Files produced

Sources live at the top level; per-architecture artifacts live in `gfx942/`,
`gfx950/`, and `gfx1250/`, each holding the same set produced by the steps above.

| File | What it is |
| --- | --- |
| `matmul.cu` | Original CUDA source |
| `matmul.hip` | HIP port |
| `matmul_hipModuleLoad_code_obj.cpp` | Runtime loader/verifier for a code object |
| `<arch>/matmul_hip` | Host executable |
| `<arch>/matmul_<arch>.co` | Offload **bundle** from `--genco` (not an ELF) |
| `<arch>/matmul_<arch>.hsaco` | Raw code object |
| `<arch>/matmul_<arch>.s` | Disassembly listing |
| `<arch>/verify.txt` | Bundle targets, ELF header, symbol table |

## Next step

The interesting direction for the hotswap branch is **down** from a wave32 part:
build with `--offload-arch=gfx1250` and translate to gfx942. That exercises the
wave32 to wave64 cross-widening — wave projection, the C5 predicate-chain
classifier, and WMMA lowering — which a gfx942 to gfx950 pair (both wave64)
never touches.
