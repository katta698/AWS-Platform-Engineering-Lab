"""Queue an HCP Terraform destroy run for a workspace, and report the run id.

Written 2026-08-30 after Weeks 11 and 12 were found still live five weeks
after their posts shipped -- their Security Hub, GuardDuty and Config free
trials had expired and started billing. Destroying from the API keeps the
teardown a recorded action rather than a console click nobody can trace.
"""
import io, json, os, sys, urllib.request

# The run message is printed on the HCP run page and ends up in screenshots.
#
# This used to be hardcoded to "Teardown: left running after publish; billing
# began when free trials expired" -- true of Week 16, false of every week
# since, and it appeared verbatim on Week 19's destroy run where nothing
# involved a free trial. A stale default that describes a different week is a
# caption that lies, and it lies in the one artefact a reader is most likely
# to trust.
DEFAULT_MSG = "Teardown: scheduled destroy at end of build window"

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
    # Optional trailing --message "..." so a week can say what it is tearing
    # down. Anything else on the command line is a workspace name.
    argv = sys.argv[1:]
    msg = DEFAULT_MSG
    if "--message" in argv:
        i = argv.index("--message")
        msg = argv[i + 1] if i + 1 < len(argv) else DEFAULT_MSG
        argv = argv[:i] + argv[i + 2:]

    tok = token()
    for ws in argv:
        w = api(f"https://app.terraform.io/api/v2/organizations/{ORG}/workspaces/{ws}", tok)
        wid = w["data"]["id"]
        rc = w["data"]["attributes"]["resource-count"]
        if not rc:
            print(f"{ws}: already 0 resources, skipping")
            continue
        body = {"data": {"type": "runs",
                         "attributes": {"is-destroy": True,
                                        "message": msg},
                         "relationships": {"workspace": {"data": {"type": "workspaces", "id": wid}}}}}
        r = api("https://app.terraform.io/api/v2/runs", tok, body)
        print(f"{ws}: {rc} resources -> destroy run {r['data']['id']}")


if __name__ == "__main__":
    main()
