#!/usr/bin/env bash
# Generate GuardDuty sample findings so the threat_notifier Lambda can be seen
# publishing an alert to SNS. Sample findings are marked [SAMPLE] and are safe;
# they emit real "GuardDuty Finding" EventBridge events.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"

DETECTOR_ID=$(aws guardduty list-detectors --region "$REGION" \
  --query 'DetectorIds[0]' --output text)

if [[ -z "$DETECTOR_ID" || "$DETECTOR_ID" == "None" ]]; then
  echo "No GuardDuty detector found in $REGION — deploy the stack first." >&2
  exit 1
fi

echo "Creating sample findings on detector $DETECTOR_ID ..."
# A high-severity crypto-mining finding is the clearest demo of the notify path.
aws guardduty create-sample-findings --region "$REGION" \
  --detector-id "$DETECTOR_ID" \
  --finding-types \
    "CryptoCurrency:EC2/BitcoinTool.B!DNS" \
    "UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration.InsideAWS"

echo "Done. Within a minute or two the threat_notifier Lambda should publish to"
echo "SNS. Check the SNS-subscribed inbox and the Lambda logs:"
echo "  aws logs tail /aws/lambda/week11-secrem-threat_notifier --region $REGION --since 10m"
