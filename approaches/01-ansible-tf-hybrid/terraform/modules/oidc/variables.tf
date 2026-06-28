variable "oidc_discovery_url" {
  description = "OIDC discovery URL (e.g. https://login.microsoftonline.com/{tenant_id}/v2.0)"
  type        = string
}

variable "oidc_client_id" {
  description = "OIDC client ID from the IdP app registration"
  type        = string
}

variable "oidc_client_secret" {
  description = "OIDC client secret from the IdP app registration"
  type        = string
  sensitive   = true
}

variable "vault_external_addr" {
  description = "External Vault address used in OIDC redirect URIs"
  type        = string
}

variable "oidc_group_ids" {
  description = "Map of Vault policy name to IdP group object ID. Omit a key to skip creating that group alias."
  type        = map(string)
  default     = {}
}

variable "enable_pki" {
  description = "When false, the pki-admin entry is excluded from oidc_group_ids even if provided"
  type        = bool
  default     = false
}
