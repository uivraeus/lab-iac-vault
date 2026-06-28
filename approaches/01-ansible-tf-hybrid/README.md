# Approach 01 — Ansible + Terraform Hybrid

Ansible for installation and procedural bootstrap, Terraform (Vault provider) for ongoing declarative configuration. See [ADR-001](../../docs/decisions/001-ansible-terraform-split.md) for the architectural rationale behind the split.

## Design Decisions

### Ansible/Terraform split

The split is based on the nature of the operation, not the tool's capabilities:

- **Ansible** handles anything that is inherently procedural and one-time: installing Vault, initialising it, creating the PKI intermediate CA, replacing the TLS certificate. These operations have side effects that don't map cleanly to Terraform's declare-and-reconcile model.
- **Terraform** owns everything that is ongoing and re-tunable: auth methods, secret engine mounts, PKI roles, policies, issuer URL configuration. These benefit from `plan`, idempotent `apply`, and `destroy` semantics.

The handoff point is the `terraform-operator` AppRole, created by Ansible and consumed by Terraform for all subsequent runs.

### TLS bootstrap

Vault needs TLS before it has a PKI engine. A self-signed certificate is generated at install time (using the system `openssl` binary, no Ansible collections) to enable encrypted communication from day one. Once Terraform has set up the PKI engine and Ansible has built the intermediate CA, `configure-tls.yml` replaces the self-signed cert with one issued by the internal PKI and saves the root CA to `local/vault-ca.pem`. From that point, `env.sh` automatically switches from `VAULT_SKIP_VERIFY=true` to `VAULT_CACERT`.

### PKI architecture

A single Vault-internal CA hierarchy is used (no externally pre-generated root). This keeps CRL, OCSP, and AIA hosting inside Vault without extra infrastructure. Two mounts are used: `pki` (root CA, stable, generated once by Terraform) and `pki_int` (intermediate CA, procedurally set up by Ansible). Separating the mounts enables intermediate rotation without touching the root.

The intermediate is set up by Ansible (`setup-intermediate.yml`) rather than Terraform because the CSR → sign → import sequence is inherently procedural, and intermediate rotation does not fit Terraform's replace semantics. Terraform manages all issuer configuration (AIA/CRL/OCSP URLs, issuer name) using `issuer_ref = "default"`, so rotation is transparent: Ansible promotes the new issuer as default and `terraform apply` re-stamps the config onto it.

### PKI feature flags

`enable_pki` has no default and must always be explicitly set. This prevents a `terraform apply` with a missing variable from silently planning destruction of the entire PKI infrastructure. `pki_intermediate_ready` defaults to `true` (the nominal ongoing case); it only needs to be explicitly set to `false` on the very first apply, before `setup-intermediate.yml` has run.

### OIDC

The OIDC module uses a flat policy (any authenticated user gets the `default` policy) as a starting point. Mapping to group claims from EntraID is a natural next step when policy differentiation is needed. The `vault_external_addr` variable is kept separate from `vault_addr` because Terraform connects to Vault on the internal network address, while OIDC redirect URIs must use the address reachable from the browser.

### Secrets handling

AppRole credentials, OIDC client secrets, and unseal keys are never committed. They live in `local/` (gitignored) and are loaded at runtime via sourced env files or `vault-env.sh`. Terraform variables that carry credentials use `ephemeral = true` where the provider allows it (not stored in state or plan files), and `sensitive = true` otherwise.

## Quickstart — Ansible phase

All playbooks are run from `approaches/01-ansible-tf-hybrid/ansible/`. The `ansible.cfg` there sets the inventory and roles path, so no extra flags are needed.

```bash
cd approaches/01-ansible-tf-hybrid/ansible
```

### Bootstrap (first-time install)

Installs Vault, initializes it, and unseals it. Fails early if Vault is already initialized.

```bash
ansible-playbook bootstrap.yml
```

Output written to `local/` on the control node:

- `vault-<hostname>.json` — unseal keys and root token (keep safe, do not commit)

### Create the Terraform operator

Creates the `terraform-operator` AppRole and writes its credentials to `local/`. Requires the root token from the bootstrap output.

```bash
source vault-env.sh
ansible-playbook create-terraform-operator.yml
```

Output written to `local/`:

- `terraform-operator-<hostname>.env` — `TF_VAR_vault_role_id` and `TF_VAR_vault_secret_id`

### Unseal after restart

```bash
source vault-env.sh
ansible-playbook unseal.yml
```

`vault-env.sh` reads `local/vault-<hostname>.json` and exports `VAULT_UNSEAL_KEY_1..N` and `VAULT_ROOT_TOKEN`. The number of keys required equals the key threshold set during bootstrap (default: 3 of 5).

