"""Queue an HCP Terraform destroy run for a workspace, and report the run id.

Written 2026-08-30 after Weeks 11 and 12 were found still live five weeks
after their posts shipped -- their Security Hub, GuardDuty and Config free
trials had expired and started billing. Destroying from the API keeps the
teardown a recorded action rather than a console click nobody can trace.
"""
import io, json, os, sys, urllib.request

ORG = "Katta"


def token():
    p = os.path.expandvars(r"%APPDATA%\terraform.d\credentials.tfrc.json")
    return json.loads(io.open(p, encoding="utf-8-sig").read())["credentials"]["app.terraform.io"]["token"]


def api(url, tok, data=None):
    req = urllib.request.Request(
        url, headers={"Authorization": "Bearer " + tok, "Content-Type": "application/vnd.api+json"},
        data=json.dumps(data).encode() if data else None)
    return json.load(urllib.request.urlopen(req))


def main():
    tok = token()
    for ws in sys.argv[1:]:
        w = api(f"https://app.terraform.io/api/v2/organizations/{ORG}/workspaces/{ws}", tok)
        wid = w["data"]["id"]
        rc = w["data"]["attributes"]["resource-count"]
        if not rc:
            print(f"{ws}: already 0 resources, skipping")
            continue
        body = {"data": {"type": "runs",
                         "attributes": {"is-destroy": True,
                                        "message": "Teardown: left running after publish; billing began when free trials expired"},
                         "relationships": {"workspace": {"data": {"type": "workspaces", "id": wid}}}}}
        r = api("https://app.terraform.io/api/v2/runs", tok, body)
        print(f"{ws}: {rc} resources -> destroy run {r['data']['id']}")


if __name__ == "__main__":
    main()
