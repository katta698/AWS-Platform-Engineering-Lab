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

SAFETY: this does NOT do the account-ID redaction capture.py performs. Inspect
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
    args = ap.parse_args()

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
        s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
