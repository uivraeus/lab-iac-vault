resource "vault_mount" "pki" {
  path                      = var.pki_root_path
  type                      = "pki"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = var.pki_root_max_ttl
  description               = "Root CA"
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = var.pki_root_common_name
  ttl         = var.pki_root_cert_ttl
  issuer_name = "root"
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_config_urls" "pki" {
  backend                = vault_mount.pki.path
  issuing_certificates   = ["${var.vault_addr}/v1/${var.pki_root_path}/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/${var.pki_root_path}/crl"]
  ocsp_servers           = ["${var.vault_addr}/v1/${var.pki_root_path}/ocsp"]
}

resource "vault_mount" "pki_int" {
  path                      = var.pki_int_path
  type                      = "pki"
  default_lease_ttl_seconds = 3600
  max_lease_ttl_seconds     = var.pki_int_max_ttl
  description               = "Intermediate CA"
}

resource "vault_pki_secret_backend_config_urls" "pki_int" {
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = ["${var.vault_addr}/v1/${var.pki_int_path}/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/${var.pki_int_path}/crl"]
  ocsp_servers            = ["${var.vault_addr}/v1/${var.pki_int_path}/ocsp"]
}

# --- Intermediate CA issuers ---
#
# ROTATION CONVENTION — append a new identifier to var.pki_intermediates; never remove or reorder.
# Old issuers stay in Vault so certs they issued remain verifiable until expiry.
# The last entry in the list is always the active default issuer.
#
# To rotate:
#   1. Append a new identifier to pki_intermediates in pki.env (and pki.env.example).
#   2. terraform apply — new intermediate created and promoted to default automatically.
#   3. Optional: run configure-tls.yml to re-issue Vault's server TLS cert from the new intermediate.
#
# WARNING: do not change key_type or key_bits in modules/pki_intermediate/main.tf after the
# first intermediate exists — those fields force recreation and would break issued certificates.

module "intermediate" {
  for_each         = toset(var.pki_intermediates)
  source           = "./modules/pki_intermediate"
  pki_root_path    = vault_mount.pki.path
  pki_int_path     = vault_mount.pki_int.path
  vault_addr       = var.vault_addr
  serial           = each.key
  pki_int_cert_ttl = var.pki_int_cert_ttl
  depends_on = [
    vault_pki_secret_backend_root_cert.root,
    vault_pki_secret_backend_config_urls.pki_int,
  ]
}

resource "vault_generic_endpoint" "pki_int_default_issuer" {
  path                 = "${vault_mount.pki_int.path}/config/issuers"
  ignore_absent_fields = true
  disable_delete       = true
  disable_read         = true  # Vault normalises the default issuer name to a UUID on read; skip read to avoid perpetual drift
  data_json = jsonencode({
    default                       = module.intermediate[var.pki_intermediates[length(var.pki_intermediates) - 1]].issuer_name
    default_follows_latest_issuer = false
  })
  depends_on = [module.intermediate]
}

# --- End of intermediate CA issuers ---

resource "vault_pki_secret_backend_role" "issue" {
  backend        = vault_mount.pki_int.path
  name           = "issue"
  issuer_ref     = "default"
  key_type       = "ed25519"
  ttl            = var.pki_default_ttl
  max_ttl        = var.pki_max_ttl
  allow_any_name = false
  allowed_domains = [var.pki_allowed_domain]
  allow_subdomains = true
  allow_ip_sans  = true
  allow_localhost = true
  server_flag    = true
  client_flag    = false
}

resource "vault_pki_secret_backend_role" "sign" {
  backend        = vault_mount.pki_int.path
  name           = "sign"
  issuer_ref     = "default"
  key_type       = "any"
  ttl            = var.pki_default_ttl
  max_ttl        = var.pki_max_ttl
  allow_any_name = false
  allowed_domains = [var.pki_allowed_domain]
  allow_subdomains = true
  allow_ip_sans  = true
  allow_localhost = true
  server_flag    = true
  client_flag    = false
}

resource "vault_policy" "pki_admin" {
  name = "pki-admin"
  policy = <<-EOT
    path "${var.pki_int_path}/issue/*" {
      capabilities = ["update"]
    }
    path "${var.pki_int_path}/sign/*" {
      capabilities = ["update"]
    }
    path "${var.pki_int_path}/roles" {
      capabilities = ["list"]
    }
    path "${var.pki_int_path}/roles/*" {
      capabilities = ["read"]
    }
    path "${var.pki_int_path}/certs" {
      capabilities = ["list"]
    }
    path "${var.pki_int_path}/cert/*" {
      capabilities = ["read"]
    }
    path "${var.pki_int_path}/keys" {
      capabilities = ["list"]
    }
    path "${var.pki_int_path}/key/*" {
      capabilities = ["read"]
    }
    path "${var.pki_int_path}/revoke" {
      capabilities = ["create", "update"]
    }
  EOT
}
