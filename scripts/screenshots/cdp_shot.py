"""Screenshot a page in an already-running Chrome, over the raw debug protocol.

    python scripts/screenshots/cdp_shot.py <url> <output.png> [--port 9222]
                                           [--height 1000] [--wait 8]

Why this exists (2026-09-18)
----------------------------
`capture.py --cdp` attaches with Playwright's `connect_over_cdp`. Against
Chrome 152 that opens the websocket and then times out at 180 seconds, every
time -- almost certainly a Playwright/Chrome version mismatch. The consequence
was Week 19's mandatory HCP screenshot going uncaptured while an EKS cluster
billed at $0.22/hr, and my telling Jay to sign into a window that could not
have worked. He pointed out he was already signed in, in Chrome, and he was
right.

Playwright is not required to do this. Chrome's DevTools Protocol takes a
`Page.navigate` and a `Page.captureScreenshot` over one websocket. That is the
whole job. This script is the fallback that needs no version agreement between
two projects.

It deliberately reuses a tab in the user's own signed-in Chrome, so no
credential ever passes through here -- same principle as START_CHROME.md.

SAFETY (changed 2026-09-24): --redact now performs the same DOM text replacement
and post-redaction verification capture.py does, and REFUSES to write the file if
any needle survives. It is required for anything with an inbox, an account id or
an address in it. Without --redact this still writes whatever is on screen, so
inspect
the image before committing it, or pass --expect-no-arns only when the page
provably renders no AWS identifiers.
"""
import argparse
import base64
import json
import sys
import time
import urllib.request

import websocket


def tabs(port):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/json/list", timeout=15) as r:
        return json.load(r)


def pick_tab(port, url):
    """Prefer a tab already on the target host: it is already authenticated,
    and reusing it avoids opening windows in someone's browser."""
    host = url.split("/")[2]
    pages = [t for t in tabs(port) if t.get("type") == "page"]
    for t in pages:
        if host in (t.get("url") or ""):
            return t
    for t in pages:
        if (t.get("url") or "").startswith("chrome://newtab"):
            return t
    if not pages:
        sys.exit("no page targets in Chrome on port %d" % port)
    return pages[0]


class Session:
    def __init__(self, ws_url):
        # suppress_origin is not optional. Chrome 111+ rejects a DevTools
        # websocket that carries an Origin header unless the browser was
        # started with --remote-allow-origins:
        #
        #   Rejected an incoming WebSocket connection from the
        #   http://127.0.0.1:9222 origin.
        #
        # This is almost certainly why `capture.py --cdp` hangs too: the
        # handshake 403s and the client waits out its timeout instead of
        # reporting the rejection. Either suppress the header here, or add
        # --remote-allow-origins=http://127.0.0.1:9222 to the Chrome launch in
        # start-capture-chrome.bat. Doing it here needs no change to how Jay
        # starts his browser.
        self.ws = websocket.create_connection(ws_url, timeout=180,
                                              suppress_origin=True)
        self.n = 0

    def send(self, method, **params):
        self.n += 1
        print("  -> %s" % method, flush=True)
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        # Drain events until the matching reply arrives. CDP interleaves
        # notifications with responses on the same socket.
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    sys.exit("CDP %s failed: %s" % (method, msg["error"]))
                return msg.get("result", {})

    def close(self):
        try:
            self.ws.close()
        except Exception:
            pass



