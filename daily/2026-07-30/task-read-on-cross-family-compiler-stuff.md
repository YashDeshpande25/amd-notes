# Task: Read on Cross-Family Compiler Stuff

2026-07-30. Details in `topics/hotswap-transpile/`.

## Context shared by the team

Messages shared by @Gaurav:

- <https://github.com/ROCm/llvm-project/pull/3536>
- <https://github.com/ROCm/llvm-project/pull/3537>

Message from @Alex:

> To help with cross-family, here's a rough plan of functionality milestones:
>
> - **M0**: directory layout, decoder, loader, dispatch infra: these are not
>   parallelizable but can benefit from aggressive review -- you are welcome to
>   roast the code
> - **M1**: vector add; this will require some SALU/VALU ops and simple
>   load/store, somewhat splittable
> - **M2**: scalar handwritten matmul: blocked on support for non-trivial CFG,
>   after which can do more VALU and VOPD instructions
> - **M3**: torch-like WMMA gemm: WMMA/MFMA is a big chunk, LDS instructions,
>   packed VALU, cross-lane instructions
> - **M4**: other non-matmul kernels (reduce, topk, scan, up to full attention)
>
> I'll push out patches for M0 soon-ish. It is technically possible to start
> migrating things on top of that if you are comfortable with rebase mess

Review skills we can use on ourselves too:

- <https://amdcloud-my.sharepoint.com/:u:/g/personal/azinenko_amd_com/IQBr2o143Qh9SY4dQaedjxwUAcY46EnctxoKh9ZwkOruCrs?e=NRPrWZ>
- <https://amdcloud-my.sharepoint.com/:u:/g/personal/azinenko_amd_com/IQD8jIyZ8aX3SLBIT3KjAB7cASGRvMLrYz42dn_oTcCHDYE?e=O2tBCS>

Follow-ups from @Alex:

> the dev machine (shark4) just died on me, so no patches for you yet

> these are partial planning docs I was iterating on

- <https://amdcloud-my.sharepoint.com/:t:/g/personal/azinenko_amd_com/IQD6qQJn7YjeTKIpN98OMrXbAR9O4zyD7vlp2hAlXLAJv8k?e=gvZIoo>
- <https://amdcloud-my.sharepoint.com/:t:/g/personal/azinenko_amd_com/IQDpgkjAWERXTZI95lpBrfQPAR9WC72jyDlKb0jqa-sLt1I?e=Et1EtF>

> pushed #3716-#3721, please review aggressively and consider the design in the
> long term

> for minor changes and other nitpicks, feel free to push commits directly to the
> corresponding branch

Action items from that: review `#3716`-`#3721` aggressively with long-term design
in mind, and push minor fixes and nitpicks straight to the corresponding branch
rather than leaving comments.

## Work done

1. Added Martin's fork as a remote and created local `hotswap-martin` tracking his `hotswap` branch.
2. Built the hotswap transpiler from that branch and passed the in-tree lit smoke test.
3. Translated a gfx950 code object to gfx942 offline, and dumped the `.s` / `.ll` / `.dis` intermediates.
4. Found the repo has no GPU test, so wrote a HIP harness and ran the translated kernel correctly on the MI300X.
5. Read the code to map the COMGR entry point, the handoff into the hotswap library, and the translation cache.
