terraform {
  required_version = "1.14.4"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.16.0"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.94.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}
