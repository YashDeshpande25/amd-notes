# Task-2: Understand Alex's Implemenatation of Cross-Family work on amd-staging

- Author: Yash Deshpande
- Date  : 2026-08-03

I asked @Harsh if PR#3536 was the most important one to look into

His reply: 
Looks like its from 3716 to 3721

## What the PRs are and are not doing

The M0 stack builds the **engine, not the car around it**. It is a bottom-up
reconstruction of `raiseToIRImpl`: each PR adds one module that a phase of that
function needs, and the last PR writes the function that stitches them together.

### Landed on amd-staging

| PR | Merged | What |
| --- | --- | --- |
| `#2438` | 2026-05-12 | Bare-bones transpiler scaffolding (tgymnich) |
| `#3536` | 2026-08-03 | Load code-object metadata — M0 step 02 (ftynse) |
| `#3274` | 2026-07-27 | Refactor hotswap files into their own directory (why the README paths are stale) |
| `#3642` | 2026-07-27 | CI labeler for the `src/hotswap` refactor |
| `#3715` | 2026-07-31 | Keep hotswap LLVM deps off `amd_comgr`'s link line |

### The open stack, in dependency order

Each PR's base is the previous one's head branch, so they must be read in order.
All are drafts; only `#3537` targets `amd-staging` directly.

| Order | PR | Step | Size | What |
| --- | --- | --- | --- | --- |
| 1 | `#3537` | m0-03 | +2934/-204 | Canonical-op enum + AMDGPU MC stack |
| 2 | `#3716` | m0-04 | +1012 | Map MC opcodes to canonical ops, decode `.text` |
| 3 | `#3717` | m0-05 | +1481 | The wave projection |
| 4 | `#3718` | m0-06 | +1581 | Raise-failure error type + register file |
| 5 | `#3719` | m0-07 | +1134 | Source kernel-argument ABI layouts |
| 6 | `#3720` | m0-08 | +1648 | Per-kernel raise context |
| 7 | `#3721` | m0-09 | +1882/-106 | Raise a scalar-move kernel to LLVM IR |

Outside the stack, both based on `amd-staging`: `#3671` (on-disk cache for
transpiled code objects, draft) and `#3676` (in-memory single-flight tier for the
translation cache, **not** a draft).

### What they are NOT doing

None of the outer chain exists upstream yet:

- **No public API.** `amd-staging`'s `exportmap.in` lists only
  `amd_comgr_hotswap_rewrite` and `..._rewrite_with_options`. There is no
  `amd_comgr_hotswap_transpile*` symbol at all.
- **No pipeline.** A repo-wide code search for `runPipelineAllKernels` returns
  zero results — no `pipeline.cpp`, no `runPipeline`, no
  `raiseAndCompileKernel`.
- **No option resolution or cache orchestration** (`hotswapTranspileWithResolvedOptions`).

So the upstream chain today is `[nothing] -> [nothing] -> raiseToIR (skeleton)`,
and `raiser.cpp` on `amd-staging` is 3 KB against the fork's 2,697 lines.

`#3721` drives `raiseToIR` directly from a test CLI
(`test-lit/comgr-sources/hotswap_transpile_cli.cpp`) instead of going through the
pipeline, which is what lets the stack be reviewed and tested before the outer
layers exist.

Also missing from the stack, and deliberately so (M1-M4 work): the two
pre-translation safety gates, and the post-SSA repairs — OCML linking, the
cross-lane rewrite, the C5 classifier, the TDM runtime, and the projection
retries. `#3721` ships only two instruction handlers (`handle-sop1`,
`handle-sopp`) and a single `mov` + `endpgm` fixture, against the fork's thirteen
handlers.

### Why the outer layers went last

They are the low-risk part. A loop that compiles each kernel and then links, plus
argument validation and cache bookkeeping, is plumbing anyone can review quickly.
The places where a subtle mistake yields a kernel that runs and returns wrong
numbers are all *inside* `raiseToIR` — so those go up first and get the most eyes.

### Why `raiseToIRImpl` is the key

The M0 stack **is** `raiseToIRImpl` taken apart into one PR per phase, so knowing
that function is knowing the map every PR is a piece of.