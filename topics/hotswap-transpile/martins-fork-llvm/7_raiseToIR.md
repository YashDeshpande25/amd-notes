# Martin's Fork/Branch of LLVM: raiseToIR

- **Author:** Yash Deshpande
- **Date:** 03-08-2026
- **Model:** Claude Opus 5

## Where it lives

| Function | Declared in | Implemented in |
| --- | --- | --- |
| `raiseToIR` (two overloads) | `amd/comgr/src/hotswap/raiser.h` | `amd/comgr/src/hotswap/raiser.cpp` |
| `raiseToIRImpl` | `amd/comgr/src/hotswap/raiser.cpp` (`static`, no header) | `amd/comgr/src/hotswap/raiser.cpp` |

## Baseline understanding

### The one-sentence version

It takes machine code compiled for GPU A, works out what it *means*, writes that
meaning down as LLVM IR, and hands the IR to LLVM's normal compiler so it can be
re-compiled for GPU B.

Like translating a book: you do not swap words one at a time, you understand each
sentence and then say it again in the other language.

### The steps in plain English

**1. Check both GPUs.** Confirm the two GPU names are real, and look up what each
one can do — how wide is a wave, does it have matrix instructions, and so on.

**2. Decide how to deal with the wave-size difference.** The source GPU might run
32 threads at a time and the target 64. Pick the rule for mapping one onto the
other. This is the projection choice, and it colours everything afterwards.

**3. Read the instructions.** Turn the raw bytes into a list of instructions, and
note which addresses are jump targets — those are where basic blocks start.

**4. Chase the jumps you could not follow.** Some jumps go through a register, so
you cannot see the destination just by reading forward. Work out where they land
— sometimes in a completely different function — and read those instructions too.

**5. Two safety checks, before writing any IR.**

- Does the code do anything that depends on wave width in a way we cannot handle?
  If so, **stop now**.
- Does anything change the lane-active mask in a way nobody has audited? If so,
  **stop now**.

Both checks happen while we only have a list of instructions. Nothing has been
built yet, so quitting is cheap.

**6. Create an empty LLVM function**, with one empty block for each block-start
found in step 3.

**7. Give every GPU register a scratch variable**, and fill in the ones the
hardware provides for free at kernel start — the pointer to the arguments, the
workgroup ID, and so on. Which register holds which of those is read from the
kernel's own descriptor, never assumed.

**8. Translate each instruction, one at a time.** Look at what family the
instruction belongs to (scalar, vector, memory, matrix...) and call the handler
for that family, which writes the equivalent LLVM IR. If something cannot be
translated, note it and **keep going** — so one run reports every problem instead
of making you fix them one by one.

**9. Ask LLVM to tidy up.** All those scratch variables from step 7 get converted
into proper values. This is a standard LLVM pass, and it does the hardest
bookkeeping for free.

**10. A few finishing touches.** Pull in math-library helpers if any were used,
fix up cross-lane operations, and — if analysis now shows the projection from
step 2 will not work for this kernel — throw everything away and start over with
a more conservative one.

**11. Check the IR is well-formed**, then return it.

### The two ideas that make it work

**Refuse before you build.** Step 5 is where the expensive "no" happens, while
there is nothing to throw away. Better a clear refusal than code that runs and
quietly computes the wrong answer.

**Registers become memory, then LLVM recovers the logic.** This is the clever bit
in steps 7 and 9. Machine code has a fixed set of registers that get overwritten
constantly, which is awkward to translate directly. So instead of tracking them,
give each register a little box in memory: reading a register becomes "read the
box", writing becomes "write the box". The result is verbose and ugly. Then step 9
hands it to LLVM's `mem2reg` pass, which figures out the real flow of values and
deletes the boxes. You get clean IR without having to reason about it yourself.

### Mapping back to the phase numbers in the code, and to the upstream PRs

| Plain step | Phase in the code | Upstream PR that provides it |
| --- | --- | --- |
| 1, 2 — check GPUs, pick projection | Phase 0 (setup) | `#3537` (GPU checks), `#3717` (projection) |
| 3 — read instructions | Phase 1 | `#3716` |
| 4 — chase jumps | Phase 1.1 | `#3719` (`setpc-analysis.h`) |
| 5 — the two safety checks | Phase 1.4.5 and 1.5 | not yet upstream (error type in `#3718`) |
| 6 — empty function and blocks | Phases 2 and 3 | `#3721` |
| 7 — registers get boxes, seed entry state | Phase 4 | `#3718` (register file), `#3719` (ABI layouts) |
| 8 — translate each instruction | Phase 5 | `#3720` (raise context), `#3721` (handlers) |
| 9 — LLVM tidies up | Phase 6 | `#3721` |
| 10 — finishing touches, maybe retry | Phases 6.5, 6.6, 6.7 | not yet upstream |
| 11 — check and return | Phase 7 | `#3721` |

The two "not yet upstream" rows are the gap between this fork and the M0 stack.
M0 is the spine — steps 1-4, 6-9, 11. The safety gates and the post-SSA repairs
exist here because the prototype discovered it needed them once it met real
kernels; upstream they are M1-M4 work.

If you only remember one thing: **steps 1-5 decide whether translation is even
possible, steps 6-9 do it, and steps 10-11 clean up and check.** The phase numbers
look intimidating mostly because the safety checks were added later and got
decimal numbers rather than a renumbering.
