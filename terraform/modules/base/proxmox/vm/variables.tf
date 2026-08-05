variable "name" {
  type        = string
  nullable    = false
  description = "Nazwa VM-ki, jednocześnie hostname ustawiany przez cloud-init"
}

variable "node_name" {
  type        = string
  nullable    = false
  description = "Nazwa noda Proxmoxa"
}

variable "vm_id" {
  type        = number
  nullable    = false
  description = "Numer VM-ki w Proxmoxie"
}

variable "pool_id" {
  type        = string
  default     = null
  description = "Pula zasobów, do której trafia VM-ka"
}

variable "tags" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Tagi VM-ki - źródło grup dla inventory Ansible"
}

variable "cpu" {
  type        = number
  nullable    = false
  description = "Liczba rdzeni"
}

variable "ram" {
  type        = number
  nullable    = false
  description = "RAM w MB"
}

variable "disk" {
  type        = number
  nullable    = false
  description = "Rozmiar dysku w GB"
}

variable "datastore_id" {
  type        = string
  nullable    = false
  description = "Datastore na dysk VM-ki (pool ZFS zarejestrowany jako zfspool)"
}

variable "image_file_id" {
  type        = string
  nullable    = false
  description = "ID pobranego cloud-image, z którego klonowany jest dysk"
}

variable "cloud_init_file_id" {
  type        = string
  nullable    = false
  description = "ID snippetu cloud-init (user-data)"
}

variable "vnet_id" {
  type        = string
  nullable    = false
  description = "Vnet SDN, do którego podpięta jest VM-ka"
}

variable "private_ip" {
  type        = string
  nullable    = false
  description = "Statyczny adres w obrębie vnetu"
}

variable "gateway" {
  type        = string
  nullable    = false
  description = "Brama vnetu (adres .1 podsieci)"
}

variable "firewall_sgs" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Grupy bezpieczeństwa doczepiane poza obowiązkową grupą 'base'"
}

variable "public_ip" {
  type        = string
  default     = null
  description = "Dodatkowy adres publiczny OVH. Ustawiony wyłącznie na bastionie - reszta maszyn nie jest widoczna z internetu"
}

variable "mac_address" {
  type        = string
  default     = null
  description = "Wirtualny MAC przypisany do adresu publicznego w panelu OVH. Bez niego OVH nie routuje ruchu do maszyny"
}

variable "public_ipv6" {
  type        = string
  default     = null
  description = "Publiczny adres IPv6 wraz z maską, np. 2001:db8::10/80"
}

variable "ipv6_gateway" {
  type        = string
  default     = null
  description = "Brama IPv6 - adres hosta w podprefiksie segmentu"
}
