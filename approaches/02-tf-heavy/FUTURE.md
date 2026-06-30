# Future Improvements — Approach 02

Tracked improvements and additions that are out of scope for the current iteration but worth revisiting.

## PKI

### Tighten TLS skip-verify defaults in Ansible roles

`vault_status`, `vault_init`, `vault_unseal`, and `vault_tokens` all default to `vault_xxx_tls_skip_verify: true`. Once `configure-tls.yml` has run and `local/vault-ca.pem` exists, these should use `VAULT_CACERT` instead. The challenge is that the root CA cert needs to be present on the remote host for the Vault CLI to use it. Options:

- Copy `local/vault-ca.pem` to the remote host in a pre-task and reference it in role defaults
- Or accept that TLS skip-verify in Ansible bootstrap is a deliberate trade-off (Ansible runs over SSH; the TLS hop is localhost → localhost)

### intermediate CA common_name convention

The initial intermediate is named `Lab Intermediate CA 001` with the prefix hard-coded in the sub-module. Consider extracting to a variable (`pki_int_common_name_prefix`) so operators can customise the prefix without editing the sub-module directly.

## Testing

### Full reset → bootstrap cycle validation

The new Terraform-managed intermediate approach has not been tested end-to-end from a clean reset. Before merging to main, run the complete sequence:

1. `reset.yml` (also removes `local/vault-ca.pem` and `local/pki.env`)
2. `bootstrap.yml`
3. `create-terraform-operator.yml`
4. `TF_VAR_enable_pki=true terraform apply`
5. `configure-tls.yml` (optional: replaces self-signed cert)
6. Verify `env.sh` switches to `VAULT_CACERT` and subsequent `terraform plan` shows no changes

### Intermediate rotation test

Rotation mechanics tested and confirmed (old issuer retained, default promoted). Remaining:
- Verify certs issued by the old intermediate are still verifiable after rotation
- `configure-tls.yml` re-issues the server cert from the new intermediate

## Alternative: minimalist PKI constructs

The current implementation uses `vault_pki_secret_backend_issuer` (per-issuer URL config) and `vault_generic_endpoint` (explicit default pointer) to give Terraform full ownership of the intermediate CA lifecycle. A lighter alternative is worth exploring as a separate approach:

- Drop `vault_pki_secret_backend_issuer` — note that `cert_request` does not have an `issuer_name` attribute (the provider rejects it); the issuer would be created with a UUID name. Dropping this resource means losing both the human-readable name and per-issuer URL tracking in TF state. Add `depends_on = [vault_pki_secret_backend_config_urls.pki_int]` to `set_signed` so the mount-level URL defaults are stamped onto the issuer at creation time.
- Replace the explicit `vault_generic_endpoint` (which manages `"default"` by name) with one that only sets `default_follows_latest_issuer = true`. Vault then auto-promotes the default on every `set_signed`, so rotation requires no TF config edits beyond adding the new resource blocks.

Trade-off: rotation is simpler (no `"default"` pointer to update) but TF no longer records which intermediate is current, and staged rotation (add new intermediate without promoting it yet) is not possible.

## Infrastructure

### Remote Terraform state backend

Currently Terraform state lives in `terraform/terraform.tfstate` on the control node. A Vault KV or S3-compatible backend would allow the state to be shared and versioned. Low priority for a single-operator lab, but relevant if this pattern is used in a team context.
