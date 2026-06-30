# Source this to load Vault unseal keys and root token from the init JSON in local/.

export VAULT_ROOT_TOKEN
VAULT_ROOT_TOKEN="$(jq -r '.root_token' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/../../../local/vault-*.json)"

eval "$(jq -r '.unseal_keys_b64 | to_entries[] | "export VAULT_UNSEAL_KEY_\(.key + 1)=\(.value)"' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/../../../local/vault-*.json)"
