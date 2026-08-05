# Week 13 — AWS WAF + Shield Standard

**The story:** an internet-facing endpoint gets hit by traffic nobody wrote code for — path scanners, Log4Shell probes, and single IPs firing thousands of requests a minute. This week puts a firewall in front of it at two layers, starts every rule in observation mode, and only then decides what to block.

---

## Shield Standard is not something you deploy

There is no Terraform resource for AWS Shield Standard. There is no console toggle. It is already active on every AWS account at no charge, protecting CloudFront, Route 53, Global Accelerator, and Elastic Load Balancing against layer 3 and 4 volumetric attacks — SYN floods, UDP reflection — and AWS reports mitigating over 99% of those in under a second.

What Shield Standard does *not* do is inspect HTTP. An attacker sending well-formed requests at 10,000/minute, or a single request carrying an SQL injection payload, is invisible to it. That is layer 7, and layer 7 is AWS WAF's job.

The common failure is teams concluding they need Shield Advanced — **$3,000/month with a one-year commitment** — for DDoS protection, deciding it is out of budget, and doing nothing. For application-layer DDoS, the WAF Anti-DDoS managed rule group costs **$1/month** and is what this build uses.

> **Timely, as of August 2026:** AWS is retiring Shield Advanced's *automatic application-layer mitigation* on **1 January 2027**, migrating subscribers to this same Anti-DDoS managed rule group. Auto-upgrade began 1 October 2026. If you run Shield Advanced today and rely on automatic L7 mitigation, this is a live migration deadline.

---

## Architecture

```
                    Internet
                       |
        [ Shield Standard — L3/L4, free, always on ]
                       |
                       v
          CloudFront distribution
                       |
          <- CLOUDFRONT-scope web ACL (edge)
                       |
                       v
          API Gateway REST API (stage: prod)
                       |
          <- REGIONAL-scope web ACL (origin)
                       |
                       v
              Lambda echo function
```

**Why two web ACLs.** An edge-only WAF protects only the requests that go through CloudFront. The API Gateway invoke URL stays publicly reachable, so anyone who finds it bypasses the edge entirely. The regional ACL makes that bypass pointless — and the attack simulation tests both paths to prove it.

---

## Rules, in evaluation order

WAF evaluates by ascending priority and stops at the first terminating action, so the cheapest and most definitive checks run first.

| Priority | Rule | WCU | What it catches |
|---|---|---|---|
| 10 | Break-glass IP set | 1 | Specific attacker addresses, added during an incident |
| 20 | Rate-based, 60s window | 2 | Volumetric abuse of otherwise-legitimate requests |
| 30 | `AWSManagedRulesCommonRuleSet` | 700 | OWASP-class: XSS, LFI/RFI, SSRF-to-IMDS, size limits |
| 40 | `AWSManagedRulesKnownBadInputsRuleSet` | 200 | Log4Shell, Java deserialization RCE, exploitable paths |
| 50 | `AWSManagedRulesAntiDDoSRuleSet` | 50 | Adaptive L7 DDoS with silent browser challenges |

**~953 WCU of the 1500 included in the base price**, so no WCU overage charge. This is where WAF costs surprise people: exceed 1500 and you pay $0.20 per million requests for each additional 500 WCU.

### Two design choices worth explaining

**`evaluation_window_sec = 60`, not the 300 default.** WAF re-checks the rate roughly every 10 seconds either way, but a 5-minute lookback averages an attacker's burst across five minutes before it crosses the threshold. A 60-second window treats a burst as a burst.

**`aggregate_key_type = "IP"` is right here and wrong for many real apps.** Users behind a shared corporate NAT all present one source IP, so IP aggregation throttles the entire office together. The fix is `CUSTOM_KEYS` over a session identifier — the provider also supports ASN and JA3/JA4 TLS fingerprints as aggregation keys.

---

## Count mode first — this is the point of the week

Every rule deploys with `count_mode = true`. In Count mode WAF records what each rule *would* have done and blocks nothing.

This is not caution for its own sake. `AWSManagedRulesCommonRuleSet` blocks request bodies over 8KB and query strings over 2,048 bytes — a legitimate file upload or a rich-text form field trips it. Teams enable WAF in Block mode, get paged, and disable it entirely. That is why so many accounts have a web ACL that protects nothing.

The rollout:

