# ADR-001: Ansible for bootstrap, Terraform for configuration

## Status

Accepted

## Context

Managing Vault with a single tool leads to trade-offs:

- **Ansible only**: Config playbooks grow large to enforce idempotency manually. No equivalent of `terraform plan` or `destroy`.
- **Terraform only**: Procedural bootstrap sequences (PKI chain, initialization, unseal) are awkward to express declaratively. Some steps are genuinely one-time and order-dependent.

## Decision

Split responsibility at the bootstrap boundary:

- **Ansible** handles installation, initialization, unsealing, and procedural PKI steps: generating the intermediate CA (CSR → sign → import) and issuing Vault's own TLS certificate from it. These steps are sequential, often one-time, and map naturally to tasks and handlers.
- **Terraform** (using the Vault provider) handles everything declarative: auth methods, policies, secret engine mounts, PKI roles, and the root CA itself. These benefit from `plan`/`destroy` semantics and are safe to re-apply.

The handoff point is explicit: Ansible's bootstrap phase creates a `terraform-operator` AppRole, whose credentials Terraform uses to authenticate for all subsequent operations.

## Consequences

- Two tools must be understood and maintained.
- The Ansible/Terraform boundary must be documented clearly — drift between what each tool "owns" is the main risk.
- Rotation of the `terraform-operator` AppRole credentials needs a defined process (likely a dedicated Ansible playbook).
- Token rotation and PKI intermediate rotation remain in Ansible as separate playbooks, keeping the procedural nature explicit.
