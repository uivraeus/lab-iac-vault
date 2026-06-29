#!/usr/bin/env bash
# Test leaf certificate provisioning from pki_int using the pki-admin policy.
# Covers both the issue role (Vault-generated key) and the sign role (caller CSR).
# Verifies CN, SANs, CRL/AIA/OCSP extensions, Ed25519 key, and domain restriction.
#
# Required env vars: VAULT_ADDR (or TF_VAR_vault_addr), VAULT_TOKEN (or VAULT_ROOT_TOKEN)
# for token creation, and either VAULT_CACERT or VAULT_SKIP_VERIFY=true for TLS.
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

VAULT_TOKEN=$(curl -s -X POST \
  -H "X-Vault-Token: $ROOT_TOKEN" \
  -H "Content-Type: application/json" \
  "${curl_tls_args[@]}" \
  "$VAULT_ADDR/v1/auth/token/create" \
  -d '{"policies": ["pki-admin"], "ttl": "5m", "no_default_policy": true}' \
  | jq -r '.auth.client_token // empty')
if [[ -z "$VAULT_TOKEN" ]]; then
  echo "ERROR: failed to create pki-admin token" >&2
  exit 1
fi

TEST_CN="${TEST_CN:-vault-test.local.example.com}"
TEST_IP_SANS="${TEST_IP_SANS:-127.0.0.1}"
TEST_DNS_SANS="${TEST_DNS_SANS:-vault-test.local.example.com}"
TEST_DENIED_CN="${TEST_DENIED_CN:-vault-test.lab.local}"
PKI_INT_PATH="${PKI_INT_PATH:-pki_int}"
PKI_ROLE="${PKI_ROLE:-issue}"

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
issuing_ca=$(echo "$response" | jq -r '.data.issuing_ca')
issuer_fp=$(echo "$issuing_ca" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/SHA256 Fingerprint=//')
echo "Issuing CA fingerprint: ${issuer_fp}"

echo ""
check "Subject CN"                  "Subject:.*CN[ ]*=[ ]*${TEST_CN}"   "$cert_text"
check "IP SAN"                      "IP Address:${TEST_IP_SANS}"         "$cert_text"
check "DNS SAN"                     "DNS:${TEST_DNS_SANS}"               "$cert_text"
check "CRL Distribution Point"      "URI:https?://[^[:space:]]*/crl"     "$cert_text"
check "AIA: OCSP endpoint"          "OCSP - URI:https?://"               "$cert_text"
check "AIA: CA Issuers endpoint"    "CA Issuers - URI:https?://"         "$cert_text"
check "EKU: TLS Web Server Auth"    "TLS Web Server Authentication"      "$cert_text"
check "Key algorithm: Ed25519"       "Public Key Algorithm: ED25519"        "$cert_text"

denied_body=$(jq -n --arg cn "$TEST_DENIED_CN" '{"common_name": $cn, "ttl": "1h"}')
denied_response=$(curl -s \
  -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  "${curl_tls_args[@]}" \
  "$VAULT_ADDR/v1/${PKI_INT_PATH}/issue/${PKI_ROLE}" \
  -d "$denied_body")

denied_error=$(echo "$denied_response" | jq -r '.errors[0] // empty')
if echo "$denied_error" | grep -qE "not allowed by this role"; then
  printf "[PASS] Disallowed domain rejected (%s)\n" "$denied_error"
  pass=$((pass + 1))
else
  printf "[FAIL] Disallowed domain should have been rejected (got: %s)\n" "$denied_error"
  fail=$((fail + 1))
fi

echo ""
echo "--- sign role ---"
csr=$(openssl req -new -newkey rsa:2048 -nodes -keyout /dev/null -subj "/CN=${TEST_CN}" 2>/dev/null)
sign_body=$(jq -n --arg csr "$csr" --arg cn "$TEST_CN" '{"csr": $csr, "common_name": $cn, "ttl": "1h"}')
sign_response=$(curl -s -X POST \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  "${curl_tls_args[@]}" \
  "$VAULT_ADDR/v1/${PKI_INT_PATH}/sign/sign" \
  -d "$sign_body")
if echo "$sign_response" | jq -e '.data.certificate' >/dev/null 2>&1; then
  printf "[PASS] pki-admin can sign CSR\n"
  pass=$((pass + 1))
else
  printf "[FAIL] pki-admin sign CSR (got: %s)\n" "$(echo "$sign_response" | jq -r '.errors[0] // empty')"
  fail=$((fail + 1))
fi

echo ""
printf "Results: %d passed, %d failed\n" "$pass" "$fail"
[[ $fail -eq 0 ]]
