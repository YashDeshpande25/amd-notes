# Martin's Fork/Branch of LLVM: Build & Validate

Build and validation walkthrough for the hotswap transpiler in
`martin-luecke/llvm-project`, branch `hotswap` (tracked locally as
`hotswap-martin`).

## 1. Configure

Repo state: on branch `hotswap-martin`.

```bash
cd /home/ydeshpan/my_repos/llvm-project
```

Create the dated build directory:

```bash
mkdir -p /home/ydeshpan/my_repos/llvm-project-builds/2026-07-30
```

Configure:

```bash
cmake -S llvm -B /home/ydeshpan/my_repos/llvm-project-builds/2026-07-30 -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD="X86;AMDGPU" \
  -DLLVM_EXTERNAL_PROJECTS="device-libs;comgr" \
  -DLLVM_EXTERNAL_DEVICE_LIBS_SOURCE_DIR=$PWD/amd/device-libs \
  -DLLVM_EXTERNAL_COMGR_SOURCE_DIR=$PWD/amd/comgr \
  -DCOMGR_ENABLE_HOTSWAP_TRANSPILE=ON \
  -DBUILD_TESTING=ON \
  -DLLVM_USE_LINKER=lld \
  -DLLVM_CCACHE_BUILD=ON
```

## 2. Build

Note: there is no `llvm-lit` target — `bin/llvm-lit` is generated at configure
time, so including it in the target list fails with
`ninja: error: unknown target 'llvm-lit'`.

```bash
cd /home/ydeshpan/my_repos/llvm-project-builds/2026-07-30

cmake --build . --parallel 96 --target \
  hotswap-transpiler amd_comgr hotswap-transpile raise_cli \
  FileCheck llc llvm-mc lld llvm-readelf llvm-objdump
```

## 3. In-tree smoke test

```bash
./bin/llvm-lit -v tools/comgr/test-lit/hotswap-transpile.c
```

Output:

```text
-- Testing: 1 tests, 1 workers --
PASS: Comgr :: hotswap-transpile.c (1 of 1)

Testing Time: 3.91s

Total Discovered Tests: 1
  Passed: 1 (100.00%)
```

The input code object is the checked-in `amd/comgr/test-lit/vecadd_gfx950.co`, a
real gfx950 code object. The test runs it through `hotswap-transpile` (which
calls COMGR's `amd_comgr_hotswap_transpile*`, which calls the hotswap library)
and writes a new gfx942 object.

Where it lands: lit's per-test temp prefix `%t` expands to
`<build-dir>/tools/comgr/test-lit/Output/hotswap-transpile.c.tmp`, so
`--output=%t.gfx942.co` becomes:

```text
/home/ydeshpan/my_repos/llvm-project-builds/2026-07-30/tools/comgr/test-lit/Output/hotswap-transpile.c.tmp.gfx942.co
```

## 4. What do we really build?

`amd_comgr` is in the target list, so the build relinks the shared library. It
lands at the build root's `lib/`:

```text
<build-dir>/lib/libamd_comgr.so.3.3.0   171,052,528 bytes   <- the real library
<build-dir>/lib/libamd_comgr.so.3       symlink (21 bytes)
<build-dir>/lib/libamd_comgr.so         symlink (17 bytes)
```

**The hotswap code is inside that `.so`, not a separate library.**

Confirm the entry points made it in:

```bash
nm -D --defined-only <build-dir>/lib/libamd_comgr.so | grep hotswap_transpile
```

Output:

```text
00000000038c9d50 T amd_comgr_destroy_hotswap_transpile_result@@amd_comgr_3.2
00000000038d3890 T amd_comgr_hotswap_transpile@@amd_comgr_3.2
00000000038c9ef0 T amd_comgr_hotswap_transpile_result_get_info@@amd_comgr_3.2
00000000038c9fb0 T amd_comgr_hotswap_transpile_result_get_string@@amd_comgr_3.2
00000000038d2d40 T amd_comgr_hotswap_transpile_with_options@@amd_comgr_3.2
00000000038d39b0 T amd_comgr_hotswap_transpile_with_options_v2@@amd_comgr_3.2
```

This confirms the library really was built with hotswap enabled — it is the
check the README recommends, and all six public hotswap entry points are present
and callable.

## 5. Offline (CPU-only) generation of transpiled code objects

```bash
BD=/home/ydeshpan/my_repos/llvm-project-builds/2026-07-30
$BD/tools/comgr/test-lit/hotswap-transpile \
  /path/to/input_gfx950.co \
  amdgcn-amd-amdhsa--gfx950 \
  amdgcn-amd-amdhsa--gfx942 \
  --output=/path/to/output_gfx942.co \
  | tee path/to/log
```

Output:

```text
transpiler: Kernel 'vecadd' kernarg_segment_size=288
RESULT_INFO: success=1 cache_hit=0 cache_lookup=disabled cache_write=not_attempted source_gfx=gfx950 target_gfx=gfx942 kernel_name= lifted=23 total=23 cache_key=
RESULT: SUCCESS bytes=4064
```

Read the `RESULT_INFO` line for the real verdict — `lifted=N total=N` is the one
to watch. Equal values mean every instruction was translated; `lifted` short of
`total` means partial coverage even when the call reports success.

## 6. How do I generate input/output assembly?

The pipeline has a built-in dump facility, and it emits real assembly, not just a
disassembly listing. Set `HSA_HOTSWAP_DUMP_DIR` and it keeps every intermediate
instead of deleting its temp directory:

```bash
BD=/home/ydeshpan/my_repos/llvm-project-builds/2026-07-30
SRC=/home/ydeshpan/my_repos/llvm-project

env HSA_HOTSWAP_DUMP_DIR=$BD/optionA/dumps HSA_HOTSWAP_DUMP_INPUT=1 \
  $BD/tools/comgr/test-lit/hotswap-transpile \
  $SRC/amd/comgr/test-lit/vecadd_gfx950.co \
  amdgcn-amd-amdhsa--gfx950 amdgcn-amd-amdhsa--gfx942 \
  --output=$BD/optionA/vecadd_gfx942.co
```

It creates a unique subdirectory per invocation (so parallel runs do not
collide) containing:

| File | Size | Contents |
| --- | --- | --- |
| `vecadd.s` | 4,419 B | **Target gfx942 assembly** |
| `vecadd.ll` | 17,089 B | Raised LLVM IR |
| `vecadd.dis` | 916 B | Source gfx950 disassembly |
| `k0.o` | 2,920 B | Per-kernel relocatable |
| `merged.Hsaco` | 4,064 B | Final linked code object |
| `input.co` | 5,648 B | Copy of the input (needs `HSA_HOTSWAP_DUMP_INPUT=1`) |

Reading `.dis` next to `.s` is the cleanest way to see what translation did to a
given kernel, and `.ll` sits in between if you need to see why.

There is an asymmetry though: `.s` for the output is assembler-ready source,
while `.dis` for the input is a bare listing — byte offsets and mnemonics, no
directives, no metadata, no labels.
