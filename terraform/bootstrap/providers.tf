# Auth: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY z secrets.sops.yaml
provider "aws" {
  region = var.state_region

  default_tags {
    tags = {
      managed_by = "terraform"
      project    = "wolffire-diploma"
    }
  }
}

provider "aws" {
  alias  = "backups"
  region = var.backups_region

  default_tags {
    tags = {
      managed_by = "terraform"
      project    = "wolffire-diploma"
    }
  }
}
