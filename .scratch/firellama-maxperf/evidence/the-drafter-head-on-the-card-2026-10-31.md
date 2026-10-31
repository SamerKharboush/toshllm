# The DFlash drafter's borrowed lm head on the card (patch spec/0073)

## The question

The 35B (Ornith-1.0-35B Q6_K) runs on the host (`-ngl 0`); its DFlash Q8_0 drafter runs on
card 1. The drafter has no lm head of its own and borrows the target's `output.weight`
(Q6_K, 2048 x 248320, 397.9 MiB), which under `-ngl 0` is in host memory. beta.4 measured the
drafter's own Q8_0 kernels at about 22 ms of a ~60 ms draft. Does a copy of the head on the
drafter's card shorten drafting, and does that show in decode?

## The change

`spec/0073`: when a DFlash draft context borrows a host-resident lm head and the draft's own
weights are on a device, the context copies the head once at load into a buffer of the
draft's buffer type (same type and shape), and the DFlash graph multiplies by that copy. The
Hadamard rotation lookup stays keyed on the target's tensor. If the copy cannot be allocated,
the context warns and keeps the host path. `TOSH_DFLASH_HEAD_HOST=1` keeps the host path. At
`-lv 4` one line says which:

    llama_context: dflash lm head copied to MTL0_Private (397.9 MiB, q6_K)
    llama_context: dflash lm head kept on the host (TOSH_DFLASH_HEAD_HOST, 397.9 MiB)

The card holds the extra 397.9 MiB next to the drafter's 391.12 MiB of weights.

## Method

- engine: llama.cpp `d81235049` plus 83 patches, the dev tree `build-static` (not the AVX1
  release engine); llama-server;
- target `ornith-1.0-35b-Q6_K.gguf`, `-ngl 0 -c 16384 -t 12 -fa auto --load-mode none
  --parallel 1 --cache-ram 0`, `TOSH_FA_AMD=1 GGML_METAL_DEVICE_INDEX=1`;
- drafter `Qwen3.6-35B-A3B-DFlash-Q8_0.gguf`, `--spec-type draft-dflash -ngld all -devd MTL0
  --spec-draft-n-max 3`;
- `-lv 4` on every server (needed for the draft timer and the head line);
- request: `rows-2026-10-30/0d-req.py`, POST /completion, the BST prompt, 128 tokens,
  temperature 0, top_k 1, cache_prompt false; 4 requests per server, the first discarded;
- draft ms per request = difference of consecutive cumulative `g` in the server's
  `statistics draft-dflash ... dur(b,g,a)` line; tok/s from the server's `eval time`;
- cells: H = `TOSH_DFLASH_HEAD_HOST=1`, D = the copy. One server per cell per round, 20 s
  between servers, nothing else serving.

## Set A (servers H1 D1 H2 D2, run by the delegate; logs re-read by the orchestrator)

Per request, the first of each server dropped (N = 3 per server, 6 per cell):

| cell | server | tok/s | draft ms | accepted / drafted |
|---|---|---|---|---|
| H | H1 | 11.73, 11.69, 11.79 | 1747.0, 1781.2, 1732.3 | 73/87 each |
| D | D1 | 12.35, 12.38, 12.62 | 1081.2, 1090.6, 1074.2 | 73/87 each |
| H | H2 | 11.71, 11.85, 11.81 | 1747.2, 1754.2, 1722.3 | 73/87 each |
| D | D2 | 12.51, 12.67, 12.64 | 1086.3, 1085.1, 1084.6 | 73/87 each |

Cell means: H 11.763 tok/s, 1747.4 ms drafting per request; D 12.527 tok/s, 1083.7 ms.
Server sd within a cell: H tok/s 0.049 and 0.069, D 0.148 and 0.085.

## Set B (servers T-D then T-H, the tidied source that became 0073, run by the orchestrator)

| cell | tok/s | draft ms | accepted / drafted |
|---|---|---|---|
| D | 11.66, 11.63, 11.80 | 1114.1, 1086.9, 1078.3 | 73/87 each |
| H | 10.80, 10.75, 10.90 | 1852.4, 1850.8, 1844.9 | 73/87 each |

Set B ran 0.8-0.9 tok/s below set A in both cells. The two sets are two observations, not
pooled. In each set D is above H, and draft time per request falls from about 1.75-1.85 s to
about 1.08-1.11 s; that is about 29 drafts per request, so about 23 ms less per draft.

Acceptance is 73 of 87 in every request of every server, so the drafts are the same drafts.

## Text

All 16 texts of set A and all 8 of set B are byte-identical (`cmp`) to `P-1.txt`, the plain
decode of the same request without `-md` (541 bytes).

## The gate

`GGML_METAL_DEVICE_INDEX=1 test-backend-ops -o MUL_MAT -b MTL0`: 1756/1756, Backend MTL0 OK
(the change adds no op; the gate is run because the tree was rebuilt). The series: 83 of 83
apply to `d81235049`.

## Notes

- The delegate's first build segfaulted at load: its INFO line passed a `size_t` to `%.1f`.
  The backtrace is `rows-2026-10-31/lldb.log`. Fixed before any measurement in this file.
- Plain decoding (cell P, no drafter, same session as set A): 10.93, 11.09, 10.97 tok/s.
  That is a different configuration, listed for the text reference only.
- Not run: the release AVX1 engine (that is the beta.5 gate), a model whose target head is on
  a card (the copy is skipped there by construction), and a drafter on the host.

Raw: `rows-2026-10-31/` (`ab.sh`, `H1.log` ... `D2.log`, `T-D.log`, `T-H.log`, `P.log`,
`P-1.txt`, `baseline.log`, `lldb.log`, `summary.txt`).
