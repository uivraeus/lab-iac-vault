variable "vault_addr" {
  description = "Vault server address"
  type        = string
}

variable "vault_role_id" {
  description = "AppRole role_id for terraform-operator"
  type        = string
  ephemeral   = true
}

variable "vault_secret_id" {
  description = "AppRole secret_id for terraform-operator"
  type        = string
  ephemeral   = true
}

variable "enable_pki" {
  description = "Enable PKI secrets engine (root CA + intermediate CA mounts)"
  type        = bool
}

variable "pki_int_cert_ttl" {
  description = "Validity period for each intermediate CA certificate in seconds (default 5 years)"
  type        = number
  default     = 157680000
}

variable "enable_oidc" {
  description = "Enable OIDC auth method"
  type        = bool
  default     = false
}

variable "vault_external_addr" {
  description = "External Vault address used in OIDC redirect URIs"
  type        = string
  default     = "https://localhost:8200"
}

variable "oidc_discovery_url" {
  description = "OIDC discovery URL (e.g. https://login.microsoftonline.com/{tenant_id}/v2.0)"
  type        = string
  default     = ""
}

variable "oidc_client_id" {
  description = "OIDC client ID from the IdP app registration"
  type        = string
  default     = ""
}

variable "oidc_client_secret" {
  description = "OIDC client secret from the IdP app registration"
  type        = string
  default     = ""
  sensitive   = true
}

variable "oidc_group_ids" {
  description = "Map of Vault policy name to IdP group object ID (keys: secret-reader, secret-writer, pki-admin)"
  type        = map(string)
  default     = {}
  validation {
    condition     = length(setsubtract(keys(var.oidc_group_ids), ["secret-reader", "secret-writer", "pki-admin"])) == 0
    error_message = "Valid keys are: secret-reader, secret-writer, pki-admin"
  }
}
