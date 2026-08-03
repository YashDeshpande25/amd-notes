# Martin's Fork/Branch of LLVM: Implementation

- **Author:** Yash Deshpande
- **Date:** 30-07-2026
- **Model:** Claude Opus 5

Notes on the hotswap transpiler in `martin-luecke/llvm-project`, branch `hotswap`
(tracked locally as `hotswap-martin`).

## COMGR entry point

The public API is `amd_comgr_hotswap_transpile_with_options_v2`, which resolves
its options and calls `hotswapTranspileWithResolvedOptions` in
`amd/comgr/src/comgr-hotswap-transpile.cpp`. That function is COMGR's side of
the boundary: it validates, manages the translation cache, and marshals results,
then hands off to the hotswap library exactly once.

### 1. Validate the input

Two gates, both returning `INVALID_ARGUMENT`:

```cpp
DataObject *InputP = DataObject::convert(input);
if (!InputP || !InputP->Data ||
    InputP->DataKind != AMD_COMGR_DATA_KIND_EXECUTABLE || !source_isa_name ||
    !target_isa_name || !output)
  return AMD_COMGR_STATUS_ERROR_INVALID_ARGUMENT;
```

This single condition is what the lit test's `--zero-size` (no data) and
`--wrong-kind` (kind is `BC` rather than `EXECUTABLE`) cases trip.

Both ISA strings then go through `parseTargetIdentifier`, the same parser the
byte-level `amd_comgr_hotswap_rewrite` uses, so the two entry points share one
public contract.

What is deliberately *not* checked: the processor name. Per the comment,
"hotswap decides per-kernel whether the source/target pair is supported", so
something like `gfx9999` parses fine here and surfaces later as a pipeline
failure rather than an invalid argument.

### 2. Build the cache request

Everything that can affect the output is packed into a
`TranslationCacheRequest`:

- source and target gfx (`SourceIdent.Processor`, `TargetIdent.Processor`)
- both full ISA strings
- `HotswapRulesPath`, `CacheDirectory`, `CacheSkipKernels`
- `KernelName`
- `StrictMode`
- `AssumeHipGlobalOffsetZero`
- `CacheDisabled` (explicit disable **or** empty cache directory)
- `CacheReadonly`
- `OptLevel`

This struct is the cache key material. See
[`4_translation-cache.md`](4_translation-cache.md) for what the cache does with it.

### 3. Enumerate kernels

If the caller named a kernel, that name is the entire list. Otherwise
`COMGR::hotswap::listKernelNames(InputBuf)` reads the kernel names out of the
code object's metadata (this is the `listKernelsSeconds` timing stage).

Either way, the resulting list is checked against the skip list via
`skippedKernelForTranslationCache`. A non-empty result means the cache is
bypassed entirely for this request.

### 4. Consult the cache, before doing any work

Three outcomes:

- **Skip-listed** -> status `Bypassed`, no lookup at all.
- **`Invalid`** -> returns `AMD_COMGR_STATUS_ERROR` immediately. Cache corruption
  is a hard failure, not a quiet fallback to recompiling.
- **`Hit`** -> `Pipeline = std::move(Lookup.Result)` and `CacheHit = true`. The
  entire translation is skipped, which is why a hit reports
  `cache_write=not_attempted`.

See [`4_translation-cache.md`](4_translation-cache.md) for what a hit actually
returns and how integrity is verified on read.

### 5. Hand off to the hotswap library

Only reached when there was no hit. It sets the process-global strict flag with
an RAII guard, translates `CacheRequest` fields into `PipelineOptions`, and makes
the one call into hotswap:

```cpp
if (!CacheRequest.KernelName.empty()) {
  Pipeline = COMGR::hotswap::runPipeline(InputBuf,
                                         SourceIdent.Processor,
                                         TargetIdent.Processor,
                                         CacheRequest.KernelName,
                                         PipelineOptions);
} else {
  Pipeline = COMGR::hotswap::runPipelineAllKernels(
      InputBuf, SourceIdent.Processor, TargetIdent.Processor,
      PipelineOptions);
}
```

Note it passes `SourceIdent.Processor` — the bare `gfx950`, not the full triple.
The triple only mattered for validation and cache keying.

This is the boundary. Everything past this point — `raiseToIR` per kernel, the
opt pipeline, `emitCodeGen`, `lld::lldMain` — happens inside that call.

| Function | Declared in | Implemented in |
| --- | --- | --- |
| `runPipeline`, `runPipelineAllKernels` | `amd/comgr/src/hotswap/pipeline.h` | `amd/comgr/src/hotswap/pipeline.cpp` |



### 6. Check the result

If `!Pipeline.Success` or the HSACO is empty, it fills the result object with
`pipelineFailReason` / `pipelineFailDetail` and returns
`AMD_COMGR_STATUS_ERROR`. Importantly the result object is still populated on
failure, which is how the lit test can assert
`success=0 kernel_name=definitely_not_vecadd` on an error path.

### 7. Write the cache

Only when it was a genuine `Miss` — not a hit, not bypassed. A `WriteFailed` is
also a hard error, matching the lookup-side strictness.

See [`4_translation-cache.md`](4_translation-cache.md) for the on-disk layout and the
atomic write behaviour.

### 8. Produce the output

`createExecutableData` wraps the HSACO bytes into a new `amd_comgr_data_t` of
kind `EXECUTABLE`, `fillResult` records the typed metadata, and it returns
`SUCCESS`.

## Flow summary

```text
validate -> build cache key -> list kernels -> cache lookup
                                                |- hit  -> reuse, skip translation
                                                |- miss -> runPipeline[AllKernels]  <- hotswap library
                                                           -> check success
                                                           -> cache write
                                                           -> wrap output
```

COMGR drives the cache and the pipeline never consults it: `runPipeline` and
`runPipelineAllKernels` take no cache arguments.

## Hotswap Library Entry Point

The translation entry point is a pair, chosen by whether a kernel was named:

- `runPipeline(InputBuf, sourceGfx, targetGfx, kernelName, options)` — one named
  kernel.
- `runPipelineAllKernels(InputBuf, sourceGfx, targetGfx, options)` — every
  kernel, relinked into a complete object.

Both are declared in `hotswap/pipeline.h`, and one of them is called exactly once
per request. That is the boundary where `raiseToIR`, the opt pipeline,
`emitCodeGen`, and `lld::lldMain` all live.