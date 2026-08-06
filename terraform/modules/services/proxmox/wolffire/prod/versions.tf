terraform {
  required_version = "1.14.4"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.94.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.31.0"
    }
  }
}
