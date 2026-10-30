#!/bin/zsh
# gate0a.sh <label> <type> [env...]: 5 perf runs of the new dense mat-vec cases on card 1
cd /Users/sam/firellama/vendor/llama.cpp
S=/private/tmp/claude-501/-Users-sam-firellama/51472447-7400-4c91-ad80-addb9c10346b/scratchpad
label=$1; ty=$2; shift 2
if [ $ty = q6_K ]; then P='type_a=q6_K,type_b=f32,m=(248320|8192|4096|512|32),n=1,k=2048|type_a=q6_K,type_b=f32,m=2048,n=1,k=(512|4096)'
else P='type_a=q4_K,type_b=f32,m=(12288|4096|1024|151936),n=1,k=4096|type_a=q4_K,type_b=f32,m=4096,n=1,k=12288'; fi
for r in 1 2 3 4 5; do
  env GGML_METAL_DEVICE_INDEX=1 TOSH_SWEEP_DEBUG=1 "$@" ./build-static/bin/test-backend-ops perf -o MUL_MAT -b MTL0 -p "$P" > $S/gate-$label-$r.log 2>&1
  grep -o 'SWEEP pipeline = [^ ]*' $S/gate-$label-$r.log | sort -u | sed "s/^/$label r$r /" >> $S/gate-pipelines.txt
  grep 'MUL_MAT(' $S/gate-$label-$r.log | python3 -I -c '
import sys,re,json
for l in sys.stdin:
  m=re.search(r"type_a=(\w+),.*?m=(\d+),n=1,k=(\d+).*?([\d.]+) GB/s",l)
  if m: print(json.dumps({"label":sys.argv[1],"run":int(sys.argv[2]),"type":m[1],"m":int(m[2]),"k":int(m[3]),"gbs":float(m[4])}))' $label $r >> $S/gate-rows.jsonl
done
