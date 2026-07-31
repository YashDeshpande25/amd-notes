# Martin's Fork/Branch of LLVM: Translation Cache

- **Author:** Yash Deshpande
- **Date:** 31-07-2026
- **Model:** Claude Opus 5

## What is the cache, and where is it stored?

The cache is a content-addressed on-disk store of already-translated code
objects, implemented in `amd/comgr/src/hotswap/translation-cache.{h,cpp}` (957
lines). Its job is to skip the whole raise -> opt -> codegen -> link pipeline
when the same input has already been translated under the same options. COMGR
drives it; the hotswap library's `runPipeline` never sees it.

### Location

The root is whatever the caller passes, and nothing more:

```cpp
std::string cacheRoot(const TranslationCacheRequest &request) {
  return request.CacheDirectory;
}

bool cacheDisabledByPolicy(const TranslationCacheRequest &request) {
  return request.CacheDisabled || cacheRoot(request).empty();
}
```

There is **no default location**. An empty `CacheDirectory` disables the cache
outright, which is why an unconfigured run reports `cache_lookup=disabled`.
Supply it with `HSA_HOTSWAP_CACHE_DIR` for the CLI, or `options.cache_directory`
through the API. Nothing is ever created implicitly in `~/.cache` or `/tmp`.

Directories are created lazily on write, sharded by the first two hex characters
of the key:

```text
<root>/<key[0:2]>/<key>.Hsaco     the translated code object
<root>/<key[0:2]>/<key>.json      metadata
```

A real entry:

```text
dc/dc6df852efce4e93028a0e95d806362de57e688c4788337a09d2e7b740e7bfd4.Hsaco   4064 bytes
dc/dc6df852efce4e93028a0e95d806362de57e688c4788337a09d2e7b740e7bfd4.json    1382 bytes
```

Both files are written atomically, and if the metadata write fails the object is
removed, so there are no half-written entries.

### What is actually stored

The `.Hsaco` is the **final, fully linked output** — not an intermediate, not
IR, not a partial artifact. Verified: the entry left behind by a lit run is
byte-identical to a freshly transpiled object, and it is a loadable ELF on its
own.

```text
Type:    DYN (Shared object file)
Machine: EM_AMDGPU
Flags:   0x54c, gfx942, xnack, sramecc

0000000000001500 g  F .text    .protected vecadd
00000000000004c0 g  O .rodata  vecadd.kd
```

Both the kernel code and its descriptor are present, so a cached file can be
`hipModuleLoad`ed straight out of the cache directory.

On a hit, `hotswapTranspileWithResolvedOptions` does
`Pipeline = std::move(Lookup.Result)` and never calls `runPipeline` — so
`raiseToIR`, the opt pipeline, codegen, and LLD are all skipped, and the cached
bytes are returned as though just produced.

Two properties keep that safe:

- **Integrity.** The `.json` records `cached_object_sha256` and
  `cached_object_size`, so the object is verified on read. A corrupted `.Hsaco`
  yields `Invalid`, which is a hard error rather than a silent re-translate.
- **Build identity.** The key includes `hotswap_build_identity`, which hashes
  `libamd_comgr.so` itself (llvm version, path, size, mtime, sha256). Rebuilding
  the library makes every existing entry unreachable, so an object built by a
  different translator version can never be served.

The cache must also carry the result metadata that the ELF cannot express —
`lifted_count` / `total_count`, `scaled_dispatch_factor`,
`uses_scratch_private_segment`, `source_private_segment_fixed_size`,
`c5_suppressed_count`, `kernel_names`. Without those in the `.json` a hit could
not reconstruct the full `PipelineResult`, and the caller would lose information
a fresh translation would have provided.
