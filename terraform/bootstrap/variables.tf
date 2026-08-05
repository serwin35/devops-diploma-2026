variable "state_bucket" {
  type        = string
  nullable    = false
  default     = "terraform-states-wf"
  description = "Bucket na stan Terraforma - musi zgadzać się z backendem w ../providers.tf"
}

variable "state_region" {
  type        = string
  nullable    = false
  default     = "us-east-1"
  description = "Region bucketa ze stanem - musi zgadzać się z backendem"
}

variable "backups_bucket" {
  type        = string
  nullable    = false
  default     = "wolffire-backups"
  description = "Bucket na kopie zapasowe maszyn i baz"
}

variable "backups_region" {
  type        = string
  nullable    = false
  default     = "eu-north-1"
  description = "Region kopii zapasowych - bliżej serwera, taniej za transfer"
}

variable "backup_retention_days" {
  type        = number
  nullable    = false
  default     = 90
  description = "Po ilu dniach kopie są usuwane"
}

variable "alerts_email" {
  description = "Adres, na który SNS dostarcza alerty z Alertmanagera"
  type        = string
  default     = "mateusz.serwinowski@gmail.com"
}
