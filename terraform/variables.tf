variable "proxmox_endpoint" {
  type        = string
  nullable    = false
  description = "Adres API Proxmoxa. Do czasu postawienia tunelu jest to publiczny IP; potem https://proxmox.wolffire.dev"
}

variable "proxmox_node_names" {
  type        = map(string)
  nullable    = false
  description = "Nazwy nodów Proxmoxa wraz z adresami DNS jako wartościami"
}

variable "proxmox_users" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Adresy e-mail użytkowników konsoli Proxmoxa"
}

variable "proxmox_resource_pools" {
  type        = set(string)
  nullable    = false
  default     = []
  description = "Pule zasobow do utworzenia"
}

variable "ansible_user" {
  type        = string
  nullable    = false
  default     = "ansible"
  description = "Użytkownik SSH zakładany na hoście i we wszystkich VM-kach"
}

variable "terraform_ssh_user" {
  type        = string
  nullable    = false
  default     = "terraform"
  description = "Użytkownik SSH na hoście Proxmoxa używany wyłącznie przez Terraform do wgrywania snippetów"
}

variable "ssh_port" {
  type        = number
  nullable    = false
  default     = 22022
  description = "Niestandardowy port SSH - na hoście i we wszystkich VM-kach"
}

variable "ssh_public_keys" {
  type        = list(string)
  nullable    = false
  description = "Klucze publiczne wsiewane przez cloud-init do użytkownika ansible"
}

variable "admin_ips" {
  type        = list(string)
  nullable    = false
  description = "Adresy IP/CIDR, z których dopuszczony jest SSH i UI hosta Proxmoxa"
}

variable "zone" {
  type        = string
  nullable    = false
  default     = "wolffire.dev"
  description = "Strefa DNS zarządzana w Cloudflare"
}

variable "cloudflare_account_name" {
  type        = string
  nullable    = false
  description = "Nazwa konta Cloudflare, w którym powstają tunele i aplikacje Access"
}

variable "access_emails" {
  type        = set(string)
  nullable    = false
  description = "Adresy e-mail dopuszczone przez Zero Trust Access do paneli"
}


variable "bastion_public_ip" {
  type        = string
  default     = null
  description = "Dodatkowy adres publiczny OVH dla bastionu. Puste = bastion tylko w sieci prywatnej"
}

variable "bastion_mac_address" {
  type        = string
  default     = null
  description = "Wirtualny MAC utworzony dla adresu bastionu w panelu OVH"
}

# UWAGA: zmienna nie jest jeszcze przekazywana do modułu proxmox_bootstrap,
# więc adresacja IPv6 pozostaje wyłączona niezależnie od jej wartości.
# Włączenie = dopisanie ipv6_prefix i ipv6_vnets = ["dmz"] do wywołania modułu
# w main.tf; zmienia to konfigurację sieciową bastionu, więc wymaga apply
# przygotowanego świadomie, a nie przy okazji.
variable "ipv6_prefix" {
  type        = string
  default     = null
  description = "Blok IPv6 routowany przez OVH na serwer (/64). Puste = brak adresacji IPv6"
}
