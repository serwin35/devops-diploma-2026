terraform {
  required_version = "1.14.4"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.94.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.16.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.31.0"
    }
  }

  backend "s3" {
    bucket       = "terraform-states-wf"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

# Poświadczenia wszystkich providerów wchodzą zmiennymi środowiskowymi
# z `sops exec-env secrets.sops.yaml` - patrz Makefile. Nic nie leży w tfvars.
provider "proxmox" {
  endpoint = var.proxmox_endpoint

  # Upload snippetów cloud-init idzie po SSH, nie przez API.
  ssh {
    agent       = false
    username    = var.terraform_ssh_user
    private_key = file("${path.root}/../keys/terraform_ed25519")

    dynamic "node" {
      for_each = var.proxmox_node_names

      content {
        name    = node.key
        address = node.value
        port    = var.ssh_port
      }
    }
  }
}

provider "cloudflare" {}

# Auth: te same AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (wolffire-tf-state)
# co backend stanu. Klucz ma poza stanem wyłącznie zawężone prawa do storage
# aplikacji - patrz ManageAppStorage* w bootstrap/iam.tf.
# Region jak kopie zapasowe: blisko serwera OVH, taniej za transfer.
provider "aws" {
  region = "eu-north-1"

  default_tags {
    tags = {
      managed_by = "terraform"
      project    = "wolffire-diploma"
    }
  }
}


