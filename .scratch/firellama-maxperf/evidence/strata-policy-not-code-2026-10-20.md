# Strata: policy adopted, code not ported

## Why no port

Strata cannot run on this machine, and its code cannot be ported to it. From Strata's own
README, as reported to this project:

- The macOS build requires **Apple Silicon M1 or newer** and **macOS 15 or newer**.
- The Linux AMD path is **HIP on RX 6800 and newer** (RDNA2).
- A FirePro D700 is **GCN 1.0 (Tahiti)**.
- **HIP has no macOS backend at all.**

That last point is the decisive one, and it is not a gate to edit out. It is a compute stack
that does not exist on this OS. Porting Strata's memory tier would be rewriting it above a
different backend, not porting it.

**Receipts owed:** the exact file and line in Strata's repository for each of the four claims
above. The claims are recorded here as reported; the line numbers have not been fetched and
confirmed in this repository's own history, and a future ticket proposing a port must first
produce a Strata code path that executes on GCN 1.0.

## What is adopted: the policy, using levers the engine already has

llama.cpp has the same three levers at a simpler level, and all three exist at this pin:

| lever | flag | Strata's equivalent |
|---|---|---|
| experts in host RAM | `--n-cpu-moe` | experts streamed from SSD into RAM |
| per-tensor placement | `-ot` | busiest experts on the GPU |
| page cache for the rest | mmap | the SSD tier, backed by the 64 GB |
| small draft model | `-md`, `--draft-max` | speculative decoding, Strata's 1.6-1.8x |

Upstream ToshLLM already ships Dynamic MoE with disk-expert streaming, which is the same idea
at a simpler level.

So the work is to measure what is already here, not to port anything. Tickets 57-60 do that:
the utilisation card says what the box is used for, the thread sweep says whether the CPU lane
was measured at the knee, the tiering preset says whether a model that overflows VRAM can run
on VRAM plus RAM, and the speculative run says whether Strata's headline number reproduces
here.
