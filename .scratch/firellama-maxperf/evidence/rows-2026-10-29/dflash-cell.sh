#!/bin/zsh
# dflash-cell.sh <label> <requests> [extra server args...]
# One server, <requests> greedy /completion requests (request 1 = warmup), one JSON line each.
S=/private/tmp/claude-501/-Users-sam-firellama/51472447-7400-4c91-ad80-addb9c10346b/scratchpad
B=/Users/sam/firellama/vendor/llama.cpp/build-static/bin/llama-server
T=/Users/sam/models/Ornith-1.0-35B-GGUF/ornith-1.0-35b-Q6_K.gguf
label=$1; n=$2; shift 2
TOSH_FA_AMD=1 $B -m $T --port 8091 -ngl 0 -c 16384 -t 12 -fa auto --load-mode none --parallel 1 \
  --cache-ram 0 "$@" > $S/srv-$label.log 2>&1 &
pid=$!
for i in {1..300}; do
  curl -s -m 2 http://127.0.0.1:8091/health | grep -q '"ok"' && break
  kill -0 $pid 2>/dev/null || { echo "$label: server exited"; grep -E ' E |error' $S/srv-$label.log | tail -5; exit 1; }
  /bin/sleep 2
done
P=${DFLASH_PROMPT:-$'<|im_start|>user\nWrite a Python function that inserts a key into a binary search tree and explain how it works.<|im_end|>\n<|im_start|>assistant\n'}
body=$(python3 -I -c 'import json,sys;print(json.dumps({"prompt":sys.argv[1],"n_predict":128,"temperature":0,"top_k":1,"cache_prompt":False}))' "$P")
for i in $(seq 0 $((n-1))); do
  curl -s -m 1800 http://127.0.0.1:8091/completion -H 'Content-Type: application/json' -d "$body" |
    python3 -I -c 'import json,sys;d=json.load(sys.stdin);t=d["timings"];print(json.dumps({"label":sys.argv[1],"run":int(sys.argv[2]),"warmup":sys.argv[2]=="0","decode":t["predicted_per_second"],"prompt":t["prompt_per_second"],"n":t["predicted_n"],"draft_n":t.get("draft_n"),"draft_acc":t.get("draft_n_accepted"),"text":d["content"]}))' $label $i >> $S/dflash-rows.jsonl
  tail -1 $S/dflash-rows.jsonl | python3 -I -c 'import json,sys;d=json.load(sys.stdin);print(d["label"],d["run"],round(d["decode"],4),d["draft_n"],d["draft_acc"],repr(d["text"][:50]))'
done
grep -E 'per-layer causality|draft acceptance' $S/srv-$label.log | tail -3
kill $pid; wait $pid 2>/dev/null
/bin/sleep 20
