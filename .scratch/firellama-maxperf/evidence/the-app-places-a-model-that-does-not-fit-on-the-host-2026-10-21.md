# The app places a model that does not fit on the host, and the launch it builds says so

## The rule, in terms a reader can check

**A model whose weights do not fit in the VRAM the run may use runs on the host, on the
cards this fork measured.** The VRAM the run may use is the combined VRAM of the cards it
splits across and one card's VRAM otherwise, less a 1 GB reserve per card. The host has to
have room for the weights, the KV cache and the compute buffers, or the host is not a
fallback either.

The payoff is in the rows and not in the rule: the same 35B Q6_K decodes at 0.1450 tok/s on
one D700 and 11.1015 tok/s with everything on the host (R1, R2, R11), and a 27B Q8_0 at
0.0883 against 1.5972 (R19, R20). The card path keeps a fraction of the weights and pays
for the whole model on every token; the host path pays for the active part.

The rule is not "big models on the CPU". A model whose weights fit stays on the card: the
8B Q4_K_M decodes at 8.2632 tok/s there (R5), and the 14B Q4_K_M fits across the two D700s
(10.0 GB of budget against 8.38 GiB of weights) and runs there.

## What the app now builds

The app resolves the placement when it reads the settings and again before a launch, and
the launch it builds for the models on this machine is:

| model | weights | placement | what the launch asks for |
|---|---|---|---|
| 35B Q6_K (26.56 GiB) | 26.56 GiB | host | `-ngl 0`, no `--n-cpu-moe`, no `--split-mode`, no card in the environment |
| 27B Q8_0 (27.74 GiB) | 27.74 GiB | host | the same |
| 14B Q4_K_M | 8.38 GiB | card | `-ngl 99 --split-mode layer`, `GGML_METAL_DEVICES=2` |
| 8B Q4_K_M | 4.68 GiB | card | `-ngl 99 --split-mode layer`, `GGML_METAL_DEVICES=2` |

The launch lines are the app's own, read out of `ServerSettings.arguments` and
`ServerSettings.environment` for these files on this machine, and they are what the two rows
below were measured with. A host placement also drops the expert offload
(`--n-cpu-moe`), the split, the device selection and the engine's own memory plan: a model
that is not on a card has nothing for those to do.

## The two rows the ticket asks for

| | |
|---|---|
| engine | this branch's `llama-server`, upstream pin `d81235049` + the 50-patch series, sha256 `8ebda2454b4df9ac348dc289cc44cb7e82af1885aa1c3c2ea78acbc5550b9d0d` (the engine the release ships), AppleClang 17 |
| machine | Intel Xeon E5-2697 v2, 12 physical cores, 64 GB RAM, two AMD FirePro D700 (6 GB each) |
| 35B row | the launch the app builds: `-m ornith-1.0-35b-Q6_K.gguf -ngl 0 -c 16384 -t 12 -fa auto --load-mode none --cache-ram 2048 --cache-reuse 256 --parallel 1`, `TOSH_FA_AMD=1`; prompt eval on a 192-token prompt with `cache_prompt: false`, decode on an 8-token prompt with 32 generated tokens, temperature 0, N=3 |
| 8B row | the launch the app builds: the same flags with `-ngl 99 --split-mode layer` and `GGML_METAL_DEVICES=2` |

| cell | prompt eval | decode | answer |
|---|---|---|---|
| 35B Q6_K on the host | 23.1305 tok/s (sd 2.1807) | **10.1353 tok/s** (sd 0.8144) | coherent |
| 8B Q4_K_M on the cards | 39.6722 tok/s (sd 3.2904) | **9.0028 tok/s** (sd 0.0280) | coherent |

## What this does not establish

- The 35B's host row is not the same cell as R2. R2 used `-c 4096 -t 8` and the engine's
  default load mode; this row uses the launch the app builds (`-c 16384 -t 12`, no mmap).
  The two are observations of the same placement under two protocols, not two estimates of
  one number, and they are not averaged.
- The rule is keyed on the card's name (`firepro d700`). A card this fork has not measured
  keeps the path it had, because the host link and the decode on it were not measured.
- The 8B row is a layer split across the two D700s, which is what the app does by default.
  The one-card row for the same model is R5.
- The first trial of each cell is the disk reading the model; the warmups were not
  discarded, and the spreads above include them.
