#!/bin/bash
# Wait until a benchmark instance has uploaded its outputs to S3, then give
# CloudWatch time to publish the last minutes before metrics are pulled.
# Usage: ./scripts/wait-done.sh <region> <instance-id> <bucket> [timeout-minutes]
set -euo pipefail
REGION=${1:?region required}; IID=${2:?instance id required}; BUCKET=${3:?bucket required}
TIMEOUT_MIN=${4:-150}
CW_SETTLE_SECONDS=${CW_SETTLE_SECONDS:-180}

# carbon-bench.log is the last object user-data.sh uploads
KEY="$REGION/$IID/carbon-bench.log"
DEADLINE=$(( $(date +%s) + TIMEOUT_MIN * 60 ))

uploaded() {
  aws s3api head-object --region "$REGION" --bucket "$BUCKET" --key "$KEY" >/dev/null 2>&1
}

until uploaded; do
  STATE=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$IID" \
          --query 'Reservations[0].Instances[0].State.Name' --output text)
  if [ "$STATE" = "terminated" ] && ! uploaded; then
    echo "$IID terminated without uploading s3://$BUCKET/$KEY" >&2
    exit 1
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "Timed out after $TIMEOUT_MIN min waiting for s3://$BUCKET/$KEY (instance $STATE)" >&2
    exit 1
  fi
  echo "$(date -u +%FT%TZ) $IID $STATE, waiting"
  sleep 60
done

echo "$(date -u +%FT%TZ) outputs uploaded; waiting ${CW_SETTLE_SECONDS}s for CloudWatch"
sleep "$CW_SETTLE_SECONDS"
