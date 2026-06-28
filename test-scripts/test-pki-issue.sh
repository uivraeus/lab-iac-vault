#!/usr/bin/env bash
# Test leaf certificate issuance from pki_int/issue/server.
# Verifies CN, SANs, and that CRL, AIA, and OCSP extensions are embedded.
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

TEST_CN="${TEST_CN:-vault-test.lab.local}"
TEST_IP_SANS="${TEST_IP_SANS:-127.0.0.1}"
TEST_DNS_SANS="${TEST_DNS_SANS:-vault-test.lab.local}"
PKI_INT_PATH="${PKI_INT_PATH:-pki_int}"
PKI_ROLE="${PKI_ROLE:-server}"

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

body=$(jq -n \
  --arg cn  "$TEST_CN" \
  --arg ip  "$TEST_IP_SANS" \
  --arg dns "$TEST_DNS_SANS" \
  '{"common_name": $cn, "ip_sans": $ip, "alt_names": $dns, "ttl": "1h"}')

echo "Issuing cert from ${VAULT_ADDR}/v1/${PKI_INT_PATH}/issue/${PKI_ROLE} ..."
response=$(curl -s \
  -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  "${curl_tls_args[@]}" \
  "$VAULT_ADDR/v1/${PKI_INT_PATH}/issue/${PKI_ROLE}" \
  -d "$body")

if ! echo "$response" | jq -e '.data.certificate' >/dev/null 2>&1; then
  echo "ERROR: unexpected Vault response:" >&2
  echo "$response" | jq . >&2
  exit 1
fi

cert=$(echo "$response" | jq -r '.data.certificate')
cert_text=$(echo "$cert" | openssl x509 -text -noout)

echo ""
check "Subject CN"                  "Subject:.*CN[ ]*=[ ]*${TEST_CN}"   "$cert_text"
check "IP SAN"                      "IP Address:${TEST_IP_SANS}"         "$cert_text"
check "DNS SAN"                     "DNS:${TEST_DNS_SANS}"               "$cert_text"
check "CRL Distribution Point"      "URI:https?://[^[:space:]]*/crl"     "$cert_text"
check "AIA: OCSP endpoint"          "OCSP - URI:https?://"               "$cert_text"
check "AIA: CA Issuers endpoint"    "CA Issuers - URI:https?://"         "$cert_text"
check "EKU: TLS Web Server Auth"    "TLS Web Server Authentication"      "$cert_text"

echo ""
printf "Results: %d passed, %d failed\n" "$pass" "$fail"
[[ $fail -eq 0 ]]
