import json,sys,urllib.request
p="<|im_start|>user\nWrite a Python function that inserts a key into a binary search tree and explain how it works.<|im_end|>\n<|im_start|>assistant\n"
for i in range(int(sys.argv[1])):
    b=json.dumps({"prompt":p,"n_predict":128,"temperature":0,"top_k":1,"cache_prompt":False}).encode()
    r=json.load(urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8091/completion",b,{"Content-Type":"application/json"}),timeout=900))
    t=r["timings"]; print(json.dumps({"i":i,"tps":t["predicted_per_second"],"pred_ms":t["predicted_ms"],"n":t["predicted_n"],"dn":t.get("draft_n"),"da":t.get("draft_n_accepted")}),flush=True)
    open(sys.argv[2]+f"-{i}.txt","w").write(r["content"])
