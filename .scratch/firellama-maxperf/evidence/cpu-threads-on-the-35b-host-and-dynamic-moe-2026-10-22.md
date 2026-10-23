# CPU threads on the 35B: the host path and Dynamic MoE

Date: 2026-10-22.

## Method

- Engine: fork engine `d81235049` plus 51 patches (0046 included), AVX1.
- Model: Ornith-1.0-35B Q6_K.
- Launch: the app's own (`-c 16384 -fa auto --load-mode none --cache-ram 2048 --cache-reuse 256 --parallel 1`, `TOSH_FA_AMD=1`).
- Requests:
  - short: BST prompt, 200 tokens out, 1 warmup + 3 measured per server;
  - long: 2402 prompt tokens, 32 tokens out, 1 warmup + 2 measured.
- Each cell is a fresh server. All answers were checked, 112 in the sweep and 60 in the A/B, and none is degenerate.
- The control takes effect: the `dmoe_init` log prints the executor's host thread count as set (6, 8, 10 or 12).

## Sweep: 2 rounds, N = 6 short and 4 long per cell (decode tok/s, sd in brackets)

| cell | short decode | long decode | long prompt |
|---|---|---|---|
| host `-t 8` | 11.4353 (0.0977) | 10.6197 (0.1525) | 27.8719 (0.8621) |
| host `-t 10` | 11.9329 (0.2424) | 10.9026 (0.2469) | 27.2804 (0.1981) |
| host `-t 12` (app today) | 11.2093 (0.5750) | 11.0472 (0.2234) | 27.5858 (0.6393) |

The host gap between `-t 10` and `-t 12` on short decode, 0.72 tok/s, is about the size of the `-t 12` cell's own sd (0.58). That is not enough to change the app's thread choice.

## A/B: Dynamic MoE, default vs `-t 4` + `TOSH_DMOE_THREADS=10`, 6 alternating rounds

| cell | short decode, N = 18 | long decode, N = 12 | long prompt |
|---|---|---|---|
| `-t 12`, 12 executor threads (default) | 12.8096 (0.9347) | 11.9366 (1.0548) | 64.7704 (20.3972) |
| `-t 4`, 10 executor threads | 12.7114 (0.9142) | 12.0174 (0.8790) | 65.8138 (19.3842) |

- **No thread effect.** The two cells are equal within their sd. The sweep's hint that `-t 4` with 10 executor threads held the fast mode does not reproduce. Both cells fall into the slow mode: the default in rounds 2 and 3, `-t 4` with 10 in rounds 5 and 6.
- **Dynamic MoE decode is bimodal, at about 13.1–13.2 vs 10.1–10.8 tok/s.** The slow mode starts at an unpredictable point, sometimes partway through a server's life, and stays. In this A/B the VRAM arena was 1082.85 MiB in all 12 servers, so arena size does not explain the modes. The host path shows no such modes and the CPU reports no thermal limit. The cause is open, and it is the next lever: the fast mode alone is about 2 tok/s above the host.
- **No app change.** The thread settings stay as they are.

## Later the same day: which card

- Every Dynamic MoE cell above ran on card 0, the card that drives the display.
- On card 1, 6 servers with the default threads gave 13.1324 tok/s short decode (sd 0.1129,
  N = 18) and 73.1019 tok/s long prompt (sd 0.1032), with no slow mode and no stall.
- The bimodal rows above are a card-0 observation. Ticket 72 has the series.
