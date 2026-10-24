# 09: What the 62 ms outside the host experts is

Type: task
Status: claimed
Blocked by: 01

## Question

On card 1 with the app's launch, a Dynamic MoE decode token takes about 78 ms. About 16 ms
of that is the CPU expert executor, on the critical path. The fit puts the rest at 62 ms.

How do those 62 ms split, measured, not modelled?
- GPU compute of attention and the resident experts;
- the GPU's wait at the join;
- the CPU's graph build and encode;
- uploads and promotions.

The timeline cannot split a decode token today. Answering this probably needs per-layer GPU
timestamps or a command-buffer split at the join, which is engine instrumentation.
