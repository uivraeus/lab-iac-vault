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

resource "vault_pki_secret_backend_issuer" "intermediate" {
  count       = var.pki_intermediate_ready ? 1 : 0
  backend     = vault_mount.pki_int.path
  issuer_ref  = "default"
  issuer_name = "intermediate"

  issuing_certificates    = ["${var.vault_addr}/v1/${var.pki_int_path}/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/${var.pki_int_path}/crl"]
  ocsp_servers            = ["${var.vault_addr}/v1/${var.pki_int_path}/ocsp"]
}

resource "vault_pki_secret_backend_role" "server" {
  backend     = vault_mount.pki_int.path
  name        = "server"
  issuer_ref  = "default"
  key_type    = "rsa"
  key_bits    = 2048
  ttl         = var.pki_server_role_ttl
  max_ttl     = var.pki_server_role_max_ttl
  allow_any_name      = true
  allow_ip_sans       = true
  allow_localhost     = true
  server_flag         = true
  client_flag         = false
}

resource "vault_pki_secret_backend_config_urls" "pki_int" {
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = ["${var.vault_addr}/v1/${var.pki_int_path}/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/${var.pki_int_path}/crl"]
  ocsp_servers            = ["${var.vault_addr}/v1/${var.pki_int_path}/ocsp"]
}
