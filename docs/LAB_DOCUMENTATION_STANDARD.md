# Cloud Engineering Lab — Documentation Standard

Issued by Jay, 2026-10-25. **Applies to all three series: AWS, Azure and GCP.**

This supersedes the previous ten-section weekly template for any lab published
from this date. Where the two disagree, this document wins.

**Primary principle: clarity over volume. Technical depth without unnecessary
complexity.**

---

## 1. Target audience

- The reader understands basic cloud computing but may not know the specific
  services used.
- Explain essential concepts without turning the lab into a theory article.
- **The reader should understand the purpose of the lab within the first minute.**

## 2. Mandatory document structure

In this order:

| # | Section | Must contain |
|---|---------|--------------|
| 1 | **Lab Overview** | Clear descriptive title; problem being solved; objective and expected outcome; difficulty and approximate completion time; deployment method and source repository |
| 2 | **Cloud Services Used** | A compact table: service name, purpose *in this architecture*, brief plain-English definition. Only services actually used |
| 3 | **Architecture and Workflow** | One clean readable diagram with provider-appropriate names/icons; application, network, identity, security and observability boundaries where relevant; the flow in **4–7 numbered steps**; major architectural decisions and their reasons |
| 4 | **Prerequisites** | Accounts/subscriptions/projects and permissions; software and versions; existing infrastructure dependencies; region assumptions and important quotas; prerequisite work from earlier labs |
| 5 | **Step-by-Step Implementation** | In deployment order. Per step: title, what we are doing, why it is required, the essential command or configuration, expected result / validation checkpoint, screenshot guidance if useful |
| 6 | **Validation and Evidence** | Test command or procedure; expected result; **actual observed result**; supporting screenshot or output; what the evidence proves |
| 7 | **Security and Cost** | Security decisions and cost, per the detail below |
| 8 | **Troubleshooting** | **Problem → Root cause → Resolution → Lesson learned** |
| 9 | **Cleanup** | Destruction commands; how to verify removal; shared infrastructure to preserve; anything that may keep charging |
| 10 | **Key Takeaways and References** | 3–5 specific technical lessons; links to vendor docs, Terraform provider docs, source repo, reference material |

### Section 5 — hard rules

- Use Terraform for provisioning where appropriate.
- **Do NOT paste into the main article:** full Terraform files, lengthy source
  code, full terminal outputs, or repository trees. **Link to the GitHub files
  instead.**
- Small code snippets **only** when they teach a significant architectural or
  implementation decision.

### Section 6 — evidence

- **Distinguish successful deployment from successful functional validation.**
  They are different claims.
- **Never invent test results, screenshots, costs, or deployment evidence.**

### Section 7 — security and cost

Security: IAM/RBAC and least privilege; identity and secrets management; network
exposure; encryption and data protection; logging and observability; risks,
limitations and accepted trade-offs.

Cost: which services charge; estimated cost and pricing assumptions; **actual
measured cost if available**; free-tier dependencies and limits; optimisation
opportunities.

### Section 8 — troubleshooting

Only meaningful problems or real reproducibility risks. **Keep unrelated
implementation history and debugging experiments out of the main deployment
flow.**

## 3. Writing rules

1. Direct, practical engineering language.
2. Short paragraphs, meaningful headings.
3. Define unfamiliar terminology at first use.
4. Explain **why** a service or setting exists, not only what it does.
5. No unnecessary history, repetition, marketing language or broad explanation.
6. One concept at a time.
7. Tables only where they simplify comparison.
8. Keep architecture and implementation connected.
9. Keep troubleshooting separate from the implementation steps.
10. Useful both to readers and to engineers following along.

## 4. Screenshot standards

Use a screenshot only when it is **evidence** or makes a procedure significantly
clearer. Each one needs:

- a clear purpose
- readable content
- a short caption
- an explanation of what it validates

**Prefer cropped screenshots** showing the relevant setting or output. **Avoid
screenshots that merely show navigation, terminal clutter, or unimportant status
messages.** Never fabricate images or results.

> Reconciles with the 2026-10-25 instruction on real terminal captures: when
> terminal output *is* the right evidence, it must be a genuine capture
> (`scripts/screenshots/capture_terminal.py`), cropped and purposeful — not a
> full-session dump, and not typeset.

## 5. Technical accuracy

Prioritise official AWS / Azure / Google Cloud / Terraform / product
documentation. Verify current behaviour, configuration, availability,
permissions, limits and pricing.

**Clearly distinguish:**

- vendor-documented behaviour
- design assumptions
- lab observations
- estimates
- recommendations

**Do not claim something is verified unless it was checked.** Do not treat a lab
configuration as production-ready without explaining the additional controls
required.

## 6. Length and content hierarchy

**Target 1,500–2,500 words** for a typical lab; complex labs may need more.

| Layer | Carries |
|---|---|
| Main article | Essential concepts, architecture, implementation, evidence, takeaways |
| GitHub | Complete code, scripts, configuration |
| Optional appendix | Advanced explanation, extra debugging, detailed output |

**Do not remove essential technical content merely to satisfy a word count.**

## 7. Final editorial review

Read it as an engineer attempting the lab for the first time:

- Is the goal obvious?
- Are all services and their purposes clear?
- Can the architecture be understood quickly?
- Are prerequisites explicit?
- Are implementation steps in executable order?
- Can commands be copied and adapted safely?
- Does each screenshot prove something?
- Are measured results clearly distinguished from claims?
- Are cost and security implications explained?
- Is cleanup complete?
- Are references accurate and accessible?
- Can it be shortened without losing essential information?

**Deliver a practical engineering lab, not an exhaustive record of the
implementation process.**
