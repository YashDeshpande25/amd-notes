# Task: Continue Reading on Cross-Family Compiler Stuff

- Author: Yash Deshpande
- Date  : 2026-08-03

I am continuing with my tutorial on using the transpiler & understanding what changes. 
Taking a deeper look into the wave32->wave64 translation strategies as my first kernel hit a fallback path.

I am also taking a complete look at raiseToIR function which is the heart of 
all the transpiler work as per my understanding. 

But it is a tough one. 

Message from Gaurav

last Friday, you were asking about UMD, KMD and other terms. 
 
Take a look at https://amd.atlassian.net/wiki/spaces/MLSE/pages/1700044723/02+Execution+Model+How+a+Workload+Flows+Through+AM
I did look into the execution model in May. But this will give you a high level idea about the flow in AM

```
Application (game / HIP / ML kernel)
        │   API calls: DX12 / Vulkan / HIP / OpenCL
        ▼
   UMD  (User-Mode Driver, per-process, ring 3)
        │   • compiles shaders
        │   • builds PM4 command buffers (the byte-level GPU command stream)
        ▼
   KMD  (Kernel-Mode Driver, shared, ring 0)
        │   • validates & maps memory (GPU VM)
        │   • schedules and pushes the PM4 stream onto the gfx ring
        ▼
   GPU hardware — the Command Processor (CP) consumes PM4
        │   CP -> GE -> SPI -> WGPs -> pixel pipe -> caches -> MC -> DRAM
        ▼
   Pixels / compute results / performance counters
   
   ```

   In this flow, TCore is nothing but a software model of the GPU
 
Look into DTIF for more details
 