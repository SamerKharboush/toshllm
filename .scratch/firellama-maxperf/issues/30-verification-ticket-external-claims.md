# 30 - Standing verification ticket: external claims, and the agent that checks them

Status: open, recurring
Date: 2026-10-18

## Why this exists

Every externally supplied technical anchor in this project so far has been
checked against the machine or the source rather than taken on trust, and a
large share of them failed. The failure mode is consistent and worth naming: a
claim arrives that is plausible, specific, and wrong in a way only a check
reveals. Accepting one has already cost this project a retraction cascade and
one void measurement run.

The rule this ticket encodes: any claim that would change what gets built is
checked before it changes anything, and the check is recorded here with its
verdict and its source.

## The agent

Web verification is delegated to a worker subagent given a numbered claim list.
It returns VERIFIED / FALSE / UNVERIFIABLE per claim with a primary source and a
quote. Primary sources only: project code, project docs, GitHub issues, Apple
documentation. Search results alone are not accepted as evidence for a claim
about code. The verdicts are pasted below.

Verdicts are recorded even when they confirm the claim, because "this one was
right" is information about the source's reliability.

## Log

### Round 1 (2026-10-17 and 2026-10-18)

Checked locally against this machine and tree:

| claim | verdict | how it was checked |
|---|---|---|
| D700 lacks Metal3 | TRUE | `MTLCopyAllDevices` + `supportsFamily:` via tools/metal-probe |
| D700 has threadExecutionWidth 64 | TRUE | same probe |
| patches/llama/metal/ exists | TRUE | directory listing, 15 patches |
| 0001-amd-backend-host.patch exists | TRUE | find |
| 0004-matvec-wave64.patch exists | TRUE | find |
| 0012-older-gcn-and-macos12.patch exists | TRUE | find |
| 0013-vram-budget-and-private-mirror.patch exists | FALSE | not present anywhere; quant/0013 is turbo-kv. The VRAM budget logic is in 0001 and 0002 |
| patches/llama/metal/ holds 16 patches | FALSE | it holds 15 |
| branch is 34 commits behind origin/main | FALSE | `git rev-list --count HEAD..origin/main` is 0; it is 19 ahead |
| upstream toshllm HEAD is 1559d9b | FALSE | `git ls-remote upstream HEAD` is 523b814ac8cc61d80afbc73cece581c34234658b |
| toshllm-work/iron-llama-rc1 and toshllm-work/toshllm-ours exist | FALSE | no such directory, and no ~/toshllm-work |
| GGML_METAL_VRAM_BUDGET_MB exists in the fork | FALSE | 0 files reference it |
| GGML_METAL_N_CB exists in the fork | FALSE | 0 files reference it |
| GGML_METAL_FORCE_PRIVATE exists in the fork | FALSE | 0 files reference it |
| GGML_METAL_DEVICE_INDEX exists in the fork | TRUE | 2 files reference it |
| GGML_METAL_CONCURRENCY_DISABLE exists in the fork | TRUE | 1 file references it |
| this CPU has no AVX2 and no FMA3 | TRUE | sysctl leaf7_features and features |
| llama.cpp #15228 exists and is about Metal3 on Mac Intel and Radeon | TRUE | fetched the issue |
| iRon-Llama exists | TRUE | github.com/Basten7/iRon-Llama, README targets W6800X Duo |

Delegated to the web-verification agent, round 1: issues #19610 and #26949, the
`has_simdgroup_reduction` gate and its family condition, whether Apple documents
the D700's Metal family, whether `ggml-metal-gcn` exists as a project, the
current HEADs of both toshllm repositories, and what iRon-Llama claims to
support. Verdicts appended below when they return.

## The one that would have done damage

A claim arrived that without `has_simdgroup_reduction` "Metal backend is
mathematically impossible, not tuneable", which would have required declaring
this fork's working GPU path impossible. It is false as stated, and the
evidence is on this machine: the fork compiles 19 Metal pipelines for a single
0.6B forward pass, reports zero CPU fallbacks, runs `kernel_mul_mm_q8_0_f32_w64`
as a GPU matmul, is deterministic run to run (cosine 1.0000 against itself),
and reproduces the published throughput to 0.13% on pp512.

The accurate statement, which the fork's own maintainer makes in #15228, is that
the *current upstream implementation* requires it. That is a codebase
constraint, not a hardware one, and it is the constraint this fork exists to
lift.
