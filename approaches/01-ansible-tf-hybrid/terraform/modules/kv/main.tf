resource "vault_mount" "kv" {
  path        = var.kv_path
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine"
}
