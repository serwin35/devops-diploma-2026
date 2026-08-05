# Strefa "Simple": każdy vnet dostaje własny most na hoście, a host trasuje
# między nimi. Przy jednym nodzie nie ma po co sięgać po EVPN/VXLAN.
resource "proxmox_virtual_environment_sdn_zone_simple" "this" {
  id    = "dvz"
  nodes = [var.node_name]
  ipam  = "pve"
  mtu   = 1500
}

# Strefa Simple tworzy izolowane mosty bez tagowania VLAN - atrybut 'tag' jest
# dozwolony wyłącznie w strefach VLAN/QinQ/VXLAN/EVPN. Liczba przypisana segmentowi
# zostaje więc czystą konwencją adresacji (trzeci oktet podsieci), a nie tagiem.
resource "proxmox_virtual_environment_sdn_vnet" "this" {
  for_each = var.vnets

  zone = proxmox_virtual_environment_sdn_zone_simple.this.id
  id   = each.key
}

# snat = true załatwia wyjście VM-ek do internetu przez jedyny publiczny adres
# hosta. Żaden gość nie ma własnego publicznego IP - ruch przychodzący wchodzi
# wyłącznie tunelem Cloudflare.
resource "proxmox_virtual_environment_sdn_subnet" "this" {
  for_each = var.vnets

  vnet    = proxmox_virtual_environment_sdn_vnet.this[each.key].id
  cidr    = "10.0.${each.value}.0/24"
  gateway = "10.0.${each.value}.1"
  snat    = true
}

# SDN w Proxmoxie działa w modelu "pending -> apply". Bez tego zasobu zmiany
# leżą w konfiguracji, ale nie trafiają na mosty.
resource "proxmox_virtual_environment_sdn_applier" "this" {
  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_zone_simple.this,
      proxmox_virtual_environment_sdn_vnet.this,
      proxmox_virtual_environment_sdn_subnet.this,
      # Bez tego wpisu podsieć IPv6 zostaje w stanie "pending" - brama nie
      # powstaje na moście i cały ruch v6 do segmentu jest martwy.
      proxmox_virtual_environment_sdn_subnet.ipv6,
    ]
  }
}
