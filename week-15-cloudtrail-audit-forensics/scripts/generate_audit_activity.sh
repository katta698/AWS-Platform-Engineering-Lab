#!/usr/bin/env bash
#
# Produce deliberate, attributable activity so the forensic queries have
# something real to find.
#
# The audit questions this week answers need events that actually happened. The
# account generates plenty of background activity on its own, but none of it is
# a clean, known story you can point at in a write-up. This creates one:
#
#   1. A resource is created and then deleted    -> query 02 (who changed this)
#   2. Several actions by one identity            -> query 03 (principal timeline)
#   3. A change made by CLI, not Terraform        -> query 04 (drift)
#   4. An action in a region we do not use        -> query 07 + its alarm
#   5. A denied call                              -> errorcode in the timeline
#
# Everything here acts on resources this script creates in your own account, and
# cleans up after itself. Step 4 deliberately trips an alarm -- that is the
# point, and it recovers on the next analyzer run.
#
# Wait ~20 minutes after running before querying: CloudTrail delivers on a 5-15
# minute lag with occasional longer tails.

set -uo pipefail

# Git Bash / MSYS rewrites any argument that looks like a Unix path into a
# Windows path, so an SSM parameter name beginning with "/" arrives at the API
# mangled and fails with a misleading "Parameter name must be a fully qualified
# name." It reads like an AWS-side validation problem and is not one. This is a
# documented trap in this environment; exporting the guard once covers every
# call below.
export MSYS_NO_PATHCONV=1

REGION="${AWS_REGION:-us-east-1}"
ODD_REGION="${ODD_REGION:-eu-west-2}"
STAMP="$(date -u +%Y%m%d%H%M%S)"
PARAM="/week15-audit/demo-${STAMP}"

echo "Region:        $REGION"
echo "Odd region:    $ODD_REGION  (used once, deliberately, to trip the alarm)"
echo "Identity:      $(aws sts get-caller-identity --query Arn --output text 2>/dev/null)"
echo

###############################################################################
echo "--- 1. Create then delete a resource (the 'who deleted it' story) ---"
###############################################################################
# An SSM parameter is the cheapest thing that leaves a clean create/delete pair
# in CloudTrail. Standard parameters are free.

aws ssm put-parameter --name "$PARAM" --value "week15-audit-demo" --type String \
  --region "$REGION" >/dev/null \
  && echo "  created  $PARAM" || echo "  WARN: create failed"

aws ssm add-tags-to-resource --resource-type Parameter --resource-id "$PARAM" \
  --tags "Key=Week,Value=15" --region "$REGION" >/dev/null \
  && echo "  tagged   $PARAM" || echo "  WARN: tag failed"

sleep 2

aws ssm delete-parameter --name "$PARAM" --region "$REGION" >/dev/null \
  && echo "  DELETED  $PARAM   <- this is what query 02 should find" \
  || echo "  WARN: delete failed"

###############################################################################
echo
echo "--- 2. A short burst of actions by this identity (timeline) ---"
###############################################################################

for _ in 1 2 3; do
  aws sts get-caller-identity >/dev/null 2>&1
  aws ec2 describe-vpcs --region "$REGION" --max-results 5 >/dev/null 2>&1
done
echo "  a handful of read calls made -- query 03 shows these alongside the writes"

###############################################################################
echo
echo "--- 3. A denied call (errorcode in the timeline) ---"
###############################################################################
# Attempts to read a bucket that does not exist in this account. Produces an
# AccessDenied or NoSuchBucket in CloudTrail without touching anything real.

aws s3api get-bucket-policy --bucket "week15-audit-does-not-exist-${STAMP}" \
  --region "$REGION" >/dev/null 2>&1
echo "  one failed call made -- shows as errorcode in query 03"

###############################################################################
echo
echo "--- 4. One action in a region we do not use (trips the alarm) ---"
###############################################################################
# A tagged, immediately-deleted parameter in another region. This is a MUTATING
# call outside expected_regions, so query 07 finds it and the
# activity-in-unexpected-region alarm fires on the next analyzer run.

ODD_PARAM="/week15-audit/odd-region-${STAMP}"
aws ssm put-parameter --name "$ODD_PARAM" --value "unexpected-region-demo" --type String \
  --region "$ODD_REGION" >/dev/null \
  && echo "  created  $ODD_PARAM in $ODD_REGION" || echo "  WARN: create failed (region may be disabled)"

aws ssm delete-parameter --name "$ODD_PARAM" --region "$ODD_REGION" >/dev/null \
  && echo "  deleted  $ODD_PARAM in $ODD_REGION" || true

echo "  <- query 07 should now show $ODD_REGION"

###############################################################################
cat <<EOF

Done. Nothing was left behind.

Wait ~20 minutes for delivery, then in the Athena console (workgroup
week15-audit-wg):

  week15-audit-partition-sanity-check       confirm data is readable at all
  week15-audit-who-changed-this-resource    edit the placeholder to: ${STAMP}
  week15-audit-principal-activity-timeline  edit to your own identity
  week15-audit-changes-outside-terraform    these CLI calls should appear
  week15-audit-activity-in-unexpected-regions   should show ${ODD_REGION}

Or force an analyzer run rather than waiting for the daily schedule:

  aws lambda invoke --function-name week15-audit-audit-analyzer out.json \\
    && cat out.json && rm out.json

EOF
