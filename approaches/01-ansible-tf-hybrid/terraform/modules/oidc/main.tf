resource "vault_jwt_auth_backend" "oidc" {
  type               = "oidc"
  path               = "oidc"
  oidc_discovery_url = var.oidc_discovery_url
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  default_role       = "default"
}

resource "vault_jwt_auth_backend_role" "default" {
  backend   = vault_jwt_auth_backend.oidc.path
  role_name = "default"
  role_type = "oidc"

  oidc_scopes = ["openid", "profile", "email"]
  user_claim  = "sub"

  allowed_redirect_uris = [
    "${var.vault_external_addr}/ui/vault/auth/oidc/oidc/callback",
    "${var.vault_external_addr}/oidc/callback",
  ]

  token_policies = ["default"]
}
