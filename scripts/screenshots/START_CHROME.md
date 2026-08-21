# Automated screenshots of sites behind Google sign-in (HCP Terraform)

## The problem

HCP Terraform signs in through Google. **Google refuses to authenticate inside an
automation-controlled browser** — it returns *"This browser or app may not be
secure."* So `capture.py`'s normal mode (a Playwright-launched Chromium with a
persistent profile) can log in to AWS and ServiceNow, but **can never log in to
HCP again** once its session lapses.

That session lapsed between Week 14 and Week 15 (2026-08-19). Two Week 15 figures
shipped as pictures of the HCP login form before anyone noticed, because nothing
was checking whether the captured page was the page that had been asked for.

Weeks 05–08 HCP screenshots were taken by hand. Weeks 09–14 were automated, on the
strength of a single login performed around 11 July that persisted for five weeks.

## The fix: attach to a real Chrome instead of launching one

Google objects to the *browser*, not the automation. Playwright's bundled Chromium
is un-branded and starts with automation switches set, and `navigator.webdriver`
is true. A normal Chrome that merely has a debugging port open looks like what it
is — a normal Chrome — so Google's check passes.

**No password ever passes through these scripts.** You sign in yourself, in your
own browser; `capture.py` only attaches to it afterwards.

## One-time setup

Start a dedicated Chrome with a debugging port. This uses a **separate profile
directory** — Chrome refuses `--remote-debugging-port` against your default
profile, and keeping it separate means automation never touches your day-to-day
browser, bookmarks or cookies.

```bat
"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" ^
  --remote-debugging-port=9222 ^
  --user-data-dir="C:\Users\katta\chrome-automation-profile"
```

In that window, sign in once to whatever the week needs — HCP Terraform, and the
AWS console if you want console captures through the same browser.

**Leave the window open** while screenshots are being taken. The profile persists,
so re-launching later keeps you signed in until the provider expires the session.

## Taking a screenshot through it

```bash
python scripts/screenshots/capture.py \
  "https://app.terraform.io/app/katta/workspaces/week-16-dev/runs" \
  week-16-.../docs/blog/screenshots/01-hcp-runs.png \
  --cdp 9222 --wait-ms 8000 --height 1100
```

Everything else behaves identically — account-ID redaction, member-account
redaction, the leak assertions, and the login-page guard all still run. The only
difference is where the browser came from.

`capture.py` closes only the tab it opened. Your Chrome, your session and your
other tabs are left alone.

## When it stops working again

The session will lapse eventually — that is normal and not a bug. The symptom is
the login-page guard refusing to save:

```
REFUSING TO SAVE: this looks like a sign-in page
```

Sign in again in the Chrome window above. Nothing else needs changing.