REDACT_JS = """
(function (pairs) {
  var n = 0;
  var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null);
  var nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (var i = 0; i < nodes.length; i++) {
    var node = nodes[i];
    for (var j = 0; j < pairs.length; j++) {
      var find = pairs[j][0], put = pairs[j][1];
      if (node.nodeValue && node.nodeValue.indexOf(find) !== -1) {
        node.nodeValue = node.nodeValue.split(find).join(put);
        n++;
      }
    }
  }
  // A value can be SPLIT ACROSS SIBLING TEXT NODES, so no single nodeValue
  // ever contains it while the rendered line plainly does. Measured on Gmail
  // 2026-09-24: a text-node pass reported zero occurrences left and innerText
  // still showed the account id. Per-node replacement is not enough.
  //
  // So also walk leaf elements -- those with no element children -- and rewrite
  // textContent when the joined text matches. Restricted to leaves so this
  // cannot flatten a subtree and destroy the page's own markup.
  var leaves = document.querySelectorAll('*');
  for (var L = 0; L < leaves.length; L++) {
    var leaf = leaves[L];
    if (leaf.childElementCount !== 0) continue;
    // Gmail enforces Trusted Types: assigning textContent on a SCRIPT throws
    // and aborts the whole pass. These never paint, so skip them outright.
    var tag = leaf.tagName;
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' ||
        tag === 'TEMPLATE' || tag === 'IFRAME') continue;
    var tc = leaf.textContent;
    if (!tc) continue;
    for (var p2 = 0; p2 < pairs.length; p2++) {
      var f3 = pairs[p2][0], r3 = pairs[p2][1];
      if (tc.indexOf(f3) !== -1) {
        leaf.textContent = tc.split(f3).join(r3);
        tc = leaf.textContent;
        n++;
      }
    }
  }

  // Last resort: a value split across SIBLING ELEMENTS, so no leaf and no text
  // node holds it whole, yet the rendered line reads it plainly. Measured on
  // Gmail 2026-09-24: the account id survived both passes above while
  // innerText still showed it.
  //
  // Find the DEEPEST element whose text contains the value -- deepest, so the
  // rewrite touches the smallest possible subtree -- then rewrite its text
  // descendants together: the first carries the replaced string, the rest are
  // emptied. This flattens styling inside that one element and nothing else.
  var SKIP = {SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEMPLATE: 1, IFRAME: 1};
  for (var q = 0; q < pairs.length; q++) {
    var need = pairs[q][0], rep = pairs[q][1];
    for (var guard = 0; guard < 50; guard++) {
      var every = document.body.querySelectorAll('*');
      var target = null;
      for (var e = 0; e < every.length; e++) {
        var el2 = every[e];
        if (SKIP[el2.tagName]) continue;
        if ((el2.textContent || '').indexOf(need) === -1) continue;
        var deeper = false;
        for (var c = 0; c < el2.children.length; c++) {
          if (!SKIP[el2.children[c].tagName] &&
              (el2.children[c].textContent || '').indexOf(need) !== -1) {
            deeper = true; break;
          }
        }
        if (!deeper) { target = el2; break; }
      }
      if (!target) break;

      var tw = document.createTreeWalker(target, NodeFilter.SHOW_TEXT, null);
      var tnodes = [];
      while (tw.nextNode()) {
        if (!SKIP[tw.currentNode.parentElement ? tw.currentNode.parentElement.tagName : '']) {
          tnodes.push(tw.currentNode);
        }
      }
      if (!tnodes.length) break;
      var joined = '';
      for (var z = 0; z < tnodes.length; z++) joined += tnodes[z].nodeValue;
      if (joined.indexOf(need) === -1) break;
      tnodes[0].nodeValue = joined.split(need).join(rep);
      for (var z2 = 1; z2 < tnodes.length; z2++) tnodes[z2].nodeValue = '';
      n++;
    }
  }

  // Attributes carry the same values on Gmail -- title, aria-label, alt, data-*
  // all repeat the address, and a tooltip rendered from one of them lands in
  // the screenshot even though no text node ever held it.
  var all = document.querySelectorAll('*');
  for (var k = 0; k < all.length; k++) {
    var el = all[k];
    for (var a = 0; a < el.attributes.length; a++) {
      var attr = el.attributes[a];
      for (var j2 = 0; j2 < pairs.length; j2++) {
        var f = pairs[j2][0], pv = pairs[j2][1];
        if (attr.value && attr.value.indexOf(f) !== -1) {
          attr.value = attr.value.split(f).join(pv);
          n++;
        }
      }
    }
  }
  for (var m = 0; m < all.length; m++) {
    var inp = all[m];
    if ((inp.tagName === 'INPUT' || inp.tagName === 'TEXTAREA') && inp.value) {
      for (var j3 = 0; j3 < pairs.length; j3++) {
        var f2 = pairs[j3][0], pv2 = pairs[j3][1];
        if (inp.value.indexOf(f2) !== -1) {
          inp.value = inp.value.split(f2).join(pv2);
          n++;
        }
      }
    }
  }
  return n;
})(PAIRS)
"""

