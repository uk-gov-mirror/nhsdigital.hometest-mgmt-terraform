#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------------------------------
# INVOKE GOOSE MIGRATOR LAMBDA
#
# Invokes the goose-migrator Lambda function and streams CloudWatch logs.
# Designed to be called from Terragrunt hooks or manually from the CLI.
#
# Usage:
#   ./scripts/invoke-goose-migrator.sh <function_name> <action> [env]
#
# Arguments:
#   function_name   Name of the Lambda function (from terraform output)
#   action          "migrate" or "teardown"
#   env             Optional label for log headers (defaults to action)
#
# Environment variables:
#   AWS_REGION      AWS region (default: eu-west-2)
#   LOG_WAIT_SECS   Max seconds to wait for CloudWatch logs (default: 120)
#   SKIP_MIGRATOR   Set to "true" to skip invocation entirely (useful for plan-only runs)
#
# Exit codes:
#   0   Success
#   1   Lambda invocation failed or function error returned
#   2   Invalid arguments
# ---------------------------------------------------------------------------------------------------------------------
set -euo pipefail

# ── Arguments ────────────────────────────────────────────────────────────────
FUNCTION_NAME="${1:-}"
LAMBDA_ACTION="${2:-migrate}"
TARGET_ENV="${3:-${LAMBDA_ACTION}}"

if [[ -z "$FUNCTION_NAME" ]]; then
  echo "Usage: $0 <function_name> <action> [env]"
  echo "  function_name: Lambda function name (from 'terragrunt output -raw function_name')"
  echo "  action:        migrate | teardown"
  echo "  env:           label for logs (optional, defaults to action)"
  exit 2
fi

# ── Config ───────────────────────────────────────────────────────────────────
AWS_REGION="${AWS_REGION:-eu-west-2}"
LOG_WAIT_SECS="${LOG_WAIT_SECS:-120}"

if [[ "${SKIP_MIGRATOR:-false}" == "true" ]]; then
  echo "[goose-migrator] SKIP_MIGRATOR=true — skipping invocation."
  exit 0
fi

# ── Handle empty / missing function name (for teardown during destroy) ───────
if [[ "$FUNCTION_NAME" == "None" || "$FUNCTION_NAME" == "" ]]; then
  if [[ "$LAMBDA_ACTION" == "teardown" ]]; then
    echo "[goose-migrator] Function name is empty — migrator may already be destroyed. Skipping teardown."
    exit 0
  else
    echo "[goose-migrator] ERROR: Function name is empty and action is '${LAMBDA_ACTION}'. Cannot proceed."
    exit 1
  fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[goose-migrator] Invoking Lambda: ${FUNCTION_NAME} (action: ${LAMBDA_ACTION})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
START_TIME_MS=$(date +%s%3N)

# ── Invoke Lambda ────────────────────────────────────────────────────────────
RESPONSE_FILE=$(mktemp /tmp/lambda-response.XXXXXX.json)
META_FILE=$(mktemp /tmp/lambda-invoke-meta.XXXXXX.json)
trap 'rm -f "$RESPONSE_FILE" "$META_FILE"' EXIT

aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --invocation-type RequestResponse \
  --log-type Tail \
  --cli-read-timeout 0 \
  --cli-binary-format raw-in-base64-out \
  --payload "{\"action\":\"${LAMBDA_ACTION}\"}" \
  --region "$AWS_REGION" \
  "$RESPONSE_FILE" > "$META_FILE"

STATUS_CODE=$(jq -r '.StatusCode // empty' "$META_FILE")
FUNCTION_ERROR=$(jq -r '.FunctionError // empty' "$META_FILE")
LOG_RESULT_B64=$(jq -r '.LogResult // empty' "$META_FILE")

echo "[goose-migrator] Status code: ${STATUS_CODE}"

# ── Decode tail logs & extract Request ID ────────────────────────────────────
LOG_TAIL=""
REQUEST_ID=""
if [[ -n "$LOG_RESULT_B64" ]]; then
  LOG_TAIL=$(echo "$LOG_RESULT_B64" | base64 -d)
  REQUEST_ID=$(echo "$LOG_TAIL" | grep -oP 'START RequestId: \K[a-f0-9-]+' || true)
fi
echo "[goose-migrator] Request ID: ${REQUEST_ID:-unknown}"

# ── Fetch full CloudWatch logs ───────────────────────────────────────────────
LOGS=""
if [[ -n "$REQUEST_ID" ]]; then
  echo "[goose-migrator] Waiting for CloudWatch to ingest logs..."
  sleep 10

  ELAPSED=0
  INTERVAL=5
  LOG_STREAM=""
  while [[ "$ELAPSED" -lt "$LOG_WAIT_SECS" ]]; do
    FILTER_RESULT=$(aws logs filter-log-events \
      --log-group-name "$LOG_GROUP" \
      --filter-pattern "\"END RequestId: ${REQUEST_ID}\"" \
      --start-time "$START_TIME_MS" \
      --region "$AWS_REGION" \
      --query "events[0]" --output json 2>/dev/null || echo "null")

    LOG_STREAM=$(echo "$FILTER_RESULT" | jq -r '.logStreamName // empty')
    if [[ -n "$LOG_STREAM" ]]; then break; fi

    echo "  Waiting for END marker... (${ELAPSED}s elapsed)"
    sleep "$INTERVAL"
    ELAPSED=$(( ELAPSED + INTERVAL ))
  done

  if [[ -n "$LOG_STREAM" ]]; then
    LOGS=$(aws logs get-log-events \
      --log-group-name "$LOG_GROUP" --log-stream-name "$LOG_STREAM" \
      --start-time "$START_TIME_MS" --start-from-head \
      --region "$AWS_REGION" \
      --query "events[*].message" --output text 2>/dev/null || true)
  fi
fi

# ── Print logs ───────────────────────────────────────────────────────────────
if [[ "$LAMBDA_ACTION" == "migrate" ]]; then
  SUMMARY_TITLE="Migration Logs (${TARGET_ENV})"
else
  SUMMARY_TITLE="Teardown Logs (${TARGET_ENV})"
fi

echo ""
echo "=== ${SUMMARY_TITLE} ==="
if [[ -n "$LOGS" ]]; then
  echo "$LOGS"
else
  echo "(full logs not available — showing tail)"
  echo "$LOG_TAIL"
fi

# ── Write GitHub Step Summary if running in CI ───────────────────────────────
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  DISPLAY_LOGS="${LOGS:-$LOG_TAIL}"
  {
    echo "### ${SUMMARY_TITLE}"
    echo "**Function**: \`${FUNCTION_NAME}\`"
    if [[ -n "$REQUEST_ID" ]]; then
      echo "**Request ID**: \`${REQUEST_ID}\`"
    fi
    echo '```'
    echo "$DISPLAY_LOGS"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
fi

# ── Check for errors ────────────────────────────────────────────────────────
if [[ -n "$FUNCTION_ERROR" && "$FUNCTION_ERROR" != "null" ]]; then
  echo ""
  echo "[goose-migrator] ERROR: Lambda ${LAMBDA_ACTION} returned error: ${FUNCTION_ERROR}"
  echo "[goose-migrator] Response payload:"
  cat "$RESPONSE_FILE"
  exit 1
fi

echo ""
echo "[goose-migrator] ${LAMBDA_ACTION} completed successfully."
