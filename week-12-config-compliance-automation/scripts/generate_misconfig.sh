#!/usr/bin/env bash
# Create deliberately-non-compliant S3 buckets so the 3 Config rules can be
# watched evaluating (and, for the tagged one, auto-remediating) end-to-end.
#
# Bucket 1 is tagged auto-remediate=true and left with no versioning/encryption
# (a bucket's default state) — the two S3 rules should flag it NON_COMPLIANT,
# then the SSM-document remediations should fix both within minutes.
# Bucket 2 carries none of the required governance tags — it should show up
# as NON_COMPLIANT on required-tags and appear in the next daily digest
# (notify-only, nothing auto-fixes a missing tag value).
#
# Usage: ./generate_misconfig.sh
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
TAG_KEY="${REMEDIATION_TAG_KEY:-auto-remediate}"
TAG_VALUE="${REMEDIATION_TAG_VALUE:-true}"
SUFFIX="$(date +%s)"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "== Creating an opted-in bucket with no versioning/encryption =="
REMEDIATE_BUCKET="week12-remediate-test-${ACCOUNT_ID}-${SUFFIX}"
aws s3api create-bucket --region "$REGION" --bucket "$REMEDIATE_BUCKET" >/dev/null
aws s3api put-bucket-tagging --region "$REGION" --bucket "$REMEDIATE_BUCKET" \
  --tagging "TagSet=[{Key=$TAG_KEY,Value=$TAG_VALUE}]" >/dev/null
echo "   created $REMEDIATE_BUCKET (tagged $TAG_KEY=$TAG_VALUE, versioning+SSE off)"

echo "== Creating an untagged bucket (fails required-tags, notify-only) =="
UNTAGGED_BUCKET="week12-untagged-test-${ACCOUNT_ID}-${SUFFIX}"
aws s3api create-bucket --region "$REGION" --bucket "$UNTAGGED_BUCKET" >/dev/null
echo "   created $UNTAGGED_BUCKET (no environment/owner/cost-center tags)"

echo ""
echo "Config evaluates on a resource-change trigger for these rules — usually"
echo "within a few minutes. Track with:"
echo "  aws configservice get-compliance-details-by-config-rule --region $REGION \\"
echo "    --config-rule-name week12-s3-bucket-versioning-enabled"
echo "  aws configservice get-compliance-details-by-config-rule --region $REGION \\"
echo "    --config-rule-name week12-required-tags"
echo ""
echo "Leftovers to clean up if remediation did not (or to reset a re-test):"
echo "  REMEDIATE_BUCKET=$REMEDIATE_BUCKET"
echo "  UNTAGGED_BUCKET=$UNTAGGED_BUCKET"
