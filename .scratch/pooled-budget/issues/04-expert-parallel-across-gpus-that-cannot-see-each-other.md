# 04: Expert parallelism across GPUs that cannot see each other

Type: research
Status: resolved
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

## Answer

No engine has an expert-parallel path built for GPUs without a peer link. vLLM and SGLang run
their normal collectives, which stage through host memory. The host-RAM designs that exist
(llama.cpp `--n-cpu-moe`, ktransformers, Fiddler) split experts between CPU and GPU, not
between two GPUs.

Per-token bytes for the 35B shape, worked out from the code, not measured. Without a peer
link every card-to-card byte crosses PCIe twice.

| design | bytes per token | notes |
|---|---|---|
| llama.cpp layer split | 8 KiB | once, at the layer boundary between the cards |
| upstream `--moe-cache-mib` | 41.3 KiB fixed, plus 1.69 MiB per missed expert | one cache per card for its own layers, nothing card to card; the same shape as ticket 71 |
| ktransformers-style CPU/GPU overlap | 323.8 KiB | each byte crosses once; the CPU's experts overlap the GPU's |
| vLLM expert parallelism, 2 cards | 640 KiB | two combine steps per layer |
| true expert parallelism on our pair (inferred) | about 656 KiB | plus two cross-card syncs per layer; a similar sync pattern measured ≤ 5.41 ms/token on the dense 14B |

- **Can't run here:** vLLM, SGLang and kt-kernel. None has an Intel-Mac Metal or GCN 1.0
  backend, and vLLM and kt-kernel need AVX2 at minimum. ktransformers' "Expert Deferral"
  overlap changes the model's output.
- **Metal and the CPU:**
  - upstream llama.cpp drives only one physical GPU on Metal; the second D700 works only
    through this fork's patches;
  - the AVX build has dedicated AVX kernels for q4_K, q6_K and q8_0.

Detail: branch `research/expert-parallel-without-peer-links`, file
`research/expert-parallel-without-peer-links.md` (commit a962802, not pushed). Sources are at
llama.cpp 4231b23d, vLLM 4bceda5d, ktransformers a694e718 and SGLang 02b98360.
