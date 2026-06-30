# IaC — Vault

Experiment repo for exploring how to manage a HashiCorp Vault instance using infrastructure-as-code tooling.

## Motivation

Two common failure modes when automating Vault:

- **Ansible-only configuration**: Playbooks grow large to enforce idempotency that Terraform provides for free, and there is no equivalent of `plan` or `destroy`.
- **Terraform-only**: Procedural bootstrap sequences — especially the PKI chain (root CA → intermediate → Vault TLS cert) — are awkward to express declaratively.

This repo explores alternative approaches to that trade-off.

## Structure

```
shared/ansible/roles/   Ansible roles shared across all approaches
test-scripts/           Vault API test scripts, usable across all approaches
docs/decisions/         Architecture Decision Records
approaches/             Self-contained alternative implementations
  01-ansible-tf-hybrid/ Ansible bootstrap + Terraform config
  02-tf-heavy/          Ansible bootstrap only; Terraform manages PKI lifecycle
```

## Target Environment

Requires a fresh Ubuntu 24.04 VM and an Ansible inventory file pointing to it. How the VM is provisioned is out of scope for this repo.

Expected inventory layout:

```yaml
all:
  hosts:
    vault-01:
      ansible_host: <ip>
      ansible_user: ubuntu
      ansible_ssh_private_key_file: <path-to-key>
```

The default inventory path assumed by the playbooks is `../../inventory.yaml` (relative to this repo's root).

## Local Setup

After cloning, activate the git hooks:

```bash
git config core.hooksPath .githooks
```

This enables a pre-commit hook that runs `ansible-lint` on any staged Ansible files.

## Approaches

| # | Name | Description | Status |
|---|------|-------------|--------|
| 01 | ansible-tf-hybrid | Ansible bootstrap, Terraform config | Initial version |
| 02 | tf-heavy | Ansible bootstrap only; Terraform manages full PKI lifecycle including intermediate CA rotation | Initial version |

See each approach's `README.md` for quickstart instructions and design decisions.

See `docs/decisions/` for Architecture Decision Records covering choices that span approaches.
