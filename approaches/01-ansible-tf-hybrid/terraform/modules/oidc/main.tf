locals {
  effective_group_ids = {
    for k, v in var.oidc_group_ids : k => v
    if v != "" && (k != "pki-admin" || var.enable_pki)
  }
}

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

  oidc_scopes  = ["openid", "profile", "email"]
  user_claim   = "sub"
  groups_claim = "groups"

  allowed_redirect_uris = [
    "${var.vault_external_addr}/ui/vault/auth/oidc/oidc/callback",
    "${var.vault_external_addr}/oidc/callback",
  ]

  token_policies = ["default"]
}

resource "vault_identity_group" "oidc" {
  for_each = local.effective_group_ids
  name     = each.key
  type     = "external"
  policies = [each.key]
}

resource "vault_identity_group_alias" "oidc" {
  for_each       = local.effective_group_ids
  name           = each.value
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.oidc[each.key].id
}
