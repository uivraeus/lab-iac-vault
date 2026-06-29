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
  validation {
    condition     = length(setsubtract(keys(var.oidc_group_ids), ["secret-reader", "secret-writer", "pki-admin"])) == 0
    error_message = "Valid keys are: secret-reader, secret-writer, pki-admin"
  }
  validation {
    # At least one entry is required so that bound_claims always gates login.
    # An empty map would result in no bound_claims, allowing any authenticated IdP user in.
    condition     = length(var.oidc_group_ids) > 0
    error_message = "oidc_group_ids must contain at least one entry"
  }
}

variable "enable_pki" {
  description = "When false, the pki-admin entry is excluded from oidc_group_ids even if provided"
  type        = bool
  default     = false
}
