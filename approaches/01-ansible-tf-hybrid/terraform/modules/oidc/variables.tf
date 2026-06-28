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