1. Deploy with `count_mode = true`
2. Run the attack simulation and real traffic
3. Review `CountedRequests` per rule and the WAF logs
4. Add `rule_action_override` for any rule catching legitimate traffic
5. Set `count_mode = false` and re-apply

A subtlety the monitoring module handles: during Count mode `BlockedRequests` stays flat at zero, so an alarm on it reports "all clear" while rules are matching heavily. There is a separate `CountedRequests` alarm for exactly this reason.

**Rule actions:**

| Action | Effect | Use for |
|---|---|---|
| Count | Allowed; match recorded | Testing |
| Block | 403 at the edge | Enforcement, once trusted |
| Challenge | Silent JS challenge; real browsers pass invisibly | Bot/DDoS traffic where false positives are costly |
| CAPTCHA | Visible puzzle | Last resort — user-hostile |

---

## Layout

```
week-13-waf-shield-protection/
├── lambda/echo_api/handler.py
├── scripts/
│   ├── attack_simulation.sh
│   └── cleanup.sh
└── terraform/
    ├── environments/dev/
    └── modules/
        ├── waf/              ← one web ACL + rules + logging (used twice)
        ├── protected_app/    ← Lambda + REST API + CloudFront
        └── monitoring/       ← SNS + alarms (used twice)
```

## Quick start

Deployed via HCP Terraform (workspace `week-13-dev`, VCS-driven). Push to `main`; if no run appears within ~30s, queue one from the HCP UI.

`alert_email` comes from the global HCP variable set `shared-alert-email` — do not put it in a tfvars file.

```bash
terraform output
```

Then run the simulation against your own endpoints:

```bash
./scripts/attack_simulation.sh "$(terraform output -raw cloudfront_url)" "$(terraform output -raw api_invoke_url)"
```

Every payload is a signature string sent to an echo Lambda that does nothing but reflect its input. There is no third-party target.

---

## Cost

Prices as of August 2026 — verify at [aws.amazon.com/waf/pricing](https://aws.amazon.com/waf/pricing/).

| Item | Monthly |
|---|---|
| Web ACL × 2 | $10.00 |
| Rules × 5 per ACL × 2 | $10.00 |
| Requests | $0.60 / million |
| WCU overage | $0 (~953 of 1500 used) |
| CloudFront, API Gateway, Lambda | ~$0 at demo volume |
| Shield Standard | $0 — always on |
| **If left running** | **~$20** |
| **Destroyed** | **$0** |

**WAF charges are prorated hourly.** The $5/web ACL and $1/rule are monthly *rates*, not minimums — build, test, and destroy in a day and the whole exercise costs well under a dollar. Shield Advanced, by contrast, is $3,000/month on a one-year commitment and cannot be prorated away.

---

## Security notes

- **WAF logs are redacted.** `authorization`, `cookie`, and `x-api-key` headers are dropped before logging. A WAF log records the request it inspected, which means it records credentials unless told otherwise — the security control becoming the disclosure vector.
- **The echo function redacts too.** It never reflects sensitive headers back, and truncates values. An echo endpoint is a classic accidental-disclosure primitive.
- **A per-web-ACL log resource policy** instead of the shared account-wide `AWSWAF-LOGS` policy, which can exceed maximum policy size in accounts with many web ACLs and cause logging configs to fail to create.
- **Default action is Allow.** A WAF fronting a general web application blocks by exception; a default-deny posture would require enumerating every legitimate request shape up front.
- **Log retention is 7 days.** WAF writes one record per inspected request.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `terraform plan` fails with "No valid credential sources found" | New HCP workspace missing `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` |
| Logging config rejected | Log group name must start with `aws-waf-logs-`, and live in the web ACL's region and account |
| Alarm stuck in `INSUFFICIENT_DATA` | Wrong `Region` metric dimension — `Global` for CLOUDFRONT scope, the region name for REGIONAL |
| Web ACL healthy but inspects nothing | Regional resources need `aws_wafv2_web_acl_association`; only CloudFront takes the ACL as an attribute |
| `GET /` returns 403 "Missing Authentication Token" | Not a WAF block — REST APIs need the root path defined separately from `{proxy+}` |
| WAF can't be associated with the API | It must be a REST API; **HTTP APIs are not supported by WAF at all** |
| `aws logs` fails on a `/`-prefixed argument | Git Bash path rewriting — prefix with `MSYS_NO_PATHCONV=1` |
| Web ACL won't delete | Still associated with a resource; CloudFront must also be disabled and fully propagated (~15 min) |

## Blog

Published: _(pending)_