VERIFY_JS = """
(function (needles) {
  // Check what is PAINTED, not the raw source. Gmail embeds the signed-in
  // address in inline <script> JSON many times over; that text is never
  // rendered, and failing on it means this guard can never pass on an inbox --
  // a check that always fails gets bypassed, which is worse than no check.
  //
  // So: rendered text, plus the attributes that actually surface (title,
  // aria-label, alt, placeholder, value), and nothing from script or style.
  var clone = document.body.cloneNode(true);
  var drop = clone.querySelectorAll('script,style,noscript,template');
  for (var d = 0; d < drop.length; d++) drop[d].parentNode.removeChild(drop[d]);

  var surfaces = [clone.innerText || '', clone.textContent || ''];
  var VISIBLE = ['title', 'aria-label', 'alt', 'placeholder', 'value', 'aria-labelledby'];
  var all = clone.querySelectorAll('*');
  for (var k = 0; k < all.length; k++) {
    for (var v = 0; v < VISIBLE.length; v++) {
      var got = all[k].getAttribute(VISIBLE[v]);
      if (got) surfaces.push(got);
    }
  }
  var hay = surfaces.join(String.fromCharCode(10));

  var left = [];
  for (var i = 0; i < needles.length; i++) {
    if (hay.indexOf(needles[i]) !== -1) left.push(needles[i]);
  }
  return JSON.stringify(left);
})(NEEDLES)
"""


def parse_redactions(items):
    """--redact 'find=>replacement', repeatable. Returns a list of pairs."""
    pairs = []
    for it in items or []:
        if "=>" in it:
            find, put = it.split("=>", 1)
        else:
            find, put = it, "<redacted>"
        find = find.strip()
        if find:
            pairs.append([find, put.strip()])
    return pairs


