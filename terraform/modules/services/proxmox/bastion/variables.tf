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

variable "public_ip" {
  type        = string
  default     = null
  description = "Dodatkowy adres publiczny OVH przypisany bastionowi"
}

variable "mac_address" {
  type        = string
  default     = null
  description = "Wirtualny MAC utworzony dla tego adresu w panelu OVH"
}

variable "ipv6_subnet" {
  type = object({
    cidr    = string
    gateway = string
  })
  default     = null
  description = "Podprefiks IPv6 segmentu dmz wraz z adresem bramy na hoście"
}
