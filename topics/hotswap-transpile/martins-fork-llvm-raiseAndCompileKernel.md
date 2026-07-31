# Martin's Fork/Branch of LLVM: raiseAndCompileKernel

- **Author:** Yash Deshpande
- **Date:** 31-07-2026
- **Model:** Claude Opus 5

## Where it lives

| Function | Declared in | Implemented in |
| --- | --- | --- |
| `raiseAndCompileKernel` | `amd/comgr/src/hotswap/pipeline.cpp` (`static`, no header) | `amd/comgr/src/hotswap/pipeline.cpp` |

Called once per kernel from `runPipelineImpl`'s loop. Its contract, from the
comment above it: *"Raise one kernel to IR, then opt + codegen it to a
relocatable `.o`. On success, writes the `.o` to `ObjPath` and returns true."*

It returns a plain `bool`. All the detail about *why* something failed is written
into the shared `PipelineResult &Result` passed by reference, which is how the
caller ends up with a mnemonic and offset to report.

## Step by step

### 1. Read the kernel's metadata

```cpp
llvm::Expected<KernelMeta> MetaOrErr =
    extractKernelMeta(CodeObjectData, KernelName);
```

Argument sizes, offsets, and value kinds from the code object's metadata. This is
**not fatal**: on failure it warns and carries on with empty metadata, and warns a
second time if the argument list came back empty. So a kernel with no usable
metadata still gets attempted.

### 2. Locate the kernel inside `.text`

```cpp
llvm::Expected<KernelSymbolExtent> KernelExtentOrErr =
    findKernelSymbolExtent(CodeObjectData, KernelName);
```

Returns the kernel's byte offset and size within the shared `.text` buffer. This
one **is** fatal, and it records a distinctive failure so it can be told apart
from a translation problem:

```cpp
Result.FailMnemonic = "__kernel_extent__";
Result.FailReason = "KernelSymbolExtentLookupFailed";
```

Note this is an offset and length only — no bytes are copied out.

### 3. List all function extents (best-effort)

```cpp
llvm::SmallVector<KernelSymbolExtent> FunctionExtents;
if (llvm::Expected<llvm::SmallVector<KernelSymbolExtent>> ExtentsOrErr =
        listTextFunctionExtents(CodeObjectData)) {
```

Lets the raiser follow a tail call into an outlined device helper that lives
outside this kernel's own extent. On failure the error is consumed and the list
stays empty, which keeps the stricter in-extent-only behaviour — so this can
degrade silently.

### 4. Lift the machine code to LLVM IR

```cpp
llvm::Expected<RaiseResult> RaisedOrErr = raiseToIR(
    Text.Bytes, SourceISA, KernelName, Meta, KernelOffset, KernelSize,
    TargetISA, Options.EnableWritelaneRewrite, Options.EnableWaveNative,
    Options.AssumeHipGlobalOffsetZero, Options.ForceScaledModrep,
    Text.Address, Text.ImageSections, FunctionExtents, &Stats);
```

The actual translation. Note it receives **both** ISAs — the source to decode
against and the target to lower for — which is what makes cross-family work
possible at all.

**The cross-family translation is finished here, in this step.** `raiseToIR`
makes the semantically hard decisions — wave projection, EXEC modeling,
cross-lane rewrites — because it knows both ISAs. By the time step 8 is reached
you are holding ordinary LLVM IR, and steps 8 through 13 are just a normal `opt`
plus `llc` run that happens to be aimed at a different GPU. That is the design's
whole leverage: express the hard part as IR, then let the existing AMDGPU backend
do the lowering.

On failure, `handleAllErrors` runs one of two handlers:

- A structured `RaiseFailure`, which carries `Mnemonic`, `Reason`, `Format`,
  `Offset` — the precise instruction that could not be translated.
- Any other error, recorded as `InternalError` with the note "raiseToIR returned
  failure without a structured reason". That wording means the raiser is expected
  to always explain itself; hitting this branch is a hotswap bug.

Only the **first** failure is recorded into `Result`; later ones are printed to
stderr but not stored.

### 5. Accumulate results into the shared `PipelineResult`

Because one code object can have many kernels, the per-kernel numbers are merged
rather than overwritten:

- `LiftedCount` / `TotalCount` are summed — this is the `lifted=23 total=23` line.
- `ScaledDispatchFactor` is taken if greater than 1.
- `UsesScratchPrivateSegment` latches to true, and
  `SourcePrivateSegmentFixedSize` keeps the **maximum** across kernels.
