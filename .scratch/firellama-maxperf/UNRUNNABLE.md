# Configurations this machine cannot run

Recorded per `CLAUDE.md` rule 4: state which configurations cannot be run, next to the
numbers, rather than in a footnote.

## Ticket 52, the AVX1 comparison half — cannot run here

The ticket asks for this build's CPU path at `-ngl 0` against "a generic build's CPU path on
comparable silicon". There is one machine (Xeon E5-2697 v2, `Sams-Mac-Pro.local`). A
comparison between two builds of different ISA baselines needs two hosts or an emulator, and
neither exists here. What *can* be measured on this machine is absolute throughput at
`-ngl 0` for this build alone; that is a number, not a delta, and it does not answer the
question the ticket asks. The RAM-in-use half of ticket 52 is unaffected and runnable.

## Ticket 54, the MoltenVK probe — tool absent

`vulkaninfo` is not installed. The probe is a package install away, not a blocker, but the
ticket should not be claimed until the tool exists. Installing it is a network dependency
this round did not take on.

## Ticket 51, the Colibri benchmark half — model likely absent

The benchmark needs Qwen3.6-35B-A3B, roughly 23 GB, which is not among the models on this
machine. The receipts half needs three repositories cloned from the network, none of which
is present. The receipts are cheap and the benchmark is not; they are split for that reason.

## Ticket 45's disassembly tool

`llvm-objdump` is absent; `otool -tvV` is present and answers the same question. The audit
uses `otool`, and says so in its evidence.
