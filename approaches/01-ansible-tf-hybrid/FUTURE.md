# Future Improvements — Approach 01

Tracked improvements and additions that are out of scope for the current iteration but worth revisiting.

## PKI

### Tighten TLS skip-verify defaults in Ansible roles

`vault_status`, `vault_init`, `vault_unseal`, and `vault_tokens` all default to `vault_xxx_tls_skip_verify: true`. Once `configure-tls.yml` has run and `local/vault-ca.pem` exists, these should use `VAULT_CACERT` instead. The challenge is that the root CA cert needs to be present on the remote host (not just on the control node) for the Vault CLI environment to use it. Options:

- Copy `local/vault-ca.pem` to the remote host in a pre-task and reference it in role defaults
- Or accept that TLS skip-verify in Ansible bootstrap is a deliberate trade-off (Ansible runs over SSH; the TLS hop is localhost → localhost)

## Testing

### Full reset → bootstrap cycle validation

The PKI additions (setup-intermediate, configure-tls, env.sh switching to VAULT_CACERT) have not been tested end-to-end from a clean reset. Before merging to main, run the complete sequence:

1. `reset.yml`  (also removes `local/vault-ca.pem` and `local/pki.env`)
2. `bootstrap.yml`
3. `create-terraform-operator.yml`
4. `TF_VAR_enable_pki=true TF_VAR_pki_intermediate_ready=false terraform apply`
5. `setup-intermediate.yml`
6. `TF_VAR_enable_pki=true terraform apply`
7. `configure-tls.yml`
8. Verify `env.sh` switches to `VAULT_CACERT` and subsequent `terraform plan` shows no changes

## Infrastructure

### Remote Terraform state backend

Currently Terraform state lives in `terraform/terraform.tfstate` on the control node. A Vault KV or S3-compatible backend would allow the state to be shared and versioned. Low priority for a single-operator lab, but relevant if this pattern is used in a team context.
