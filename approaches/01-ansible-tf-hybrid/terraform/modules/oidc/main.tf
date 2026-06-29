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

  # Require the user to be a member of at least one configured group.
  # Comma-separated values are treated as OR by Vault.
  # effective_group_ids excludes pki-admin when enable_pki=false, so the gate
  # only covers groups that are actually wired up.
  bound_claims = {
    groups = join(",", values(local.effective_group_ids))
  }

  allowed_redirect_uris = [
    "${var.vault_external_addr}/ui/vault/auth/oidc/oidc/callback",
    "${var.vault_external_addr}/oidc/callback",
  ]

  token_policies = ["default"]

  lifecycle {
    # Guard against the edge case where oidc_group_ids contains only pki-admin
    # but enable_pki=false — effective_group_ids would be empty, which would
    # result in bound_claims = { groups = "" }, silently removing the login gate.
    precondition {
      condition     = length(local.effective_group_ids) > 0
      error_message = "oidc_group_ids produces no effective entries after filtering. If pki-admin is the only key, enable_pki must be true."
    }
  }
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
