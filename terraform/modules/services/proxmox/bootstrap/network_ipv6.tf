# OVH routuje na serwer cały blok /64 i traktuje go jako on-link na vmbr0.
# Zamiast mostkować maszyny prosto do vmbr0 i liczyć na to, że OVH odpowie
# na NDP dla obcego MAC-a, host pełni rolę routera: wydziela z bloku podprefiks
# /80 dla segmentu i odpowiada za niego przez proxy NDP (rola ipv6_router).
#
# Indeks podprefiksu to numer segmentu, a nie kolejna liczba - podprefiks o indeksie 0
# zawierałby adres samego hosta (używa on adresu z wyzerowaną częścią hosta).
#
#   dmz (numer 110) -> cidrsubnet(prefix, 16, 110) -> 2001:41d0:602:4f1a:6e::/80
#
# Adres .1 podprefiksu należy do hosta i jest bramą dla maszyn w segmencie.
locals {
  ipv6_subnets = var.ipv6_prefix == null ? {} : {
    for name in var.ipv6_vnets : name => {
      cidr    = cidrsubnet(var.ipv6_prefix, 16, var.vnets[name])
      gateway = cidrhost(cidrsubnet(var.ipv6_prefix, 16, var.vnets[name]), 1)
    }
  }
}

resource "proxmox_virtual_environment_sdn_subnet" "ipv6" {
  for_each = local.ipv6_subnets

  vnet    = proxmox_virtual_environment_sdn_vnet.this[each.key].id
  cidr    = each.value.cidr
  gateway = each.value.gateway
  # Bez NAT-u: w IPv6 każda maszyna ma adres globalny i jest routowana wprost.
  snat = false
}
