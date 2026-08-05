resource "proxmox_virtual_environment_firewall_alias" "this" {
  for_each = local.aliases

  name = each.key
  cidr = each.value
}

resource "proxmox_virtual_environment_firewall_ipset" "admins" {
  name    = "admins"
  comment = "Adresy administratora dopuszczone do hosta Proxmoxa"

  dynamic "cidr" {
    for_each = var.admin_ips

    content {
      name = cidr.value
    }
  }
}

# Adresy bram wszystkich vnetów, czyli sam hypervisor widziany z sieci gości.
# Potrzebne wyłącznie na etapie provisioningu - Ansible musi dosięgnąć maszyn,
# zanim bastion zostanie skonfigurowany i przejmie rolę jump hosta.
resource "proxmox_virtual_environment_firewall_ipset" "hypervisor" {
  name    = "hypervisor"
  comment = "Bramy vnetow - hypervisor jako jump host na czas provisioningu"

  dynamic "cidr" {
    for_each = var.vnets

    content {
      name = "10.0.${cidr.value}.1"
    }
  }
}

resource "proxmox_virtual_environment_cluster_firewall_security_group" "this" {
  for_each = local.security_groups

  name = each.key

  dynamic "rule" {
    for_each = each.value

    content {
      type    = "in"
      action  = "ACCEPT"
      comment = rule.value.name
      proto   = try(rule.value.protocol, null)
      dport   = try(rule.value.port, null)
      source  = try(rule.value.source, null)
      log     = "info"
    }
  }

  depends_on = [
    proxmox_virtual_environment_firewall_alias.this,
    proxmox_virtual_environment_firewall_ipset.admins,
    proxmox_virtual_environment_firewall_ipset.hypervisor,
  ]
}

# Reguły na poziomie klastra dotyczą także samego hosta. Kolejność ma znaczenie:
# reguła wpuszczająca SSH musi istnieć, zanim polityka wejściowa przejdzie na DROP,
# inaczej apply kończy się odcięciem dostępu do serwera.
resource "proxmox_virtual_environment_firewall_rules" "cluster" {
  rule {
    security_group = proxmox_virtual_environment_cluster_firewall_security_group.this["host-admin"].name
  }
}

resource "proxmox_virtual_environment_cluster_firewall" "this" {
  enabled        = true
  input_policy   = "DROP"
  output_policy  = "ACCEPT"
  forward_policy = "ACCEPT"

  depends_on = [
    proxmox_virtual_environment_firewall_rules.cluster,
  ]
}
