variable "node_name" {
  type        = string
  nullable    = false
  description = "Nazwa noda Proxmoxa"
}

variable "pool_id" {
  type        = string
  nullable    = false
  description = "Pula zasobów, do której trafiają maszyny"
}

variable "datastore_id" {
  type        = string
  nullable    = false
  description = "Datastore na dyski VM-ek"
}

variable "image_file_id" {
  type        = string
  nullable    = false
  description = "ID cloud-image Ubuntu"
}

variable "cloud_init_file_id" {
  type        = string
  nullable    = false
  description = "ID snippetu cloud-init"
}

variable "cloudflare_account_name" {
  type        = string
  nullable    = false
  description = "Nazwa konta Cloudflare, w którym stoi tunel maszyny"
}

variable "zone" {
  type        = string
  nullable    = false
  description = "Strefa DNS, w której tunel tworzy rekordy"
}

variable "allowed_emails" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Adresy e-mail dopuszczone przez Zero Trust Access do paneli maszyny"
}
