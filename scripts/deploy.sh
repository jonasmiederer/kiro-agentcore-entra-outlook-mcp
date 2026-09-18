#!/usr/bin/env bash
# Deploy Option A (no Lambda): Outlook via MCP for Kiro users.
# Order: create+seed the OpenAPI bucket, upload the spec, then the main stack.
set -euo pipefail

PROFILE="${PROFILE:-default}"
REGION="${REGION:-us-east-1}"
STACK="${STACK:-outlook-mcp-gateway}"
GATEWAY_NAME="${GATEWAY_NAME:-outlook-mcp}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$HERE/templates/outlook-mcp-gateway.yaml"
OPENAPI="$HERE/openapi/graph-me-openapi.json"
PARAMS="$HERE/scripts/params.json"

ACCOUNT="$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)"
BUCKET="${OPENAPI_BUCKET:-${GATEWAY_NAME}-openapi-${ACCOUNT}-${REGION}}"
KEY="graph-me-openapi.json"

echo ">> account=$ACCOUNT region=$REGION bucket=$BUCKET"

# 1) Bucket first (idempotent).
if ! aws s3api head-bucket --bucket "$BUCKET" --profile "$PROFILE" 2>/dev/null; then
  echo ">> creating bucket $BUCKET"
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" \
    --profile "$PROFILE" >/dev/null
  aws s3api put-public-access-block --bucket "$BUCKET" --profile "$PROFILE" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  aws s3api put-bucket-encryption --bucket "$BUCKET" --profile "$PROFILE" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi

# 2) Upload the OpenAPI spec.
echo ">> uploading $KEY"
aws s3 cp "$OPENAPI" "s3://$BUCKET/$KEY" --profile "$PROFILE" --region "$REGION" >/dev/null

# 3) Validate then deploy the main stack.
echo ">> validating template"
aws cloudformation validate-template --template-body "file://$TEMPLATE" \
  --profile "$PROFILE" --region "$REGION" >/dev/null

echo ">> deploying stack $STACK"
# Build Key=Value overrides from params.json + injected bucket/name.
OVERRIDES="$(python3 -c '
import json,sys
p=json.load(open(sys.argv[1]))
print(" ".join(f"{k}={v}" for k,v in p.items()))
' "$PARAMS")"

aws cloudformation deploy \
  --stack-name "$STACK" \
  --template-file "$TEMPLATE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --profile "$PROFILE" --region "$REGION" \
  --parameter-overrides \
    $OVERRIDES \
    "OpenApiBucketName=$BUCKET" \
    "GatewayName=$GATEWAY_NAME"

echo ">> outputs"
aws cloudformation describe-stacks --stack-name "$STACK" \
  --profile "$PROFILE" --region "$REGION" \
  --query 'Stacks[0].Outputs' --output table
