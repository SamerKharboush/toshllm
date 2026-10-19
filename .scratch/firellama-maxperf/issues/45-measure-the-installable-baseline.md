# 45: measure the installable baseline

Status: ready-for-agent
Type: task
Spec: ../spec.md (Revision 5)

## Problem

The whole effort compared against stock llama.cpp, which no user installs. The alternative a
user actually has is the 0.87.26 noavx2 build, and it has never been run on this machine.

## Change

Install and run it on the Mac Pro. Record what it compiles and what falls back: matmul kernel
count, refused-pipeline count, CPU-fallback count, and whether Flash Attention lands on GPU or
CPU. These counters are the capability metric and they do not depend on thermal state.

## Evidence

The counts from this binary, and the engine log lines they came from. If it compiles matmul
kernels on the D700s, the capability claim needs rewriting before anything else happens.
