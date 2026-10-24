#!/usr/bin/env python3
"""Apply a VCS-backed HCP workspace against a KNOWN configuration version.

    python scripts/hcp_apply_pinned.py <workspace-name> [expected-commit-sha]

WHY THIS EXISTS
---------------
Creating a run through the HCP API without naming a configuration version
makes HCP reuse the LAST ONE IT HAS INGESTED. If the VCS webhook has not
landed yet -- and it often has not, seconds after a push -- the run plans the
PREVIOUS commit.

That failure is silent and it looks like success. It reported
"planned_and_finished: no changes" while the broken IAM policy it was meant
to fix was still live in the account. Nothing in the run output says "this is
not your code".

So: wait for a configuration version whose commit matches the one you just
pushed, pin the run to it, and refuse to proceed if it never arrives.
"""
import io, json, os, subprocess, sys, time, urllib.request

p = os.path.expandvars(r"%APPDATA%\terraform.d\credentials.tfrc.json")
TOK = json.loads(io.open(p, encoding="utf-8-sig").read())["credentials"]["app.terraform.io"]["token"]
H = {"Authorization": "Bearer " + TOK, "Content-Type": "application/vnd.api+json"}
API = "https://app.terraform.io/api/v2"


def api(url, data=None):
    req = urllib.request.Request(url, headers=H,
                                 data=json.dumps(data).encode() if data else None)
    return json.load(urllib.request.urlopen(req))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    ws_name = args[0]
    want = (args[1] if len(args) > 1 else
            subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip())

    ws = api(f"{API}/organizations/{os.environ.get('HCP_ORG', 'Katta')}/workspaces/{ws_name}")
    ws_id = ws["data"]["id"]
    print(f"workspace : {ws_name} ({ws_id})")
    print(f"want commit: {want[:12]}")

    # Wait for HCP to ingest the commit we actually pushed.
    # The commit sha lives in the ingress-attributes RELATIONSHIP, not in the
    # configuration-version's own attributes. Reading it from attributes
    # yields an empty string for every version, which silently matches
    # nothing -- a false refusal rather than a false apply, but still wrong.
    cv_id = None
    deadline = time.time() + 300
    while time.time() < deadline:
        doc = api(f"{API}/workspaces/{ws_id}/configuration-versions"
                  f"?page[size]=20&include=ingress-attributes")
        ingress = {i["id"]: i["attributes"].get("commit-sha", "")
                   for i in doc.get("included", []) if i["type"] == "ingress-attributes"}
        for cv in doc["data"]:
            rel = ((cv.get("relationships") or {}).get("ingress-attributes") or {}).get("data")
            sha = ingress.get(rel["id"], "") if rel else ""
            if sha and sha == want and cv["attributes"]["status"] == "uploaded":
                cv_id = cv["id"]
                break
        if cv_id:
            break
        print("  waiting for HCP to ingest the push...")
        time.sleep(10)

    if not cv_id:
        sys.exit("REFUSING: HCP never ingested that commit. A run now would "
                 "plan older code and report success.")
    print(f"pinned cv : {cv_id}")

    # Plan only by default. Applying is a separate, explicit step so the plan
    # can be read first -- the whole point of this script is that a run can
    # silently be about the wrong code.
    do_apply = "--apply" in sys.argv

    run = api(f"{API}/runs", {"data": {
        "type": "runs",
        "attributes": {"message": f"pinned to {want[:12]}", "plan-only": not do_apply},
        "relationships": {
            "workspace": {"data": {"type": "workspaces", "id": ws_id}},
            "configuration-version": {"data": {"type": "configuration-versions", "id": cv_id}},
        }}})
    rid = run["data"]["id"]
    print(f"run       : {rid}  ({'apply' if do_apply else 'PLAN ONLY'})")

    last = None
    deadline = time.time() + 1200
    while time.time() < deadline:
        d = api(f"{API}/runs/{rid}")["data"]["attributes"]
        st = d["status"]
        if st != last:
            print(f"  {time.strftime('%H:%M:%S')}  {st}")
            last = st
        if st == "planned":
            if not do_apply:
                break
            api(f"{API}/runs/{rid}/actions/apply", {"comment": "confirmed"})
        if st in ("applied", "errored", "canceled", "discarded", "planned_and_finished"):
            break
        time.sleep(8)

    # Always print what the plan actually proposes to change.
    plan_id = api(f"{API}/runs/{rid}?include=plan")["data"]["relationships"]["plan"]["data"]["id"]
    pa = api(f"{API}/plans/{plan_id}")["data"]["attributes"]
    print(f"\nplan: +{pa.get('resource-additions')} ~{pa.get('resource-changes')} "
          f"-{pa.get('resource-destructions')}")
    st = api(f"{API}/runs/{rid}")["data"]["attributes"]["status"]
    print(f"final: {st}")
    sys.exit(0 if st in ("applied", "planned", "planned_and_finished") else 1)


if __name__ == "__main__":
    main()
