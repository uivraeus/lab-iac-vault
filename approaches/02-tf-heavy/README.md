# Approach 02 — Terraform-Heavy

Ansible for installation and procedural bootstrap only; Terraform owns all ongoing configuration including the intermediate CA lifecycle. Compare with [approach 01](../01-ansible-tf-hybrid/README.md) where Ansible managed the intermediate CA setup and rotation.

## Design Decisions

### Ansible/Terraform split

The split is narrower than approach 01:

- **Ansible** handles only what cannot reasonably be declarative: installing Vault, initialising it, unsealing it, and optionally replacing the server TLS certificate once PKI is up.
- **Terraform** owns everything else: auth methods, secret engine mounts, PKI roles, policies, and the entire intermediate CA lifecycle (CSR generation, signing, import, issuer configuration, default promotion).

The handoff point is still the `terraform-operator` AppRole, created by Ansible and consumed by Terraform for all subsequent runs.

### Intermediate CA management

Terraform manages the intermediate CA using three chained resources per intermediate generation:

1. `vault_pki_secret_backend_intermediate_cert_request` — generates the key and CSR inside Vault
2. `vault_pki_secret_backend_root_sign_intermediate` — signs the CSR with the root CA
3. `vault_pki_secret_backend_intermediate_set_signed` — imports the signed certificate (full chain: cert + root)

A fourth resource, `vault_pki_secret_backend_issuer`, assigns a human-readable name to the issuer (via `imported_issuers[0]` from `set_signed`) and configures AIA/CRL/OCSP URLs. A `vault_generic_endpoint` targeting `pki_int/config/issuers` controls which issuer is the active default.

This means the full PKI hierarchy — root CA, intermediate CA, roles, policies, issuer URLs, and default issuer selection — is brought up in a single `terraform apply`.

### Intermediate CA rotation convention

Intermediates are controlled by the `pki_intermediates` list in `terraform/main.tf`. The `modules/pki` module creates one intermediate per entry using `for_each`, and the last entry in the list is always the active default issuer. There is no required format for the identifier; any unique string works.

The only convention is **append only — never remove or reorder**. Old issuers must stay in Vault so that certificates they issued remain verifiable until expiry.

To rotate:

1. Append a new identifier to `pki_intermediates` in `terraform/main.tf` (the root module's module call).
2. `terraform apply` — new intermediate is created and automatically becomes the default.
3. Optional: run `configure-tls.yml` to re-issue Vault's server TLS cert from the new intermediate.

This is documented inline in `modules/pki/main.tf`.

### Why `pki_intermediate_ready` is gone

Approach 01 needed a two-step apply: first apply with `pki_intermediate_ready=false` to create the mounts, then Ansible set up the intermediate, then a second apply with `pki_intermediate_ready=true` to configure the issuer. In approach 02, Terraform handles all three steps in one apply — no flag needed.

### PKI feature flags

`enable_pki` has no default and must always be explicitly set — same as approach 01. This prevents a `terraform apply` with a missing variable from silently planning destruction of the entire PKI infrastructure.

### TLS bootstrap, OIDC, secrets handling

Identical to approach 01 — see the [approach 01 README](../01-ansible-tf-hybrid/README.md) for those sections.

## Quickstart — Ansible phase

All playbooks are run from `approaches/02-tf-heavy/ansible/`. The `ansible.cfg` there sets the inventory and roles path.

```bash
cd approaches/02-tf-heavy/ansible
```

### Bootstrap (first-time install)

```bash
ansible-playbook bootstrap.yml
```

### Create the Terraform operator

```bash
source vault-env.sh
ansible-playbook create-terraform-operator.yml
```

### Unseal after restart

```bash
source vault-env.sh
ansible-playbook unseal.yml
```

### Reset (destructive)

```bash
ansible-playbook ../../../shared/ansible/reset.yml
```

## Quickstart — Terraform phase

```bash
cd approaches/02-tf-heavy/terraform
terraform init
```

### env.sh

Source before every Terraform run:

```bash
source env.sh
```

### Apply (KV only)

```bash
source env.sh
terraform apply
```

### Enable PKI

PKI and the intermediate CA are both set up in a single apply — no multi-step sequence required.

```bash
cp pki.env.example ../../../local/pki.env
source env.sh
terraform apply
```

Then optionally replace Vault's self-signed TLS certificate:

```bash
cd ../ansible
source vault-env.sh
ansible-playbook configure-tls.yml
```

### Intermediate CA rotation

See the rotation convention above. After editing `pki_intermediates` in `terraform/main.tf`:

```bash
source env.sh
terraform apply
```

### OIDC (optional)

```bash
cp oidc.env.example ../../../local/oidc.env
# Edit local/oidc.env: fill in tenant-id, client-id, client-secret, group object IDs
source env.sh
terraform apply
```

### Destroy

```bash
source env.sh
terraform destroy
```
