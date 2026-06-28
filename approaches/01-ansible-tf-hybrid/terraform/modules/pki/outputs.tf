output "pki_root_path" {
  description = "Mount path of the root CA"
  value       = vault_mount.pki.path
}

output "pki_int_path" {
  description = "Mount path of the intermediate CA"
  value       = vault_mount.pki_int.path
}

output "pki_intermediate_ready" {
  description = "True when issuer config has been applied to the intermediate CA"
  value       = var.pki_intermediate_ready
}
