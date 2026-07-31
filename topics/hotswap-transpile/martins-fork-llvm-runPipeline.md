# Martin's Fork/Branch of LLVM: runPipeline

- **Author:** Yash Deshpande
- **Date:** 31-07-2026
- **Model:** Claude Opus 5

## Where they live

| Function | Declared in | Implemented in |
| --- | --- | --- |
| `runPipeline`, `runPipelineAllKernels` | `amd/comgr/src/hotswap/pipeline.h` | `amd/comgr/src/hotswap/pipeline.cpp` |
| `runPipelineImpl` | `amd/comgr/src/hotswap/pipeline.cpp` (`static`, no header) | `amd/comgr/src/hotswap/pipeline.cpp` |

## What is the difference between `runPipeline` and `runPipelineAllKernels`?

The only difference is **how the kernel list is obtained**. Everything after that
is identical, because both call the same `runPipelineImpl` with a list of names.

`runPipeline` takes the name from you and wraps it in a one-element list:

```cpp
llvm::SmallVector<std::string> KernelNames{KernelName.str()};
return runPipelineImpl(CodeObjectData, SourceISA, TargetISA, KernelNames,
                       Options, TotalStart, PipelineResult{});
```

`runPipelineAllKernels` discovers the list by reading the code object's metadata,
and fails early with a diagnostic if there are none:

```cpp
llvm::Expected<llvm::SmallVector<std::string>> KernelNamesOrErr =
    listKernelNames(CodeObjectData);
...
if (KernelNamesOrErr->empty()) {
  llvm::errs() << "transpiler: No kernels found in code object\n";
  return finishEarly();
}
```

So `runPipeline` is a one-line adapter, while `runPipelineAllKernels` adds a
metadata-enumeration step (charged to `listKernelsSeconds`) plus two early-exit
paths.

But the consequence for the output is significant. `runPipelineImpl` loops over
whatever names it was given, compiles each to `k<N>.o`, and links **only those
objects** into `merged.Hsaco`. Nothing carries over kernels that were not in the
list, so on a multi-kernel input `runPipeline("foo")` yields a code object
containing only `foo` — the others are absent, not passed through untouched.

## `runPipelineImpl` step by step

This is the function that actually turns one code object into another; everything
above it just decides *which* kernels to hand it.

### 1. Extract the whole `.text` into memory, once

```cpp
llvm::Expected<TextSection> TextOrErr = extractTextSection(CodeObjectData);
```

A code object is an ELF file — a container with several sections. The executable
instructions live in `.text`. This step extracts those raw bytes, along with the
address they were linked at and a list of the other sections (needed later so
PC-relative loads can be resolved). If the input is not a valid code object, this
fails and the whole call returns unsuccessfully.

This happens **once** per request, before the per-kernel loop, and the buffer it
returns holds the machine code for **every** kernel in the object. The per-kernel
steps below do not re-read the input or split it up; they just index into this
one shared in-memory buffer.

### 2. Create a scratch directory

```cpp
DumpDir TmpDir;
```

The pipeline needs somewhere to put intermediate files. `DumpDir` makes a unique
temp directory and **deletes it in its destructor** — unless
`HSA_HOTSWAP_DUMP_DIR` is set, in which case it is marked persistent and
survives. That single flag is what turns the debug dumps on: the files are always
written to disk, they just normally get thrown away.

### 3. Optionally save a copy of the input

With `HSA_HOTSWAP_DUMP_INPUT=1`, the original bytes are written to `input.co` so
the input can be compared against the output later.

### 4. Translate each kernel, one at a time

```cpp
for (size_t I = 0; I < KernelNames.size(); ++I) {
  std::string ObjPath = TmpDir.filePath("k" + llvm::Twine(I) + ".o");
  if (!raiseAndCompileKernel(...)) {
    Result.Success = false;
    return finish();
  }
  ObjPaths.push_back(std::move(ObjPath));
}
```

Each kernel becomes one **relocatable object file** — `k0.o`, `k1.o`, and so on.
Note the `return` inside the loop: this is **all-or-nothing**. One kernel that
cannot be translated fails the entire request, and the kernels already compiled
are discarded.

