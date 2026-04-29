provider "azurerm" {
  features {
    key_vault {
      # Soft-delete is on by default; allow Terraform to permanently purge
      # destroyed key vaults so re-applies don't trip on name reuse.
      purge_soft_deleted_secrets_on_destroy = true
      purge_soft_delete_on_destroy          = true
      recover_soft_deleted_key_vaults       = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "azuread" {}

provider "kubernetes" {
  host                   = module.aks.host
  client_certificate     = base64decode(module.aks.client_certificate)
  client_key             = base64decode(module.aks.client_key)
  cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = module.aks.host
    client_certificate     = base64decode(module.aks.client_certificate)
    client_key             = base64decode(module.aks.client_key)
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  }
}
