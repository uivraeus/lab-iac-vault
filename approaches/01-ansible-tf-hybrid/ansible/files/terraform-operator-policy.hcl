# Permissions for the terraform-operator AppRole used by Terraform to manage
# ongoing Vault configuration (auth methods, policies, secret engines, PKI).

path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "sys/policies/acl" {
  capabilities = ["list"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

path "sys/mounts" {
  capabilities = ["read"]
}

path "pki/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki_int/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "auth/oidc/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Used by the Vault Terraform provider to check its own capabilities on startup
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Required for the Vault Terraform provider to create a short-lived child token
# per run. Vault prevents privilege escalation: child tokens cannot receive
# policies the creator does not already hold.
path "auth/token/create" {
  capabilities = ["update"]
}
