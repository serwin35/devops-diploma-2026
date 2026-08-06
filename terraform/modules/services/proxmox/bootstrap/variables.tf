variable "node_name" {
  type        = string
  nullable    = false
  description = "Nazwa noda Proxmoxa"
}

variable "users" {
  type        = set(string)
  default     = []
  nullable    = false
  description = "Użytkownicy konsoli Proxmoxa (adresy e-mail)"
}

variable "resource_pools" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Pule zasobów do utworzenia"
}

variable "vnets" {
  type        = map(number)
  nullable    = false
  description = "Mapa vnet -> numer segmentu. Numer jest trzecim oktetem podsieci 10.0.<numer>.0/24"
}

variable "ssh_port" {
  type        = number
  nullable    = false
  description = "Port SSH dopuszczony w grupie bezpieczeństwa 'base'"
}

variable "admin_ips" {
  type        = list(string)
  nullable    = false
  description = "Adresy administratora - dostęp do SSH i UI hosta zanim stanie tunel"
}

variable "monitoring_ip" {
  type        = string
  nullable    = false
  description = "Adres Prometheusa - jedyne źródło dopuszczone do portów eksporterów"
}

variable "zfs_pool" {
  type        = string
  nullable    = false
  default     = "data"
  description = "Istniejący pool ZFS, na którym powstaną ZVOL-e dysków VM-ek"
}

variable "cloud_image_url" {
  type        = string
  nullable    = false
  default     = "https://cloud-images.ubuntu.com/releases/noble/release/ubuntu-24.04-server-cloudimg-amd64.img"
  description = "Obraz cloud-image Ubuntu 24.04 LTS"
}

variable "ssh_public_keys" {
  type        = list(string)
  nullable    = false
  description = "Klucze publiczne użytkownika ansible wsiewane przez cloud-init"
}

variable "ansible_user" {
  type        = string
  nullable    = false
  default     = "ansible"
  description = "Użytkownik zakładany przez cloud-init we wszystkich VM-kach"
}

variable "ipv6_prefix" {
  type        = string
  default     = null
  description = "Blok IPv6 routowany przez OVH na serwer (/64). Puste = brak adresacji IPv6"
}

variable "ipv6_vnets" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Vnety, które dostają publiczną adresację IPv6 z bloku"
}

variable "cicd_ip" {
  type        = string
  nullable    = false
  description = "Adres maszyny CI/CD - jedyne poza klastrem źródło dopuszczone do bazy (pg_dump)"
}

variable "cloudflare_account_name" {
  type        = string
  nullable    = false
  description = "Nazwa konta Cloudflare, w którym stoi tunel hypervisora"
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
  description = "Adresy e-mail dopuszczone przez Zero Trust Access do UI Proxmoxa"
}
