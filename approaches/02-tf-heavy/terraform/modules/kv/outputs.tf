output "kv_path" {
  description = "Mount path of the KV v2 secrets engine"
  value       = vault_mount.kv.path
}
