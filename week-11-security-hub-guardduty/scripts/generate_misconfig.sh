#!/usr/bin/env bash
# Create deliberately-insecure resources so Security Hub FSBP raises findings
# and the auto-remediators can be watched fixing them end-to-end.
#
# Both resources are tagged auto-remediate=true so the Lambdas act on them.
# Run cleanup_misconfig.sh (or the values printed here) to remove any leftovers.
#
# Usage: ./generate_misconfig.sh [vpc-id]
#   vpc-id optional; defaults to the account's default VPC.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
TAG_KEY="${REMEDIATION_TAG_KEY:-auto-remediate}"
TAG_VALUE="${REMEDIATION_TAG_VALUE:-true}"
SUFFIX="$(date +%s)"

VPC_ID="${1:-$(aws ec2 describe-vpcs --region "$REGION" \
  --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)}"

echo "== Creating an open-to-world security group in $VPC_ID =="
SG_ID=$(aws ec2 create-security-group --region "$REGION" \
  --group-name "week11-open-ssh-$SUFFIX" \
  --description "INTENTIONALLY INSECURE — Week 11 remediation test" \
  --vpc-id "$VPC_ID" \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=$TAG_KEY,Value=$TAG_VALUE},{Key=Name,Value=week11-open-ssh}]" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null
aws ec2 authorize-security-group-ingress --region "$REGION" \
  --group-id "$SG_ID" --protocol tcp --port 3389 --cidr 0.0.0.0/0 >/dev/null
echo "   created SG $SG_ID with 22 and 3389 open to 0.0.0.0/0"

echo "== Creating a public S3 bucket =="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="week11-public-test-${ACCOUNT_ID}-${SUFFIX}"
aws s3api create-bucket --region "$REGION" --bucket "$BUCKET" >/dev/null
# Turn OFF the account/bucket default block so it can actually become public.
aws s3api put-public-access-block --region "$REGION" --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false >/dev/null
aws s3api put-bucket-tagging --region "$REGION" --bucket "$BUCKET" \
  --tagging "TagSet=[{Key=$TAG_KEY,Value=$TAG_VALUE}]" >/dev/null
aws s3api put-bucket-policy --region "$REGION" --bucket "$BUCKET" --policy "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"PublicRead\", \"Effect\": \"Allow\", \"Principal\": \"*\",
    \"Action\": \"s3:GetObject\", \"Resource\": \"arn:aws:s3:::$BUCKET/*\"
  }]
}" >/dev/null || echo "   (bucket policy may be rejected if account SCP blocks public — BPA finding still fires)"
echo "   created public bucket $BUCKET"

echo ""
echo "Findings should appear in Security Hub within ~15-30 min, then the"
echo "remediators will act. Track with:"
echo "  aws securityhub get-findings --region $REGION \\"
echo "    --filters '{\"ResourceId\":[{\"Value\":\"$SG_ID\",\"Comparison\":\"CONTAINS\"}]}'"
echo ""
echo "Leftovers to clean up if the remediator did not (or to reset a re-test):"
echo "  SG_ID=$SG_ID"
echo "  BUCKET=$BUCKET"
