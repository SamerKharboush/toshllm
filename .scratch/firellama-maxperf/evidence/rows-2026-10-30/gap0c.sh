#!/bin/zsh
# gaps.sh: 5 alternated rounds of forced r4/r8 (q6_K) and r4/r8/L16r8 (q4_K) plus the default rule, card 1
cd /Users/sam/firellama/vendor/llama.cpp
O=$1
P6='type_a=q6_K,type_b=f32,m=(768|1024|1280|1536|1792),n=1,k=2048|type_a=q6_K,type_b=f32,m=1024,n=1,k=(2560|4096|5120)|type_a=q6_K,type_b=f32,m=2560,n=1,k=(4096|9728)|type_a=q6_K,type_b=f32,m=(9728|2048),n=1,k=2560|type_a=q6_K,type_b=f32,m=4096,n=1,k=12288|type_a=q6_K,type_b=f32,m=5120,n=1,k=17408|type_a=q6_K,type_b=f32,m=2048,n=1,k=(512|4096)'
P4='type_a=q4_K,type_b=f32,m=(4096|5120|6144|7168|8192|10240|12288),n=1,k=4096|type_a=q4_K,type_b=f32,m=5120,n=1,k=(5120|17408)|type_a=q4_K,type_b=f32,m=17408,n=1,k=5120|type_a=q4_K,type_b=f32,m=4096,n=1,k=12288'
run() { label=$1; P=$2; r=$3; shift 3
  env GGML_METAL_DEVICE_INDEX=1 TOSH_SWEEP_DEBUG=1 "$@" ./build-static/bin/test-backend-ops perf -o MUL_MAT -b MTL0 -p "$P" > $O/$label-$r.log 2>&1
  grep -o 'SWEEP pipeline = kernel_mul_mv_q[46]_K_f32[^ ]*' $O/$label-$r.log | sed 's/_nsg=.*//' | sort -u | sed "s/^/$label r$r /" >> $O/pipelines.txt
  grep 'MUL_MAT(' $O/$label-$r.log | python3 -I -c '
import sys,re,json
for l in sys.stdin:
  m=re.search(r"type_a=(\w+),.*?m=(\d+),n=1,k=(\d+).*?([\d.]+) GB/s",l)
  if m: print(json.dumps({"label":sys.argv[1],"run":int(sys.argv[2]),"type":m[1],"m":int(m[2]),"k":int(m[3]),"gbs":float(m[4])}))' $label $r >> $O/rows.jsonl
}
for r in 1 2 3 4 5; do
  run q6def $P6 $r
  run q6r4 $P6 $r TOSH_SWEEP_TYPE=q6_K TOSH_SWEEP_NR0=4
  run q6r8 $P6 $r TOSH_SWEEP_TYPE=q6_K TOSH_SWEEP_NR0=8
  run q4def $P4 $r
  run q4r4 $P4 $r TOSH_SWEEP_TYPE=q4_K TOSH_SWEEP_NR0=4
  run q4r8 $P4 $r TOSH_SWEEP_TYPE=q4_K TOSH_SWEEP_NR0=8
  run q4L16r8 $P4 $r TOSH_SWEEP_TYPE=q4_K TOSH_SWEEP_NR0=8 TOSH_SWEEP_LANES=16
done
echo DONE
