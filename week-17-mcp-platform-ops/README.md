# Week 17 — MCP Server for Platform Operations

**The story:** on 30 August I asked my own AWS account what it was doing. Answering took eleven API calls across Cost Explorer, CloudTrail, Resource Groups Tagging, CloudWatch and Terraform Cloud — and by then a service had been billing $9.35/day for a week. The data existed the whole time. What was missing was a way to ask.

This week builds that way to ask: a **Model Context Protocol server** exposing four read-only tools, so an AI client can answer *"what is running, what is it costing, and did we leave anything behind?"* in one question.

---

## The topic survived; the data source did not

The Year 1 roadmap planned this as a server over Weeks 10–16's own operational data — Athena tables, Config, Security Hub findings. **That data no longer exists.** Those weeks were destroyed on 30 August once their 30-day free trials expired and they began billing, taking the Glue databases, the Config recorder and the findings with them.

Rather than rebuild data that was just deliberately removed, the server reads **live AWS control-plane state**. Same topic, same phase-closing role, and a data source that cannot evaporate.

---

## The four tools

| Tool | Answers | Cost to call |
|---|---|---|
| `get_daily_cost` | What am I being charged for, by service, day by day | **$0.01 per call** |
| `list_running_resources` | What is actually deployed right now | free |
| `find_untagged_resources` | What has no owner | free |
| `get_alarm_state` | Is monitoring actually working | free |

**Every tool is read-only.** The server's IAM role holds exactly one write action — `dynamodb:PutItem` on its own cache table — and no write on anything it reports on. The whole policy is five statements; it is short enough to read in full, and the post does. That is not caution for its own sake: the top risk in current MCP guidance is *tool poisoning*, where instructions hidden in a tool's description or parameter schema steer the model. A read-only server turns that from a destruction risk into a disclosure one.

---

## The cost trap this is built around

**`ce:GetCostAndUsage` bills $0.01 per request, and each page counts as a separate request.** Nearly every other read here is free.

That matters more than the number suggests, because **an LLM decides when to call a tool**. Ask about spend three times in a conversation and you have paid three times. So `get_daily_cost` is cached in DynamoDB with a TTL:

```
CACHE_TTL_SECONDS = 3600
```

Repeat questions inside the hour cost nothing. The cached answer is marked `"_cached": true` so you can see it happen. Losing the cache costs exactly one cent, which is why the table has no point-in-time recovery.

---

## Why a Function URL and not API Gateway

This endpoint answers occasional sub-second questions. A **Lambda Function URL** has no hourly charge and no idle cost, and `AWS_IAM` auth means the caller's existing SSO identity *is* the authorization — no Cognito user pool to run.

The trade is real: the client must sign requests with **SigV4**, so an off-the-shelf MCP client that speaks plain HTTP gets a 403 from Lambda before any of this code runs. `scripts/mcp_client.py` signs correctly.

> **In production**, expose it through API Gateway with an OAuth provider instead. That works with any MCP client, at the cost of two more services. The 2026-07-28 spec revision hardened this path specifically — issuer validation per RFC 9207, issuer-bound client credentials, and Client ID Metadata Documents as the preferred registration route.

**Why not Bedrock AgentCore Runtime?** It bills per vCPU-second for sessions that can live up to 14 days. For a server answering occasional questions that is both dearer and open-ended — the same uncapped-meter shape as the charge that motivated this week. Runtime is the right call for a long-lived stateful agent; this is not that.

---

## Quick start

```bash
# Deploy via HCP (workspace: week-17-dev, VCS-driven)
git push            # HCP plans on push; confirm the apply in the UI or via API

# Then talk to it
URL=$(terraform -chdir=terraform/environments/dev output -raw mcp_endpoint)

python scripts/mcp_client.py "$URL" list
python scripts/mcp_client.py "$URL" call get_daily_cost '{"days": 7}'
python scripts/mcp_client.py "$URL" ask "what did I leave running"
```

---

## Cost

Prices as of September 2026 — verify at [aws.amazon.com/aws-cost-management/pricing](https://aws.amazon.com/aws-cost-management/pricing/).

| Item | Rate | This build |
|---|---|---|
| Cost Explorer API | **$0.01 / request** (each page counts) | the only metered read |
| Lambda | per-request, sub-second calls | pennies |
| DynamoDB | on-demand | pennies |
| CloudWatch alarm | $0.10 / alarm / month | $0.10 |
| Function URL | no hourly charge | **$0 idle** |
| **Destroyed** | | **$0** |

Nothing here bills while idle: no NAT gateway, no API Gateway, no always-on compute.

---

## Cleanup

Queue a destroy from HCP, then verify against AWS rather than trusting the run status:

```bash
./scripts/cleanup.sh
```

It checks Lambda, IAM, DynamoDB, alarms, log groups **and a tag search on `Week=17`** — because a destroy run reporting "applied" only says Terraform removed what it knew about. Two Week 12 buckets survived their teardown by being created outside Terraform, and a tag search is what catches that class of leftover.

---

## Security patterns

- **Read-only where it counts** — the only write in the role is `dynamodb:PutItem` on its own cache table, so a manipulated model can fill a cache but cannot change the account
- **IAM scoped per tool, not per server** — each statement maps to exactly one tool
- **DynamoDB access scoped to the one table**, not to DynamoDB generally
- **`AWS_IAM` auth on the Function URL** — unsigned requests are rejected by Lambda before reaching this code
- **Explicit log retention** — the implicit log group Lambda would create never expires
