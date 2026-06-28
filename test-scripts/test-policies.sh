#!/usr/bin/env bash
# Test secret-reader and secret-writer policies against KV v2.
# Positive: writer can create and read back; reader can read.
# Negative: reader is denied on write.
#
# Required env vars: VAULT_ADDR (or TF_VAR_vault_addr), VAULT_TOKEN (or VAULT_ROOT_TOKEN),
# and either VAULT_CACERT or VAULT_SKIP_VERIFY=true for TLS.
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-${TF_VAR_vault_addr:-}}"
if [[ -z "$VAULT_ADDR" ]]; then
  echo "ERROR: Set VAULT_ADDR or source terraform/env.sh to export TF_VAR_vault_addr" >&2
  exit 1
fi
ROOT_TOKEN="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"
if [[ -z "$ROOT_TOKEN" ]]; then
  echo "ERROR: Set VAULT_TOKEN or source ansible/vault-env.sh to export VAULT_ROOT_TOKEN" >&2
  exit 1
fi

curl_tls_args=()
if [[ -n "${VAULT_CACERT:-}" ]]; then
  curl_tls_args+=(--cacert "$VAULT_CACERT")
elif [[ "${VAULT_SKIP_VERIFY:-}" == "true" ]]; then
  curl_tls_args+=(-k)
fi

KV_PATH="${KV_PATH:-secret}"
TEST_PATH="${TEST_PATH:-__policy-test__}"

pass=0
fail=0

check_http() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf "[PASS] %s (HTTP %s)\n" "$label" "$actual"
    pass=$((pass + 1))
  else
    printf "[FAIL] %s — expected HTTP %s, got %s\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

check_value() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf "[PASS] %s (%s)\n" "$label" "$actual"
    pass=$((pass + 1))
  else
    printf "[FAIL] %s — expected %q, got %q\n" "$label" "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

make_token() {
  local policy="$1"
  local token
  token=$(curl -s -X POST \
    -H "X-Vault-Token: $ROOT_TOKEN" \
    -H "Content-Type: application/json" \
    "${curl_tls_args[@]}" \
    "$VAULT_ADDR/v1/auth/token/create" \
    -d "{\"policies\": [\"$policy\"], \"ttl\": \"5m\", \"no_default_policy\": true}" \
    | jq -r '.auth.client_token // empty')
  if [[ -z "$token" ]]; then
    echo "ERROR: failed to create token for policy '$policy'" >&2
    exit 1
  fi
  echo "$token"
}

kv_write_status() {
  local token="$1" path="$2" value="$3"
  curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "X-Vault-Token: $token" \
    -H "Content-Type: application/json" \
    "${curl_tls_args[@]}" \
    "$VAULT_ADDR/v1/$KV_PATH/data/$path" \
    -d "{\"data\": {\"value\": \"$value\"}}"
}

kv_read_status() {
  local token="$1" path="$2"
  curl -s -o /dev/null -w "%{http_code}" -X GET \
    -H "X-Vault-Token: $token" \
    "${curl_tls_args[@]}" \
    "$VAULT_ADDR/v1/$KV_PATH/data/$path"
}

kv_read_value() {
  local token="$1" path="$2"
  curl -s -X GET \
    -H "X-Vault-Token: $token" \
    "${curl_tls_args[@]}" \
    "$VAULT_ADDR/v1/$KV_PATH/data/$path" \
    | jq -r '.data.data.value // empty'
}

cleanup() {
  curl -s -X DELETE \
    -H "X-Vault-Token: $ROOT_TOKEN" \
    "${curl_tls_args[@]}" \
    "$VAULT_ADDR/v1/$KV_PATH/metadata/$TEST_PATH" >/dev/null || true
}
trap cleanup EXIT

echo "Creating policy-scoped tokens ..."
writer_token=$(make_token "secret-writer")
reader_token=$(make_token "secret-reader")

echo ""
echo "--- secret-writer ---"
status=$(kv_write_status "$writer_token" "$TEST_PATH" "hello")
check_http "writer can create secret" "200" "$status"

actual=$(kv_read_value "$writer_token" "$TEST_PATH")
check_value "writer can read secret back" "hello" "$actual"

echo ""
echo "--- secret-reader ---"
status=$(kv_read_status "$reader_token" "$TEST_PATH")
check_http "reader can read secret" "200" "$status"

echo ""
echo "--- negative tests ---"
status=$(kv_write_status "$reader_token" "$TEST_PATH" "should-be-denied")
check_http "reader is denied on write" "403" "$status"

echo ""
printf "Results: %d passed, %d failed\n" "$pass" "$fail"
[[ $fail -eq 0 ]]
