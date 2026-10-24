# A Dynamic MoE decode token, split

Date: 2026-10-25. Map ticket: `.scratch/pooled-budget/issues/09-what-the-62-ms-outside-the-host-experts-is.md`.

## Method

- Engine: fork engine `d81235049` plus 53 patches, including 0048 with its clock and kind-24
  fixes. Built AVX1: 0 AVX2/FMA mnemonics.
- Model and launch: Ornith-1.0-35B Q6_K with the app's launch (`-c 16384 -t 12 -fa auto
  --load-mode none --cache-ram 2048 --cache-reuse 256 --parallel 1 --dynamic-moe on`),
  `TOSH_FA_AMD=1`, card 1 (`GGML_METAL_DEVICE_INDEX=1`).
- Servers: 4, in the order off, on, off, on. `on` sets `TOSH_DMOE_TIMELINE`.
- Requests per server: 1 warmup + 3 measured short requests (BST prompt, 200 tokens,
  greedy). Analysis drops the warmup request and the first 2 tokens of each request:
  1182 tokens over the two `on` servers.
- Scripts: `timeline_run.sh` and `timeline_analyze.py`, written by OpenCode and checked here.
  The run was repeated by the orchestrator after the fixes.
- Per decode token, the window is one `llama_context::decode` call (kind 24):
  - G is the union of the GPU command-buffer spans inside it (kind 21);
  - H is the sum of the CPU expert jobs (kind 20);
  - E is the host time in `ggml_metal_graph_compute` (kind 22);
  - I = W − G.

## Rows

| | mean ms | median | p10 | p90 |
|---|---|---|---|---|
| W, the token | 76.048 | 75.948 | 73.880 | 78.340 |
| G, GPU busy span (2 command buffers per token) | 73.400 | 73.265 | 71.570 | 75.412 |
| H, CPU expert jobs (40 per token) | 14.449 | 14.566 | 11.741 | 16.927 |
| E, host encode | 6.591 | 6.556 | 5.384 | 7.586 |
| I, no GPU command buffer running | 2.648 | 2.625 | 2.127 | 3.277 |

- The two `on` servers agree to within 0.16 ms on every mean.
- The timeline costs nothing measurable: decode was 13.04 tok/s pooled with it off and 13.02
  with it on, over N = 6 requests each.

## Reading

- **The GPU has work queued for 73.4 of the 76.0 ms.** The CPU experts run inside that span:
  ticket 01's slope of 0.976 says each ms of them adds a ms to the token, so the GPU waits on
  them at the joins. These waits are inferred from the slope, not measured. Taking H out
  leaves about 59 ms of GPU work per token, for attention and the delta-net layers, the
  shared expert, the resident experts and routing.
- **Host encode, 6.6 ms, mostly overlaps the GPU:** only 2.6 ms of the token has no GPU
  buffer running.
- **The largest share of a 35B decode token is GPU kernel time on the D700,** not the CPU
  experts. Which ops it is was not measured here; that is the next ticket.

## Defects found and fixed on the way (in 0048 before it shipped)

- The host timeline clock was `steady_clock`, which counts sleep. Metal's GPU timestamps do
  not, and the two were 6113 s apart on this Mac. The host clock is now `CLOCK_UPTIME_RAW`.
  The existing upload events (kind 2) were misaligned for the same reason. The only other
  host-against-GPU comparison, the rare-rows `late_s`, is a log statistic and drives no
  decision.
- Kind 24 was first placed in `llama_decode`, which the server does not call; the server
  uses `llama_process` → `llama_context::decode(const llama_batch_ext &)`.
- The first run's after-the-fact alignment (823–955 of 2088 buffers matched, offsets 232 ms
  apart) is not published as a row.
