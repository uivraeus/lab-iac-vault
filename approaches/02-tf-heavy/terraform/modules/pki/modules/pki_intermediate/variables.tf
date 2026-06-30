variable "pki_root_path" {
  description = "Mount path for the root CA"
  type        = string
}

variable "pki_int_path" {
  description = "Mount path for the intermediate CA"
  type        = string
}

variable "vault_addr" {
  description = "Vault address used as base for AIA, CRL, and OCSP URLs"
  type        = string
}

variable "serial" {
  description = "Zero-padded serial number for this intermediate, e.g. 001"
  type        = string
}

variable "pki_int_cert_ttl" {
  description = "Validity period for the intermediate CA certificate in seconds"
  type        = number
}