- `C5SuppressedCount` is summed; `C5SuppressionReason` keeps the first non-empty
  one.

### 6. Pick a filesystem-safe filename

```cpp
std::string FileStem = makeSafeBasename(KernelName, /*ReservedSuffixBytes=*/5);
```

Kernel names from Tensile routinely exceed 255 bytes, the per-component limit on
ext4, xfs, and tmpfs. This hashes the tail and truncates the head. Only the dump
filenames are affected — the symbol inside the IR keeps the full name, so
debuggers can still resolve it.

### 7. Dump `.ll` and `.dis` (debug only)

```cpp
if (TmpDir.Persistent) {
  writeDebugModule(TmpDir.filePath(FileStem + ".ll"), M);
  if (!Raised.DisasmText.empty())
    writeDebugFile(TmpDir.filePath(FileStem + ".dis"), Raised.DisasmText);
}
```

Two things to keep straight: this runs **before** optimization, so the `.ll` is
the raw raised IR, not what gets compiled. And it only happens when a persistent
dump directory was requested — the production path never serializes IR to text.

### 8. Create the `TargetMachine` and set the data layout

```cpp
createHotswapTargetMachine(TargetISA, Options.OptLevel);
...
M.setDataLayout(TM->createDataLayout());
```

Built for the **target** ISA. From here on it is ordinary LLVM compilation.

### 9. Run the optimization pipeline

```cpp
runOptPipeline(M, *TM, Options.OptLevel);
```

### 10. Lower computed jumps, if the kernel had any

```cpp
if (Raised.HasEnumeratedSetpcDispatch) {
  lowerSwitchesToBranches(M);
  if (llvm::Error Err = checkNoSwitchTerminators(M, KernelName)) {
```

Kernels whose control flow came from an enumerated `s_setpc` dispatch get their
switches lowered to branches, then **verified**: any surviving switch terminator
is a fatal `InternalError`. A belt-and-braces check that the lowering actually
did its job.

### 11. Clone the module if an assembly dump is wanted

```cpp
std::unique_ptr<llvm::Module> AsmModule;
if (TmpDir.Persistent)
  AsmModule = llvm::CloneModule(M);
```

Object codegen consumes the module, so the clone has to be taken before it runs.
This is why the `.s` dump costs an extra full module copy.

### 12. Generate the object code in memory

```cpp
llvm::SmallVector<char, 4096> ObjBytes;
llvm::Error Err = [&] {
  llvm::raw_svector_ostream OS(ObjBytes);
  return emitCodeGen(M, *TM, llvm::CodeGenFileType::ObjectFile, OS);
}();
```

Charged to `llcSeconds`, though nothing is shelled out — this is in-process
codegen.

### 13. Write `k<N>.o`

```cpp
if (llvm::Error WriteErr = writeFile(
        ObjPath, llvm::StringRef(ObjBytes.data(), ObjBytes.size()))) {
```

The **only** write to `ObjPath` anywhere in the file. The `.o` appears exactly
once, already fully translated and already target-ISA.

### 14. Emit `.s` from the clone (debug only)

Best-effort: a failure here is logged but does not fail the kernel. The comment
is explicit that object codegen above stays the canonical lowering, so the `.s`
is a view of the same module rather than the thing that gets linked.

Because it comes from the clone taken in step 11, the `.s` is **post**
optimization while the `.ll` from step 7 is **pre** optimization. They are not
two views of the same IR state.

### 15. Return `true`

## Timing buckets

| Bucket | Covers |
| --- | --- |
| `raiseSeconds` | Steps 1-5 (metadata, extents, `raiseToIR`) |
| `writeIrSeconds` | Step 7 (`.ll` / `.dis` dumps) |
| `optSeconds` | Steps 9-10 (opt pipeline, switch lowering) |
| `llcSeconds` | Step 12 (object codegen) |

## Flow summary

```text
metadata (non-fatal)
  -> locate kernel in .text (fatal)
  -> list function extents (best-effort)
  -> raiseToIR              <- the translation
  -> merge stats into PipelineResult
  -> safe filename
  -> dump .ll / .dis        (pre-opt, debug only)
  -> TargetMachine + data layout
  -> opt pipeline
  -> lower + verify switches (only if enumerated setpc dispatch)
  -> clone module           (debug only)
  -> codegen to memory
  -> write k<N>.o           <- single write
  -> emit .s from clone     (post-opt, debug only)
```
