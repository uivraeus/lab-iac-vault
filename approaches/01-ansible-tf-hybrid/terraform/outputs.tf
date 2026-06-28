output "kv_path" {
  description = "Mount path of the KV v2 secrets engine"
  value       = module.kv.kv_path
}

output "oidc_path" {
  description = "Mount path of the OIDC auth method (empty when OIDC is disabled)"
  value       = var.enable_oidc ? module.oidc[0].oidc_path : ""
}
