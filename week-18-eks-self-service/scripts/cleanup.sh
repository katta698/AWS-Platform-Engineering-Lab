#!/usr/bin/env bash
# Verify Week 18 is gone. Run AFTER the HCP destroy, not instead of it.
#
# EKS is the most expensive thing this series has built: $0.10/hr control plane
# plus $0.045/hr NAT plus a node, from creation, with no free tier. A teardown
# that half-worked costs about $4/day until somebody notices.
set -uo pipefail
PROFILE="${AWS_PROFILE:-personal}"
PREFIX="week18"
fail=0

check() {
  local label="$1" result="$2"
  if [[ -z "${result// /}" || "$result" == "[]" || "$result" == "None" ]]; then
    printf '  [gone] %s\n' "$label"
  else
    printf '  [LIVE] %s -> %s\n' "$label" "$result"
    fail=1
  fi
}

echo "Week 18 teardown verification"

check "eks clusters" "$(aws eks list-clusters --profile "$PROFILE" \
  --query "clusters[?starts_with(@,'${PREFIX}')]" --output text)"

check "nat gateways" "$(aws ec2 describe-nat-gateways --profile "$PROFILE" \
  --filter Name=tag:Week,Values=18 Name=state,Values=available,pending \
  --query "NatGateways[].NatGatewayId" --output text)"

check "elastic ips" "$(aws ec2 describe-addresses --profile "$PROFILE" \
  --filters Name=tag:Week,Values=18 --query "Addresses[].AllocationId" --output text)"

check "vpcs" "$(aws ec2 describe-vpcs --profile "$PROFILE" \
  --filters Name=tag:Week,Values=18 --query "Vpcs[].VpcId" --output text)"

check "ec2 instances" "$(aws ec2 describe-instances --profile "$PROFILE" \
  --filters Name=tag:Week,Values=18 Name=instance-state-name,Values=running,pending \
  --query "Reservations[].Instances[].InstanceId" --output text)"

check "iam roles" "$(aws iam list-roles --profile "$PROFILE" \
  --query "Roles[?starts_with(RoleName,'${PREFIX}')].RoleName" --output text)"

# IRSA creates one OIDC provider per cluster. They are invisible in the EKS
# console once the cluster is gone, they survive a careless teardown, and IAM
# caps an account at 100 of them. They cost nothing, which is why they pile up.
check "oidc providers" "$(aws iam list-open-id-connect-providers --profile "$PROFILE" \
  --query "OpenIDConnectProviderList[?contains(Arn,'oidc.eks')].Arn" --output text)"

check "s3 buckets" "$(aws s3api list-buckets --profile "$PROFILE" \
  --query "Buckets[?starts_with(Name,'${PREFIX}')].Name" --output text)"

check "log groups" "$(aws logs describe-log-groups --profile "$PROFILE" \
  --query "logGroups[?contains(logGroupName,'${PREFIX}')].logGroupName" --output text)"

# The catch-all: anything tagged this week that the name checks missed.
#
# Deleted NAT gateways linger in the EC2 API and keep their tags, so a tag
# search finds them long after they stop billing. Reporting one as LIVE is a
# false alarm, and a cleanup check that cries wolf is one people stop reading --
# so resolve the state and drop the ones that are genuinely gone.
tagged=$(aws resourcegroupstaggingapi get-resources --profile "$PROFILE" \
  --tag-filters Key=Week,Values=18 \
  --query "ResourceTagMappingList[].ResourceARN" --output text)

still_real=""
for arn in $tagged; do
  case "$arn" in
    *":natgateway/"*)
      ngw="${arn##*/}"
      state=$(aws ec2 describe-nat-gateways --profile "$PROFILE" \
        --nat-gateway-ids "$ngw" --query "NatGateways[0].State" \
        --output text 2>/dev/null)
      if [[ "$state" == "deleted" ]]; then
        printf '  [gone] %s (deleted; its tags outlive it)\n' "$ngw"
        continue
      fi
      ;;
  esac
  still_real="$still_real $arn"
done

check "tagged Week=18" "$still_real"

echo
if [[ $fail -eq 0 ]]; then
  echo "CLEAN — nothing from Week 18 remains."
else
  echo "NOT CLEAN — see [LIVE] lines above. EKS bills by the hour; fix now."
  exit 1
fi
