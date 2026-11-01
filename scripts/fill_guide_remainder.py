#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""The last nine sections, each written from something checkable.

    python scripts/fill_guide_remainder.py --write

Nine gaps remained after the derivable sections were filled. Each is handled
here rather than by a general rule, because each needed looking at:

  3. Deploy for weeks 16, 18, 19, 20, 21
      None of them ships a deploy.sh, because none of them is deployed from a
      CLI. Each has a cloud {} block naming workspace week-NN-dev in
      organization Katta -- checked in that week's own terraform -- and a
      VCS-connected workspace refuses `terraform apply` from a checkout. The
      procedure is therefore: push, then confirm the run. That is the same
      thing weeks 5, 6 and 13 already say in prose.

  6. Cleanup for week 16
      No cleanup.sh either. Destroy is queued from the same workspace.

  Troubleshooting for week 9
      Its article writes troubleshooting as headings plus prose rather than
      in the Problem/Root cause form, so the general carry-across found
      nothing. Carried here as heading plus first paragraph.

  Cost for weeks 1 and 25
      Week 1's article gives a per-resource estimate and no measured total;
      week 25's measured figure is in its article's Security and Cost
      section rather than in a table the carry-across reads.
"""
from __future__ import annotations

import argparse
import html
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import fill_guide_from_post as P          # noqa: E402

ORDER = P.ORDER

DEPLOY_HCP = """The workspace is VCS-connected, so an apply does not run from a
checkout: `terraform apply` is refused with
`Error: Apply not allowed for workspaces with a VCS connection`.

```bash
# on the connected branch
git push
```

The push queues a plan in the `%s` workspace (organization `Katta`). Confirm
the apply on its run page."""

CLEANUP_HCP = """Queue a destroy from the same workspace: **Settings &rarr;
Destruction and Deletion &rarr; Queue destroy plan**, then confirm it.

Verify afterwards rather than trusting the destroy output &mdash; a destroy
reports what Terraform removed, not what is left in the account."""

TARGETS = {
    "week-16-devops-agent-investigations": [("3. Deploy", "week-16-dev"),
                                            ("6. Cleanup", None)],
    "week-18-eks-self-service": [("3. Deploy", "week-18-dev")],
    "week-19-gitops-argocd": [("3. Deploy", "week-19-dev")],
    "week-20-eventbridge-accountable-bus": [("3. Deploy", "week-20-dev")],
    "week-21-bluegreen-ecs": [("3. Deploy", "week-21-dev")],
}


def cost_from_article(num):
    post = P.post_text(num)
    if post is None:
        return None
    sec = P.section(post, "security-cost")
    if not sec:
        return None
    m = re.search(r"<table.*?</table>", sec, re.S)
    rows = P.rows_of(m.group(0)) if m else []
    money = [r for r in rows if any("$" in c for c in r)]
    out = []
    if money:
        out.append(P.table_md([rows[0]] + money))
    sentences = [s.strip() for s in
                 re.split(r"(?<=[.!?])\s", P.md(sec)) if "$" in s]
    if sentences:
        out.append(sentences[-1])
    return "\n\n".join(out) if out else None


def insert(text, heading, body):
    after = ORDER[ORDER.index(heading) + 1:]
    block = "\n## %s\n\n%s\n" % (heading, body)
    for nxt in after:
        m = re.search(r"^##\s+%s\b" % re.escape(nxt), text, re.M)
        if m:
            return text[:m.start()].rstrip() + "\n" + block + "\n" + text[m.start():]
    return text.rstrip() + "\n" + block


def troubleshooting_prose(num):
    post = P.post_text(num)
    sec = P.section(post, "troubleshooting") if post else None
    if not sec:
        return None
    out = []
    for m in re.finditer(r"<h3>(.*?)</h3>\s*<p>(.*?)</p>", sec, re.S):
        title, first = P.md(m.group(1)), P.md(m.group(2))
        if title:
            out.append("**%s**\n%s" % (title.rstrip("."), first))
    return "\n\n".join(out) if out else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    jobs = []
    for wd, items in TARGETS.items():
        for heading, ws in items:
            body = (DEPLOY_HCP % ws) if heading == "3. Deploy" else CLEANUP_HCP
            jobs.append((wd, heading, body))
    jobs.append(("week-09-ecs-fargate-self-service", "Troubleshooting",
                 troubleshooting_prose(9)))
    jobs.append(("week-01-enterprise-ec2-provisioning", "Cost",
                 cost_from_article(1)))
    jobs.append(("week-25-serverless-microservices", "Cost",
                 cost_from_article(25)))

    for wd, heading, body in jobs:
        p = os.path.join(ROOT, wd, "README.md")
        if not body:
            print("  %-40s %-18s NO SOURCE - left missing" % (wd, heading))
            continue
        text = io.open(p, encoding="utf-8").read()
        pat = r"^##\s+%s\b" % re.escape(heading)
        if re.search(pat, text, re.M):
            print("  %-40s %-18s already present" % (wd, heading))
            continue
        text = insert(text, heading, body)
        if a.write:
            io.open(p, "w", encoding="utf-8", newline="\n").write(text)
        print("  %-40s %-18s %s" % (wd, heading,
                                    "written" if a.write else "would write"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