### Reset (destructive)

Removes Vault, its data, and all local credential files including `local/vault-ca.pem` and `local/pki.env`. Use before re-running bootstrap on the same host.

```bash
# Remove Vault package, config, data, and local credential files:
ansible-playbook ../../../shared/ansible/reset.yml

# Also remove the HashiCorp apt repo and GPG key (full purge):
ansible-playbook ../../../shared/ansible/reset.yml -e vault_reset_purge=true
```

## Quickstart — Terraform phase

Terraform runs from `approaches/01-ansible-tf-hybrid/terraform/`. It requires the AppRole credentials written by the Ansible phase and the Vault server address.

```bash
cd approaches/01-ansible-tf-hybrid/terraform
```

### First-time setup

```bash
terraform init
```

### env.sh

Source `env.sh` before every Terraform run. It sets all required `TF_VAR_*` environment variables in one step:

- Reads `TF_VAR_vault_addr` from the Ansible inventory
- Sources `local/terraform-operator-<hostname>.env` (AppRole credentials)
- Sources `local/pki.env` if present, otherwise sets `TF_VAR_enable_pki=false`
- Sources `local/oidc.env` if present (OIDC credentials)
- Sets `VAULT_CACERT` to `local/vault-ca.pem` if it exists, otherwise falls back to `VAULT_SKIP_VERIFY=true`

```bash
source env.sh
```

The AppRole credentials (`TF_VAR_vault_role_id`, `TF_VAR_vault_secret_id`) are declared as ephemeral variables and are never written to the state file.

### Apply

```bash
source env.sh
terraform apply
```

Sets up the KV secrets engine. PKI and OIDC are disabled by default — see the optional sections below.

### OIDC (optional)

OIDC enables browser-based login to the Vault UI via an external identity provider. Tested with EntraID but works with any OIDC-compliant IdP.

**IdP configuration (EntraID)**

Create an app registration with the following settings:

- **Platform**: Web (not SPA or mobile/desktop)
- **Redirect URIs** — two are required, both using the address the browser uses to reach Vault:
  - `https://<vault-addr>/ui/vault/auth/oidc/oidc/callback`
  - `https://<vault-addr>/oidc/callback`
- **Client secret**: create one under Certificates & secrets

Collect the **Directory (tenant) ID**, **Application (client) ID**, and the **client secret value**.

**Enable OIDC**

Copy the example file and fill in the values from your app registration:

```bash
cp oidc.env.example ../../../local/oidc.env
# Edit local/oidc.env: replace tenant-id, client-id, client-secret
```

`TF_VAR_vault_external_addr` controls the redirect URIs registered in Vault. It defaults to `https://localhost:8200` in `env.sh`. If the browser reaches Vault at a different address (e.g. the VM's IP directly), add an override to `local/oidc.env`:

```bash
export TF_VAR_vault_external_addr="https://<vault-ip>:8200"
```

Then apply:

```bash
source env.sh
terraform apply
```

> Authenticated users receive the `default` Vault policy, which grants access to the personal cubbyhole only. See `FUTURE.md` for planned improvements.

### PKI (optional)

PKI is enabled and configured via `local/pki.env`, which `env.sh` sources automatically. The full PKI flow requires three steps run in sequence.

> If you know from the start that you want PKI, you can skip the apply above and go directly to Step 1.

**Step 1 — Create mounts and root CA:**

```bash
TF_VAR_enable_pki=true TF_VAR_pki_intermediate_ready=false terraform apply
```

**Step 2 — Set up the intermediate CA** (Ansible, from the `ansible/` directory):

```bash
source vault-env.sh
ansible-playbook setup-intermediate.yml
```

**Step 3 — Configure issuer, replace Vault's TLS certificate, and save PKI flags:**

In the `terraform/` directory:

```bash
cp pki.env.example ../../../local/pki.env
source env.sh
terraform apply
```

And then from the `ansible/` directory:

```bash
source vault-env.sh
ansible-playbook configure-tls.yml
```

After step 3, `local/vault-ca.pem` exists and `env.sh` automatically switches from `VAULT_SKIP_VERIFY=true` to `VAULT_CACERT` on subsequent runs. `local/pki.env` is also now in place, so all future `source env.sh && terraform apply` invocations work without any overrides.

### Intermediate CA rotation

```bash
# 1. Generate new intermediate, sign with root, import and promote as default
source vault-env.sh
ansible-playbook rotate-intermediate.yml   # (future playbook)

# 2. Re-apply issuer config to the new default issuer
source env.sh
terraform apply

# 3. Issue a new Vault TLS cert from the new intermediate
ansible-playbook configure-tls.yml
```

### Destroy

```bash
source env.sh
terraform destroy
```