def apply_redactions(s, pairs, attempts=4, settle=1.3):
    """Replace, then PROVE the replacement worked. Never assume it did.

    Running a redactor and checking the result are different things. capture.py
    learned that on the Week 14 HCP leak; this path had no equivalent at all,
    which is why it was only ever safe on pages that contained nothing.

    Why it loops (2026-09-24): a single pass failed on Gmail. Not because the
    replacement does not work -- measured on the live page it replaced five
    occurrences and left zero, in the main document and all six iframes -- but
    because Gmail streams the message body in progressively, so content can
    arrive in the gap between replacing and checking. Redacting once and
    trusting it is the same mistake as redacting and not checking, one step
    later. So: replace, let the page settle, check, repeat until a pass finds
    nothing new. If it never converges, refuse.
    """
    if not pairs:
        return
    import time as _t
    expr = REDACT_JS.replace("PAIRS", json.dumps(pairs))
    needles = [f for f, _ in pairs]
    verify = VERIFY_JS.replace("NEEDLES", json.dumps(needles))

    left = None
    for attempt in range(attempts):
        rr = s.send("Runtime.evaluate", expression=expr, returnByValue=True)
        # Check the REDACTOR, not just the verifier. A JS error here returns a
        # perfectly normal-looking response and replaces nothing; the run then
        # fails at verification and every symptom points at the page instead of
        # at the broken script. Two hours of 2026-09-24 went that way.
        if "exceptionDetails" in rr:
            raise SystemExit(
                "REFUSING TO WRITE: the redaction script itself threw: %s"
                % json.dumps(rr.get("exceptionDetails"))[:300])
        print("  pass %d: replaced %s occurrence(s)"
              % (attempt + 1, rr.get("result", {}).get("value")))
        _t.sleep(settle)
        res = s.send("Runtime.evaluate", expression=verify, returnByValue=True)
        if "exceptionDetails" in res or "value" not in res.get("result", {}):
            raise SystemExit(
                "REFUSING TO WRITE: the redaction check itself failed to run. "
                "An unverified redaction is not a redaction: %s"
                % json.dumps(res)[:300])
        left = json.loads(res["result"]["value"])
        if not left:
            print("Redacted %d value(s) and verified none remain (pass %d)"
                  % (len(pairs), attempt + 1))
            return

    raise SystemExit(
        "REFUSING TO WRITE: these values are still on the page after %d "
        "redaction passes: %s" % (attempts, ", ".join(repr(x[:6] + "...") for x in left)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("output")
    ap.add_argument("--port", type=int, default=9222)
    ap.add_argument("--height", type=int, default=1000)
    ap.add_argument("--width", type=int, default=1600)
    ap.add_argument("--scale", type=float, default=2.0,
                    help="deviceScaleFactor; 2 keeps text sharp on a phone")
    ap.add_argument("--wait", type=float, default=8.0,
                    help="seconds to let the page settle after load")
    ap.add_argument("--new-tab", action="store_true",
                    help="open a fresh tab instead of reusing one -- never "
                         "navigate a tab the user is working in")
    ap.add_argument("--redact", action="append", metavar="FIND=>PUT",
                    help="replace FIND with PUT everywhere on the page before "
                         "capturing, then refuse to write if any survives. "
                         "Repeatable. Required for inboxes and anything "
                         "carrying an account id or an address.")
    args = ap.parse_args()

    own_tab = False
    if args.new_tab:
        # Do not navigate a tab somebody else is using. On 2026-09-24 this
        # attached to a live AWS SSO login tab in another project's browser and
        # navigated it away mid-flow.
        import urllib.request, urllib.parse as _up
        req = urllib.request.Request(
            "http://127.0.0.1:%d/json/new?%s" % (args.port, _up.quote(args.url, safe="")),
            method="PUT")
        with urllib.request.urlopen(req, timeout=30) as r:
            tab = json.loads(r.read().decode("utf-8"))
        own_tab = True
        time.sleep(2.0)
    else:
        tab = pick_tab(args.port, args.url)
    print("attaching to tab %s (%s)" % (tab["id"][:12], (tab.get("url") or "")[:50]))

    s = Session(tab["webSocketDebuggerUrl"])
    try:
        # Page.enable is not needed just to navigate and shoot, and on an
        # attached browser it starts a firehose of lifecycle events that the
        # simple request/response loop below has to wade through.
        # No Emulation.setDeviceMetricsOverride. capture.py's own comment says
        # an attached Chrome owns its window size, and overriding metrics on a
        # real browser window is what hung the first attempt.
        s.send("Page.navigate", url=args.url)
        time.sleep(args.wait)

        # Page.captureScreenshot needs the compositor to produce a frame, and a
        # backgrounded or minimised window produces none -- the call simply
        # never returns. Navigate succeeded and the capture hung, which is
        # exactly that symptom. bringToFront makes the tab active first.
        #
        # This does move the user's browser to the foreground. That is the
        # trade for using a real signed-in Chrome instead of an automated one,
        # and it is visible and momentary rather than surprising.
        s.send("Page.bringToFront")
        time.sleep(1.5)

        # Only NOW override the viewport. Doing this before bringToFront hung
        # the first attempt -- a backgrounded window cannot produce the frame
        # the resize needs. Order matters and the failure is a silent hang
        # rather than an error.
        #
        # Without this the capture is however wide the user left their window,
        # which on the first successful shot clipped the HCP run statuses off
        # the right edge. A screenshot whose content depends on someone's
        # window size is not reproducible evidence.
        s.send("Emulation.setDeviceMetricsOverride", width=args.width,
               height=args.height, deviceScaleFactor=args.scale, mobile=False)
        time.sleep(2.5)

        pairs = parse_redactions(args.redact)
        if pairs:
            # Freeze the page before rewriting it. Gmail rebuilds its DOM
            # continuously, so a redaction applied to a live page is undone
            # before the verification runs -- measured on 2026-09-24: a pass
            # replaced every occurrence, a scan immediately after found none,
            # and the check a second later found them back. Racing a framework
            # is not a redaction strategy.
            #
            # With script execution off, the DOM stops changing, so what is
            # verified is exactly what gets painted.
            s.send("Emulation.setScriptExecutionDisabled", value=True)
            time.sleep(1.0)
        apply_redactions(s, pairs)

        shot = s.send("Page.captureScreenshot", format="png", captureBeyondViewport=False)
        data = base64.b64decode(shot["data"])
        with open(args.output, "wb") as fh:
            fh.write(data)

        # Report what was actually on screen, so a login page or an error page
        # is obvious from the terminal rather than discovered in the blog.
        res = s.send("Runtime.evaluate",
                     expression="JSON.stringify({u:location.href,t:document.title})",
                     returnByValue=True)
        info = json.loads(res["result"]["value"])
        print("captured: %s" % info["t"][:70])
        print("     url: %s" % info["u"][:90])
        print("   wrote: %s (%d bytes)" % (args.output, len(data)))
        low = (info["u"] + " " + info["t"]).lower()
        # "sign-in" with the hyphen is what AWS actually titles its page --
        # "Amazon Web Services Sign-In" slipped straight past the first
        # version of this list.
        if any(w in low for w in ("sign in", "sign-in", "signin",
                                  "log in", "login", "accounts.google")):
            print("WARNING: this looks like a sign-in page. Check the image "
                  "before using it -- Week 15 shipped two of those.")
            return 1
    finally:
        # Put the browser back the way it was found.
        try:
            s.send("Emulation.clearDeviceMetricsOverride")
        except Exception:
            pass
        try:
            s.send("Emulation.setScriptExecutionDisabled", value=False)
        except Exception:
            pass
        s.close()
        if own_tab:
            try:
                import urllib.request
                urllib.request.urlopen(
                    "http://127.0.0.1:%d/json/close/%s" % (args.port, tab["id"]),
                    timeout=15).close()
            except Exception:
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
