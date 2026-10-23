# 04: Expert parallelism across GPUs that cannot see each other

Type: research
Status: claimed
Blocked by:

## Question

How do existing engines split MoE experts across GPUs with no peer link, so all traffic goes
through host RAM? Engines to check: upstream llama.cpp, vLLM's expert parallelism, ktransformers,
and others found on the way.

For each, find out:
- what crosses the devices per token, and how much;
- how routing results reach each device;
- what overlap they get;
- whether any of it works on Metal or on non-AVX2 CPUs.

The answer feeds the two-card expert-tier design (ticket 71 in
`.scratch/firellama-maxperf/`).
