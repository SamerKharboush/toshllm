#!/bin/bash
cd /Users/sam/firellama/vendor/llama.cpp
O=$1
for round in 1 2; do
 for M in /Users/sam/models/Qwen3-4B-Q4_K_M.gguf /Users/sam/models/Nemotron-3.5-Bolt-E4B-Q4_K_M.gguf; do
  for cell in old new old new; do
   b=build-static/bin/llama-bench; [ $cell = old ] && b=build-static/bin/llama-bench-oldrule
   n=$(basename $M .gguf)
   echo "=== r$round $n $cell $(date +%H:%M:%S)"
   GGML_METAL_DEVICE_INDEX=1 perl -e 'alarm 900; exec @ARGV' $b -m $M -p 0 -n 128 -r 5 -fa 1 -o csv 2>/dev/null | tail -1
   sleep 10
  done
 done
done
