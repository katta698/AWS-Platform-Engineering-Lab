# -*- coding: utf-8 -*-
"""Build week 26's LinkedIn card and standalone architecture diagram.

    python week-27-elasticache-valkey/scripts/build-linkedin-card.py
    python scripts/render_card.py week-27-elasticache-valkey

The diagram is imported from the article's own builder so the card and post
cannot drift. Authored at 1200x675, rendered at 2x.
"""
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WEEK = os.path.dirname(HERE)
OUT = os.path.join(WEEK, "docs", "linkedin")
sys.path.insert(0, r"C:\Projects\Engineering\katta698-aws\scripts")

from build_week27_diagram import build            # noqa: E402


CARD = """<!doctype html>
<!-- Week 27 LinkedIn architecture card. Generated, not hand-drawn:
     python week-27-elasticache-valkey/scripts/build-linkedin-card.py
     Render:  python scripts/render_card.py week-27-elasticache-valkey
     Authored at 1200x675, shot at deviceScaleFactor 2 -> 2400x1350.

     The diagram comes from the article's own builder. -->
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
     the SVG keeps its natural height and pushes the footer off the board. */
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
  <div class="kicker">AWS Platform Engineering Lab &middot; Week 27 of 52</div>
  <h1>Twenty thousand requests, three different bills</h1>
  <div class="sub">A cache priced per request would be easy to budget.
  ElastiCache Serverless is priced per kilobyte moved.</div>
  <div class="fig">
{svg}
  </div>
  <div class="foot">
    <div class="m good">20,000 reads of 1 KB &nbsp;<b>20,803 ECPUs</b></div>
    <div class="m bad">20,000 reads of 100 KB &nbsp;<b>2,000,960 ECPUs</b></div>
    <div class="m">same request count &nbsp;<b>96&times;</b> the bill</div>
  </div>
</div>
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    svg = build().render(indent="  ")

    io.open(os.path.join(OUT, "architecture-diagram.html"), "w",
            encoding="utf-8", newline="\n").write(CARD.format(svg=svg))

    io.open(os.path.join(OUT, "architecture-diagram.svg"), "w",
            encoding="utf-8", newline="\n").write(
        '<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n")

    print("wrote:")
    for f in ("architecture-diagram.html", "architecture-diagram.svg"):
        p = os.path.join(OUT, f)
        print("  %-28s %6d bytes" % (f, os.path.getsize(p)))
    print("\nnow:  python scripts/render_card.py "
          "week-27-elasticache-valkey")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
