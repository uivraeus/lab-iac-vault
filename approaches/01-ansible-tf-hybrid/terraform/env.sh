# Source this to set TF_VAR_* for a Terraform run.

export TF_VAR_vault_addr="https://$(
  ansible-inventory \
    -i "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../../../inventory.yaml" \
    --list | jq -r '._meta.hostvars[].ansible_host'
):8200"

if [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../local/vault-ca.pem" ]]; then
  export VAULT_CACERT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../local/vault-ca.pem"
else
  export VAULT_SKIP_VERIFY=true
fi

export TF_VAR_vault_external_addr="https://localhost:8200"

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../local"/terraform-operator-*.env

if [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../local/pki.env" ]]; then
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../local/pki.env"
else
  export TF_VAR_enable_pki=false
fi

if [[ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../local/oidc.env" ]]; then
  # shellcheck source=/dev/null
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../local/oidc.env"
fi
