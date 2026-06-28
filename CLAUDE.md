# Claude Context — iac-vault

## Purpose

This repo experiments with different strategies for managing a HashiCorp Vault instance. The core question is where to draw the line between Ansible (procedural bootstrap) and Terraform (declarative configuration).

## Repository Layout

```
shared/ansible/roles/   Ansible roles used across all approaches
docs/decisions/         Architecture Decision Records (ADRs)
approaches/             One sub-directory per alternative strategy
```

Each approach under `approaches/` is self-contained with its own `ansible/` and `terraform/` directories, and its own `CLAUDE.md` for approach-specific context.

## Shared Ansible Roles

| Role | Purpose |
|------|---------|
| `vault_status` | Check Vault status, set `vault_status_initialized` and `vault_status_sealed` facts |
| `vault_install` | Install Vault binary, configure systemd service |
| `vault_init` | One-time init, saves unseal keys + root token to `local/` |
| `vault_unseal` | Unseal after restarts, reads keys from env vars |
| `vault_tokens` | Create terraform-operator AppRole, save credentials to `local/` |
| `vault_pki` | PKI engine setup and intermediate CA rotation |

Playbooks live inside each approach's `ansible/` directory and reference roles via `../../shared/ansible/roles`.

## Target Environment

A single Ubuntu 24.04 VM. Ansible inventory at `../../inventory.yaml` (relative to this repo root). SSH access via key, passwordless sudo.

## Key Design Decisions

See `docs/decisions/` for ADRs. Summary:

- Ansible handles installation and all procedural bootstrap (including PKI chain setup)
- Terraform (Vault provider) handles ongoing declarative config: auth methods, policies, secret engines, PKI roles
- The handoff point is a `terraform-operator` AppRole created by Ansible, which Terraform uses to authenticate
- PKI uses two separate mounts: `pki` (root CA) and `pki_int` (intermediate CA with named issuers for rotation)

## Deferred Decisions

- **AppRole credential storage**: The `terraform-operator` role_id and secret_id are saved to `local/` on the control node only. Storing them in Vault KV for easier retrieval was considered but deferred — KV is mounted by Terraform, which creates a chicken-and-egg dependency. Recovery path is to re-run `vault_tokens` with a root/admin token to regenerate. The same tension will apply to token rotation if that is addressed in the future.

## Active Approach

`approaches/01-ansible-tf-hybrid` — see its `CLAUDE.md` for current status and working notes.
