# Martin's Fork/Branch of LLVM: Structure

## Access

`YashDeshpande25` is a collaborator (write access) on Martin's fork of LLVM:
<https://github.com/martin-luecke/llvm-project>.

## `hotswap-martin` vs `amd-staging`

- Repo: `/home/ydeshpan/my_repos/llvm-project`
- Remote: `martin` -> `git@github.com:martin-luecke/llvm-project.git`
  (fetches `hotswap` only)
- Measured: 2026-07-30

### Divergence summary

| Metric | Value |
| --- | --- |
| Branch tip | `8451fccde390` (2026-07-28) |
| `amd-staging` tip | `60fc37823a90` |
| Commits behind `amd-staging` | 11,042 |
| Commits ahead of `amd-staging` | 202 |
| Divergence point (merge base) | `fd64721962c4` |
| Divergence date | 2026-05-15 (76 days ago) |
| Last sync with `amd-staging` | 2026-05-15 — same as divergence; never re-synced |
| Commits added since last sync | 202 |
| Merge commits on branch | 0 |
| Commit date range | 2026-05-15 -> 2026-07-28 |
| Diff vs merge base | 524 files, +90,462 / -948 |

`origin/amd-staging`, `upstream/amd-staging`, and local `amd-staging` are all at
`60fc37823a90`, so the comparison is unambiguous.

### Where the 202 commits land

| Path scope | Commits |
| --- | --- |
| `amd/comgr` | 199 |
| `amd/comgr/src/hotswap` | 186 |
| Outside `amd/comgr` | 6 |

### Authors

| Author | Commits |
| --- | --- |
| Tim Gymnich | 65 |
| Martin Paul Lücke | 53 |
| Oleksandr "Alex" Zinenko | 46 |
| Juan Manuel Martinez Caamaño | 10 |
| Soumitra Chatterjee | 8 |
| Martin Lücke | 7 |
| ishkool | 5 |
| Aurore De Spirlet | 4 |
| Anik Chaudhuri | 3 |
| Gaurav Verma | 1 |

(Martin appears under two name spellings, 60 commits combined.)

### Notes

- The branch was cut once from May-15 `amd-staging` and has only accumulated
  work since; there are no merges or rebases bringing newer `amd-staging` in.
- Rebasing onto current `amd-staging` has a narrow conflict surface because the
  work is concentrated in `amd/comgr/src/hotswap`, which the rest of
  `amd-staging` barely touches.
- The 6 commits reaching outside `amd/comgr` are the likely friction points —
  notably an `[AMDGPU]` change to emitted `user_sgpr_count`.

## Core structure

Top-level: everything lands under `amd/comgr` (the Code Object Manager), with
only a thin spillover into LLVM proper.

| Location | Files | Role |
| --- | --- | --- |
| `amd/comgr/src/hotswap/` | 82 added, 4 modified | The transpiler library itself |
| `amd/comgr/src/hotswap/docs/` | 10 added | Design docs |
| `amd/comgr/test-lit/hotswap-raise/` | 356 added | Lit test corpus (355 `.s` + 1 `.md`) |
| `amd/comgr/test-lit/`, `test-unit/`, `test-shared/` | ~48 | Harness wiring and unit tests |
| `amd/comgr/src/`, `include/`, `CMakeLists.txt` | ~9 modified | COMGR integration points |
| `llvm/lib/Target/AMDGPU/`, `llvm/test/CodeGen/AMDGPU/` | 3 | The only real LLVM-tree changes |
| `.github/workflows/` | 3 | CI |

## Reference

Library README:
`/home/ydeshpan/my_repos/llvm-project/amd/comgr/src/hotswap/README.md`
