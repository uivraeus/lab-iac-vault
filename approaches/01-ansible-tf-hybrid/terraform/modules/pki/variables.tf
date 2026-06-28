variable "pki_root_path" {
  description = "Mount path for the root CA"
  type        = string
  default     = "pki"
}

variable "pki_int_path" {
  description = "Mount path for the intermediate CA"
  type        = string
  default     = "pki_int"
}

variable "pki_root_max_ttl" {
  description = "Maximum TTL for the root CA mount in seconds (default 10 years)"
  type        = number
  default     = 315360000
}

variable "pki_int_max_ttl" {
  description = "Maximum TTL for the intermediate CA mount in seconds (default 5 years)"
  type        = number
  default     = 157680000
}

variable "pki_root_common_name" {
  description = "Common name for the root CA certificate"
  type        = string
  default     = "Lab Root CA"
}

variable "pki_root_cert_ttl" {
  description = "Validity period for the root CA certificate"
  type        = string
  default     = "87600h"
}

variable "vault_addr" {
  description = "Vault address used as base for AIA, CRL, and OCSP URLs"
  type        = string
}

variable "pki_intermediate_ready" {
  description = "Set to false on first apply before Ansible setup-intermediate has run"
  type        = bool
  default     = true
}

variable "pki_server_role_ttl" {
  description = "Default TTL for server certificates in seconds (default 30 days)"
  type        = string
  default     = "2592000"
}

variable "pki_server_role_max_ttl" {
  description = "Maximum TTL for server certificates in seconds (default 1 year)"
  type        = string
  default     = "31536000"
}
