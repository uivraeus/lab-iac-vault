output "oidc_path" {
  description = "Mount path of the OIDC auth method"
  value       = vault_jwt_auth_backend.oidc.path
}
