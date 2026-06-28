# Future Improvements — Approach 01

Tracked improvements and additions that are out of scope for the current iteration but worth revisiting.

## PKI

### Intermediate CA rotation playbook (`rotate-intermediate.yml`)

The README references this playbook as part of the rotation workflow, but it does not exist yet. It should:

- Unconditionally generate a new CSR/key via `pki_int/intermediate/generate/internal`
- Sign the CSR against the root CA via `pki/root/sign-intermediate`
- Import the signed cert via `pki_int/intermediate/set-signed`
- Promote the new issuer as default using `vault write pki_int/issuer/<new-id> issuer_name=intermediate`
- Leave the old issuer in place until CRL expiry (clients validating existing certs still need it)

After the playbook, `terraform apply` re-stamps the issuer config (AIA/CRL/OCSP URLs, issuer name) onto the new default, and `configure-tls.yml` issues a new Vault TLS cert from the new intermediate.

### Tighten TLS skip-verify defaults in Ansible roles

`vault_status`, `vault_init`, `vault_unseal`, and `vault_tokens` all default to `vault_xxx_tls_skip_verify: true`. Once `configure-tls.yml` has run and `local/vault-ca.pem` exists, these should use `VAULT_CACERT` instead. The challenge is that the root CA cert needs to be present on the remote host (not just on the control node) for the Vault CLI environment to use it. Options:

- Copy `local/vault-ca.pem` to the remote host in a pre-task and reference it in role defaults
- Or accept that TLS skip-verify in Ansible bootstrap is a deliberate trade-off (Ansible runs over SSH; the TLS hop is localhost → localhost)

## OIDC

### Non-trivial default policy

Any user authenticated via OIDC currently receives the `default` policy, which grants access to the cubbyhole only. For the lab to be usable via browser login, a small policy granting at minimum read access to `secret/` should be created and assigned as the default role's `token_policies`.

### EntraID group claims → Vault policies

EntraID can include group membership in the OIDC token. Mapping groups to Vault policies via `bound_claims` on the OIDC role is the natural next step for multi-user policy differentiation. Requires configuring the app registration to include group claims in the token.

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
