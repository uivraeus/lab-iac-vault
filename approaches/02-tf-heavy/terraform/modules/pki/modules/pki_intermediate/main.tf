resource "vault_pki_secret_backend_intermediate_cert_request" "this" {
  backend     = var.pki_int_path
  type        = "internal"
  common_name = "Lab Intermediate CA ${var.serial}"
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_root_sign_intermediate" "this" {
  backend        = var.pki_root_path
  csr            = vault_pki_secret_backend_intermediate_cert_request.this.csr
  common_name    = "Lab Intermediate CA ${var.serial}"
  ttl            = var.pki_int_cert_ttl
  use_csr_values = true
}

resource "vault_pki_secret_backend_intermediate_set_signed" "this" {
  backend     = var.pki_int_path
  certificate = "${vault_pki_secret_backend_root_sign_intermediate.this.certificate}\n${vault_pki_secret_backend_root_sign_intermediate.this.issuing_ca}"
}

resource "vault_pki_secret_backend_issuer" "this" {
  backend                 = var.pki_int_path
  issuer_ref              = vault_pki_secret_backend_intermediate_set_signed.this.imported_issuers[0]
  issuer_name             = "intermediate-${var.serial}"
  issuing_certificates    = ["${var.vault_addr}/v1/${var.pki_int_path}/ca"]
  crl_distribution_points = ["${var.vault_addr}/v1/${var.pki_int_path}/crl"]
  ocsp_servers            = ["${var.vault_addr}/v1/${var.pki_int_path}/ocsp"]
}
