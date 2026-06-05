# Week 03 — Screenshot Checklist for Blog

Save all screenshots to: `week-03-ssm-fleet-management/blog/screenshots/`

---

## Filename Cheat Sheet

Use these exact filenames when saving. Order matters — numbered for clarity.

```
01-terraform-output.png
02-fleet-manager-online.png
03-patch-noncompliant-before.png
04-stepfunctions-scan-succeeded.png
05-stepfunctions-scan-output.png
06-manual-ec2-no-tags.png
07-patch-manager-2-instances.png
08-stepfunctions-onboard-succeeded.png
09-manual-ec2-tags-after-onboard.png
10-patch-manager-3-instances.png
11-stepfunctions-install-succeeded.png
12-patch-manager-all-compliant.png
13-patch-detail-installed.png
14-cloudwatch-dashboard-full.png
15-stepfunctions-audit-trail.png
16-servicenow-ticket-submitted.png
17-servicenow-ticket-closed.png
18-session-manager-session.png       (bonus)
19-s3-session-logs.png               (bonus)
```

---

## Clean Run Order

Follow this exact sequence for clean, consistent screenshots:

```
1.  cleanup.sh                    → destroy everything first
2.  deploy.sh                     → fresh deploy
3.  Wait 5 min                    → instances registering with SSM
4.  Screenshot: Terraform output  → infrastructure proof
5.  Screenshot: Fleet Manager     → instances online (before patch)
6.  Screenshot: Patch Manager     → Non-compliant (before state)
7.  curl Scan RITM0030001         → simulate ServiceNow scan request
8.  Screenshot: Step Functions    → execution succeeded
9.  Screenshot: Patch Manager     → compliance data visible
10. Launch manual EC2             → no tags, unmanaged
11. Screenshot: Manual EC2 tags   → no PatchGroup tag (before)
12. Screenshot: Patch Manager     → only 2 instances (before onboard)
13. curl Onboard RITM0030002      → simulate ServiceNow onboard request
14. Screenshot: Step Functions    → onboard execution succeeded
15. Screenshot: EC2 tags          → PatchGroup + ManagedBy + OnboardedAt applied
16. Screenshot: Patch Manager     → now 3 instances showing
17. curl Install RITM0030003      → simulate ServiceNow patch request
18. Screenshot: Step Functions    → install execution succeeded
19. Screenshot: Patch Manager     → all 3 Compliant, MissingCount=0
20. Screenshot: CloudWatch        → dashboard with all widgets
21. Screenshot: Audit trail       → Step Functions list showing all executions
22. Wire ServiceNow (README Step 8) → create catalog item + business rule
23. Submit catalog item in ServiceNow
24. Screenshot: ServiceNow ticket  → RITM submitted, In Progress state
25. Screenshot: ServiceNow closed  → RITM Closed Complete with compliance report in work notes
```

---

## Screenshots Detail

### 1. Terraform Output
- **File:** `01-terraform-output.png`
- **Where:** Terminal after `deploy.sh` completes
- **What to show:** All outputs — API Gateway URL, ASG name, state machine ARN, maintenance window ID

---

### 2. SSM Fleet Manager — Instances Online
- **File:** `02-fleet-manager-online.png`
- **Where:** AWS Console → Systems Manager → Fleet Manager → Managed Instances
- **What to show:** Both ASG instances with PingStatus = Online, platform name, SSM agent version

---

### 3. Patch Manager — Non-Compliant (Before State)
- **File:** `03-patch-noncompliant-before.png`
- **Where:** AWS Console → Systems Manager → Patch Manager → Compliance reporting
- **What to show:** Both instances showing Non-compliant, High severity — this is the PROBLEM your platform solves

---

### 4. Step Functions — Scan Execution Succeeded
- **File:** `04-stepfunctions-scan-succeeded.png`
- **Where:** AWS Console → Step Functions → fleet-mgmt-dev-fleet-management → click patch-RITM0030001
- **What to show:** Table view with all steps green — RouteRequest, PatchFleet, MergePatch, UpdateServiceNow, Done

---

### 5. Step Functions — Scan Output (Compliance Report)
- **File:** `05-stepfunctions-scan-output.png`
- **Where:** Same execution → click Done state → Output tab
- **What to show:** JSON with ticket_id, compliance numbers, patch counts

---

### 6. Manual EC2 — Before Onboard (No Tags)
- **File:** `06-manual-ec2-no-tags.png`
- **Where:** AWS Console → EC2 → Instances → click manual-test-instance → Tags tab
- **What to show:** Only Name tag visible — no PatchGroup, no ManagedBy

---

