import json,sys,urllib.request
p="<|im_start|>user\nWrite a Python function that inserts a key into a binary search tree and explain how it works.<|im_end|>\n<|im_start|>assistant\n"
b=json.dumps({"prompt":p,"n_predict":256,"temperature":0,"top_k":1,"cache_prompt":False}).encode()
r=urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8093/completion",b,{"Content-Type":"application/json"}),timeout=600)
d=json.load(r); open(sys.argv[1],"w").write(d["content"]); print(d["tokens_predicted"], d.get("timings",{}).get("predicted_per_second"))
