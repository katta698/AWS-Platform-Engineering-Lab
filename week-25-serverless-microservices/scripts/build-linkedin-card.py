# -*- coding: utf-8 -*-
"""Build week 25's LinkedIn card and the standalone architecture diagram.

    python week-25-serverless-microservices/scripts/build-linkedin-card.py
    python scripts/render_card.py week-25-serverless-microservices

The card embeds the SAME diagram the blog post carries, generated from the same
aws_arch source rather than redrawn for social. Week 16's card was produced ad
hoc and its source thrown away, so when it was called not sharp there was
nothing to re-export. Worse than losing the source is a card that disagrees
with the article it links to.

Outputs, beside this file's week folder under docs/linkedin/:
    architecture-diagram.html   authored at 1200x675, rendered at 2x
    architecture-diagram.svg    the diagram alone, vector, for reuse anywhere
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WEEK = os.path.dirname(HERE)
OUT = os.path.join(WEEK, "docs", "linkedin")
sys.path.insert(0, r"C:\Projects\Engineering\katta698-aws\scripts")

from aws_arch import Diagram, RED, MUTED          # noqa: E402

DESC = (
    "Three AWS Lambda functions behind one Amazon API Gateway HTTP API in "
    "us-east-2, sharing one DynamoDB table and one Regional concurrency pool "
    "of 1000. exports reserves 900, leaving 100 unreserved for checkout and "
    "reports to share.")


def diagram():
    d = Diagram(920, 430, DESC)
    d.cloud(14, 14, 892, 402)
    d.group(44, 60, 520, 330, "Region: us-east-2")

    d.icon(72, 150, "user", "User", "20 req/s", size=44)
    d.arrow(124, 172, 168, 172)
    d.step(146, 138, "1")

    d.icon(176, 148, "api-gateway", "API Gateway", "HTTP API", size=48)
    d.arrow(230, 162, 292, 118)
    d.arrow(230, 172, 292, 196)
    d.arrow(230, 182, 292, 276)
    d.step(266, 132, "2")

    d.icon(300, 86, "lambda", "checkout", "50 ms per request", size=48)
    d.icon(300, 176, "lambda", "reports", "10 s per request", size=48)
    d.icon(300, 266, "lambda", "exports", "10 s per request", size=48)

    d.arrow(356, 118, 438, 186)
    d.arrow(356, 200, 438, 200)
    d.arrow(356, 284, 438, 214)
    d.step(402, 142, "3")

    d.icon(446, 176, "dynamodb", "DynamoDB", "one shared table", size=48)
    d.icon(446, 290, "cloudwatch", "CloudWatch", "watches the functions", size=48)

    d.note(600, 86, "REGIONAL CONCURRENCY POOL", weight="700", size=10.5,
           colour=MUTED)
    d.note(600, 104, "1,000 for the account, in this Region", size=11,
           colour=MUTED)
    d.box(600, 118, 286, 38)
    d.note(616, 142, "900  reserved by exports", size=11.5)
    d.box(600, 164, 286, 38, fill="#FDF3F2", stroke=RED)
    d.note(616, 188, "100  unreserved", size=11.5, weight="600", colour=RED)
    d.note(600, 228, "checkout and reports share those 100.", size=11.5)
    d.note(600, 248, "A reservation is subtracted from the pool", size=11,
           colour=MUTED)
    d.note(600, 265, "even while the reserving function is idle.", size=11,
           colour=MUTED)
    d.step(578, 137, "4")
    d.step(578, 183, "5")

    d.assert_clean()
    return d.render(indent="  ")


CARD = """<!doctype html>
<!-- Week 25 LinkedIn architecture card. Generated, not hand-drawn:
     python week-25-serverless-microservices/scripts/build-linkedin-card.py
     Render:  python scripts/render_card.py week-25-serverless-microservices
     Authored at 1200x675, shot at deviceScaleFactor 2 -> 2400x1350.

     The diagram is the one the blog post carries, from the same source, so the
     card cannot drift from the article it links to. -->
<meta charset="utf-8">
<style>
  * {{ box-sizing: border-box }}
  html, body {{ margin: 0; padding: 0 }}
  body {{ width: 1200px; height: 675px; background: #fff; color: #16191f;
         font-family: "Segoe UI", -apple-system, "Helvetica Neue", Arial, sans-serif;
         -webkit-font-smoothing: antialiased; }}
  .board {{ width: 1200px; height: 675px; padding: 26px 34px 20px;
           display: flex; flex-direction: column }}
  .kicker {{ font-size: 12.5px; font-weight: 700; letter-spacing: .09em;
            text-transform: uppercase; color: #FF9900 }}
  h1 {{ font-size: 28px; line-height: 1.15; font-weight: 600; margin: 8px 0 0;
       letter-spacing: -.015em }}
  .sub {{ font-size: 13px; color: #5f6b7a; margin-top: 7px }}
  /* min-height:0 lets a flex child shrink below its content size; without it
     the SVG kept its natural 533px and pushed the footer off the board. */
  .fig {{ flex: 1; min-height: 0; display: flex; align-items: center;
         justify-content: center; margin-top: 10px }}
  .fig svg {{ max-height: 100%; max-width: 100%; width: auto; height: auto;
             border: 0 !important }}
  .foot {{ display: flex; gap: 26px; align-items: baseline;
          border-top: 1px solid #e6e8eb; padding-top: 11px; margin-top: 6px }}
  .m {{ font-size: 12.5px; color: #5f6b7a }}
  .m b {{ font-size: 15px; color: #16191f; font-weight: 650 }}
  .bad b {{ color: #D13212 }}
  .good b {{ color: #1A7F37 }}
</style>
<div class="board">
  <div class="kicker">AWS Platform Engineering Lab &middot; Week 25 of 52</div>
  <h1>The neighbour that starved checkout</h1>
  <div class="sub">Three Lambda functions that never call each other, one
  Regional concurrency pool, and the one attribute that decides who gets a
  slot.</div>
  <div class="fig">
{svg}
  </div>
  <div class="foot">
    <div class="m bad">checkout, sharing the pool &nbsp;<b>5.4% served</b></div>
    <div class="m good">checkout, reserved 50 &nbsp;<b>99.5% served</b></div>
    <div class="m">measured cost &nbsp;<b>$0.81</b>, of which Lambda was <b>$0</b></div>
  </div>
</div>
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    svg = diagram()

    io.open(os.path.join(OUT, "architecture-diagram.html"), "w",
            encoding="utf-8", newline="\n").write(CARD.format(svg=svg))

    # The diagram on its own, vector, for anywhere else it is needed.
    io.open(os.path.join(OUT, "architecture-diagram.svg"), "w",
            encoding="utf-8", newline="\n").write(
        '<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n")

    print("wrote:")
    for f in ("architecture-diagram.html", "architecture-diagram.svg"):
        p = os.path.join(OUT, f)
        print("  %-28s %6d bytes" % (f, os.path.getsize(p)))
    print("\nnow:  python scripts/render_card.py week-25-serverless-microservices")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