What happens inside `raiseAndCompileKernel` for a single kernel:

- **Read the kernel's metadata** (`extractKernelMeta`) — argument sizes, offsets,
  kinds. If missing, it warns and continues with empty metadata rather than
  failing.
- **Locate the kernel in `.text`** (`findKernelSymbolExtent`) — its byte offset
  and length, since `.text` may hold many kernels. This one *is* fatal if it
  fails.
- **List all function extents** (`listTextFunctionExtents`), best-effort, so the
  raiser can follow a tail call into a helper function outside this kernel's own
  range.
- **Lift the machine code to LLVM IR** (`raiseToIR`). This is the interesting
  part — decoding instructions and rebuilding equivalent IR. On failure it
  unpacks a structured `RaiseFailure` carrying the exact mnemonic, offset, and
  reason into the result.
- **Accumulate bookkeeping**: `LiftedCount` / `TotalCount` (the
  `lifted=23 total=23` line), plus contract flags like `ScaledDispatchFactor`,
  `UsesScratchPrivateSegment`, and `C5SuppressedCount`.
- **Pick a safe filename** (`makeSafeBasename`) — real kernel names from Tensile
  routinely exceed the 255-byte filesystem limit, so the name is hashed and
  truncated for the dump files only; the IR keeps the full symbol.
- **Dump `.ll` and `.dis`** if the directory is persistent. The `.ll` is written
  here, *before* optimization.
- **Build a `TargetMachine` for the target ISA**, set the module's data layout,
  and run the optimization pipeline.
- **Lower any switches to branches** if the kernel had computed jumps
  (`HasEnumeratedSetpcDispatch`), then verify none remain.
- **Clone the module** if a `.s` dump is wanted, because codegen consumes it.
- **Generate the object code** in memory and write it to `k<N>.o`, then
  optionally emit the `.s`.

Two things worth making explicit, because the file naming invites the opposite
reading:

- The offset and length from `findKernelSymbolExtent` point into the **shared
  in-memory `.text`** extracted in step 1. No per-kernel file is carved out of
  the input first.
- `k<N>.o` is written **exactly once**, at the end, as output — it is the only
  write to `ObjPath` in the whole file. So the `.o` is already target-ISA code
  the moment it appears, and no transformation ever operates on a `.o`; every
  transformation happens on the in-memory `llvm::Module`. The dumps confirm it:
  `k0.o` is `gfx942` though the input was `gfx950`, and it is type `REL`
  (relocatable, not loadable alone) until linking produces the `DYN` object.

### 5. Link the objects together

```cpp
std::string HsacoPath = TmpDir.filePath("merged.Hsaco");
if (llvm::Error Err = linkObjects(ObjPaths, HsacoPath)) {
```

The per-kernel `.o` files are separate pieces; linking combines them into one
loadable code object, called an **HSACO**. This calls LLD in-process. Only the
objects in `ObjPaths` go in — which is why a single-kernel request produces an
object containing only that kernel.

### 6. Read the result back

The linker wrote a file, so it is read into memory as `Result.Hsaco`. An empty or
unreadable file is treated as failure.

### 7. Collect final metadata

`collectTargetPrivateSegmentMetadata` inspects the finished object to record
scratch-memory facts about the target build.

### 8. Mark success

Sets `Result.Success = true`, stamps the total elapsed time, and returns. Note
that `Success` starts out `false` and is only set here at the very end — so every
early return is automatically a failure.

## Flow summary

```text
extract .text
  -> make temp dir (kept only if HSA_HOTSWAP_DUMP_DIR)
  -> for each kernel:
        metadata -> locate in .text -> raiseToIR -> opt -> codegen -> k<N>.o
        (any failure aborts everything)
  -> link all k<N>.o -> merged.Hsaco
  -> read it back
  -> collect metadata
  -> Success = true
```

The pattern worth internalising: **per-kernel work produces object files, then
one link produces the final result.** That is the same structure as an ordinary
compiler — compile each translation unit, then link — except the "source" is
machine code from another GPU instead of C++.
