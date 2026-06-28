terraform {
  required_version = ">= 1.10"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }
}

provider "vault" {
  address = var.vault_addr

  auth_login {
    path = "auth/approle/login"
    parameters = {
      role_id   = var.vault_role_id
      secret_id = var.vault_secret_id
    }
  }
}

module "kv" {
  source = "./modules/kv"
}

resource "vault_policy" "secret_reader" {
  name = "secret-reader"
  policy = <<-EOT
    path "secret/data/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

resource "vault_policy" "secret_writer" {
  name = "secret-writer"
  policy = <<-EOT
    path "secret/data/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
    path "secret/delete/*" {
      capabilities = ["update"]
    }
    path "secret/undelete/*" {
      capabilities = ["update"]
    }
  EOT
}


module "pki" {
  count  = var.enable_pki ? 1 : 0
  source = "./modules/pki"

  vault_addr             = var.vault_addr
  pki_intermediate_ready = var.pki_intermediate_ready
}

module "oidc" {
  count  = var.enable_oidc ? 1 : 0
  source = "./modules/oidc"

  vault_external_addr = var.vault_external_addr
  oidc_discovery_url  = var.oidc_discovery_url
  oidc_client_id      = var.oidc_client_id
  oidc_client_secret  = var.oidc_client_secret
  oidc_group_ids      = var.oidc_group_ids
  enable_pki          = var.enable_pki
}
