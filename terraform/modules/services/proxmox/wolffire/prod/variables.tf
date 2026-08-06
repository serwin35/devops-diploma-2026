variable "app_storage_bucket" {
  type        = string
  nullable    = false
  default     = "wolffire-app-storage"
  description = "Bucket na pliki aplikacji (Laravel FILESYSTEM_DISK=s3). Nazwa musi zgadzać się z polityką klucza stanu w terraform/bootstrap/iam.tf"
}

variable "zone" {
  type        = string
  nullable    = false
  description = "Domena publiczna aplikacji - origin dopuszczony w CORS bucketa"
}

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