### 7. Patch Manager — Manual Instance Has No Baseline
- **File:** `07-patch-manager-2-instances.png`
- **Where:** AWS Console → Systems Manager → Patch Manager → Compliance reporting
- **What to show:** 3 instances visible but manual-test-instance has Patch configuration name = "-" — it's visible to SSM but has no patch baseline assigned (no PatchGroup tag yet)

---

### 8. Step Functions — Onboard Execution Succeeded
- **File:** `08-stepfunctions-onboard-succeeded.png`
- **Where:** AWS Console → Step Functions → click onboard-RITM0030002 execution
- **What to show:** All steps green including the onboard path (different from patch path)

---

### 9. EC2 Tags — After Onboard
- **File:** `09-manual-ec2-tags-after-onboard.png`
- **Where:** AWS Console → EC2 → click manual-test-instance → Tags tab
- **What to show:** PatchGroup=fleet-mgmt-dev-linux, ManagedBy=fleet-mgmt-dev, OnboardedAt=timestamp all applied

---

### 10. Patch Manager — 3 Instances Now Showing
- **File:** `10-patch-manager-3-instances.png`
- **Where:** AWS Console → Systems Manager → Patch Manager → Compliance reporting
- **What to show:** All 3 instances listed — manual one now managed alongside fleet instances

---

### 11. Step Functions — Install Execution Succeeded
- **File:** `11-stepfunctions-install-succeeded.png`
- **Where:** AWS Console → Step Functions → click patch-RITM0030003 execution
- **What to show:** All steps green for Install operation

---

### 12. Patch Manager — All 3 Compliant
- **File:** `12-patch-manager-all-compliant.png`
- **Where:** AWS Console → Systems Manager → Patch Manager → Compliance reporting
- **What to show:** All 3 instances Compliant, MissingCount=0 — this is the AFTER state

---

### 13. Per-Instance Patch Detail
- **File:** `13-patch-detail-installed.png`
- **Where:** Terminal output of:
```bash
aws ssm describe-instance-patches \
  --instance-id <any-instance-id> \
  --query "Patches[*].[Title,State,InstalledTime]" \
  --output table --region us-east-1
```
- **What to show:** List of actual patch names, Installed state, timestamps

---

### 14. CloudWatch Dashboard — Full View
- **File:** `14-cloudwatch-dashboard-full.png`
- **Where:** CloudWatch → Dashboards → fleet-mgmt-dev-fleet-management
- **What to show:** All 6 widgets with real data — Lambda invocations, errors, duration, Step Functions executions, Session Manager

---

### 15. Step Functions Audit Trail
- **File:** `15-stepfunctions-audit-trail.png`
- **Where:** Terminal output of list-executions command OR Step Functions console executions list
- **What to show:** All executions (onboard + scans + install) all SUCCEEDED with timestamps

---

### 16. ServiceNow — Catalog Item Submitted
- **File:** `16-servicenow-ticket-submitted.png`
- **Where:** ServiceNow → Service Catalog → Fleet Management Request → after clicking Order Now
- **What to show:** RITM in Open/In Progress state — ticket number visible, request_type and patch_group fields filled in

---

### 17. ServiceNow — Ticket Closed with Compliance Report
- **File:** `17-servicenow-ticket-closed.png`
- **Where:** ServiceNow → your RITM ticket → Work Notes tab
- **What to show:** Ticket in Closed Complete state, work notes containing compliance report — instance count, compliant/non-compliant numbers, patch counts, Athena console link

---

### 18. Session Manager (Bonus)
- **File:** `18-session-manager-session.png`
- **Where:** Terminal — `aws ssm start-session --target <instance-id>`
- **What to show:** Interactive shell connected to instance with no SSH, no key pair

---

### 19. S3 Session Logs (Bonus)
- **File:** `19-s3-session-logs.png`
- **Where:** AWS Console → S3 → fleet-mgmt-dev-session-logs-684346483786
- **What to show:** patch-runs/, sessions/, onboarding/ folders with log files

---

## Key Messages Per Screenshot

| Screenshot | Blog caption |
|------------|-------------|
| 03 Non-compliant | "Fresh instances — High severity patches missing. The problem." |
| 07 Only 2 instances | "Manual EC2 invisible to Patch Manager — no tags, no baseline." |
| 09 Tags after onboard | "One ServiceNow ticket later — tagged, classified, managed." |
| 10 Three instances | "Manual instance now alongside fleet instances. Patch Manager can't tell the difference." |
| 12 All compliant | "100% compliant. 0 missing patches. 3 instances. Zero SSH." |
| 15 Audit trail | "Every operation traceable — ticket ID, timestamp, result." |
| 16 ServiceNow submitted | "User submits a form. That's it. AWS does the rest." |
| 17 ServiceNow closed | "Ticket closes itself — compliance report delivered, zero manual steps." |
