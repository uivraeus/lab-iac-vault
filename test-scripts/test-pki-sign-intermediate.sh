#!/usr/bin/env bash
# Test intermediate CA CSR signing via pki/root/sign-intermediate.
# Generates a temporary CSR externally with openssl, submits it to the root CA,
# and verifies that the signed cert contains correct CA extensions,
# CRL distribution points, and AIA/OCSP endpoints.
# Does NOT import the signed cert — Vault's intermediate state is unchanged.
#
# Required env vars: VAULT_ADDR (or TF_VAR_vault_addr), VAULT_TOKEN (or VAULT_ROOT_TOKEN),
# and either VAULT_CACERT or VAULT_SKIP_VERIFY=true for TLS.
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-${TF_VAR_vault_addr:-}}"
if [[ -z "$VAULT_ADDR" ]]; then
  echo "ERROR: Set VAULT_ADDR or source terraform/env.sh to export TF_VAR_vault_addr" >&2
  exit 1
fi
VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"
if [[ -z "$VAULT_TOKEN" ]]; then
  echo "ERROR: Set VAULT_TOKEN or source ansible/vault-env.sh to export VAULT_ROOT_TOKEN" >&2
  exit 1
fi

curl_tls_args=()
if [[ -n "${VAULT_CACERT:-}" ]]; then
  curl_tls_args+=(--cacert "$VAULT_CACERT")
elif [[ "${VAULT_SKIP_VERIFY:-}" == "true" ]]; then
  curl_tls_args+=(-k)
fi

TEST_CN="${TEST_CN:-Lab Test Intermediate CA}"
PKI_ROOT_PATH="${PKI_ROOT_PATH:-pki}"

pass=0
fail=0

check() {
  local label="$1" pattern="$2" input="$3"
  local matched
  matched=$(echo "$input" | grep -m1 -E "$pattern" | sed 's/^[[:space:]]*//' || true)
  if [[ -n "$matched" ]]; then
    printf "[PASS] %s (%s)\n" "$label" "$matched"
    pass=$((pass + 1))
  else
    printf "[FAIL] %s\n" "$label"
    fail=$((fail + 1))
  fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Generating test CSR (CN: ${TEST_CN}) ..."
openssl req -newkey rsa:2048 -nodes \
  -keyout "${tmpdir}/key.pem" \
  -out "${tmpdir}/int.csr" \
  -subj "/CN=${TEST_CN}" \
  2>/dev/null

csr_content=$(cat "${tmpdir}/int.csr")
body=$(jq -n \
  --arg csr "$csr_content" \
  --arg cn  "$TEST_CN" \
  '{"csr": $csr, "common_name": $cn, "format": "pem_bundle", "ttl": "8760h"}')

echo "Signing CSR via ${VAULT_ADDR}/v1/${PKI_ROOT_PATH}/root/sign-intermediate ..."
response=$(curl -s \
  -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  "${curl_tls_args[@]}" \
  "$VAULT_ADDR/v1/${PKI_ROOT_PATH}/root/sign-intermediate" \
  -d "$body")

if ! echo "$response" | jq -e '.data.certificate' >/dev/null 2>&1; then
  echo "ERROR: unexpected Vault response:" >&2
  echo "$response" | jq . >&2
  exit 1
fi

signed_cert=$(echo "$response" | jq -r '.data.certificate')
cert_text=$(echo "$signed_cert" | openssl x509 -text -noout)

echo ""
check "Subject CN"                   "Subject:.*CN[ ]*=[ ]*${TEST_CN}"  "$cert_text"
check "CA:TRUE (basic constraint)"   "CA:TRUE"                           "$cert_text"
check "Key Usage: Certificate Sign"  "Certificate Sign"                  "$cert_text"
check "Key Usage: CRL Sign"          "CRL Sign"                          "$cert_text"
check "CRL Distribution Point"       "URI:https?://[^[:space:]]*/crl"    "$cert_text"
check "AIA: OCSP endpoint"           "OCSP - URI:https?://"              "$cert_text"
check "AIA: CA Issuers endpoint"     "CA Issuers - URI:https?://"        "$cert_text"

echo ""
printf "Results: %d passed, %d failed\n" "$pass" "$fail"
[[ $fail -eq 0 ]]
