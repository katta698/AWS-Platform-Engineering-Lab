import io, json, os, sys, time, urllib.request
p=os.path.expandvars(r"%APPDATA%\terraform.d\credentials.tfrc.json")
tok=json.loads(io.open(p,encoding="utf-8-sig").read())["credentials"]["app.terraform.io"]["token"]
H={"Authorization":"Bearer "+tok,"Content-Type":"application/vnd.api+json"}
def api(u,d=None):
    return json.load(urllib.request.urlopen(urllib.request.Request(u,headers=H,data=json.dumps(d).encode() if d else None)))
runs=sys.argv[1:]
deadline=time.time()+600
while time.time()<deadline:
    done=True
    for r in runs:
        d=api("https://app.terraform.io/api/v2/runs/"+r)
        s=d["data"]["attributes"]["status"]
        print(time.strftime("%H:%M:%S"),r,s)
        if s=="planned":
            api("https://app.terraform.io/api/v2/runs/%s/actions/apply"%r,{"comment":"confirmed teardown"})
            print("   -> apply confirmed")
            done=False
        elif s not in ("applied","errored","canceled","discarded","planned_and_finished"):
            done=False
    if done: break
    time.sleep(20)
