resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node_name
  vm_id     = var.vm_id
  pool_id   = var.pool_id
  tags      = var.tags

  # Bez tego restart hypervisora zostawia wszystkie maszyny zatrzymane
  # i trzeba je podnosić ręcznie.
  on_boot = true

  # Bez agenta Proxmox nie zna adresu IP gościa i nie potrafi go czysto wyłączyć.
  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.ram
    # Balloning: 25 GB przydzielone na 31 GB fizycznych, więc nieużywana pamięć
    # ma wracać do hosta zamiast leżeć odłogiem w gościu.
    floating = var.ram
  }

  # Jeden dysk na ZVOL-u. Rozdzielanie systemu i danych na osobne datastore'y ma
  # sens przy wielu poolach ZFS; tutaj pool jest jeden, więc podział nic nie wnosi.
  disk {
    datastore_id = var.datastore_id
    file_id      = var.image_file_id
    interface    = "scsi0"
    size         = var.disk
    discard      = "on"
    ssd          = true
  }

  # Karta wpięta prosto w vmbr0 z wirtualnym MAC-iem przypisanym do dodatkowego
  # adresu OVH. Powstaje tylko tam, gdzie maszyna ma być widoczna z internetu -
  # w praktyce wyłącznie na bastionie.
  dynamic "network_device" {
    for_each = var.mac_address != null ? [0] : []

    content {
      bridge      = "vmbr0"
      model       = "virtio"
      mac_address = var.mac_address
      firewall    = true
    }
  }

  network_device {
    bridge   = var.vnet_id
    model    = "virtio"
    firewall = true
  }

  initialization {
    datastore_id = var.datastore_id

    # Kolejność bloków ip_config odpowiada kolejności kart sieciowych, więc ta
    # konfiguracja musi być pierwsza, jeśli karta publiczna w ogóle istnieje.
    # Brama 100.64.0.1 to standard OVH dla adresów dodatkowych (routed).
    dynamic "ip_config" {
      for_each = var.public_ip != null ? [0] : []

      content {
        ipv4 {
          address = "${var.public_ip}/32"
          gateway = "100.64.0.1"
        }
      }
    }

    ip_config {
      ipv4 {
        address = "${var.private_ip}/24"
        gateway = var.gateway
      }

      # Adres publiczny IPv6 z podprefiksu wydzielonego dla segmentu. Brama to
      # host, który routuje ruch dalej i odpowiada za prefiks przez proxy NDP.
      dynamic "ipv6" {
        for_each = var.public_ipv6 != null ? [0] : []

        content {
          address = var.public_ipv6
          gateway = var.ipv6_gateway
        }
      }
    }

    dns {
      servers = ["1.1.1.1", "8.8.8.8"]
    }

    user_data_file_id = var.cloud_init_file_id
  }

  lifecycle {
    ignore_changes = [
      # Nazwa snippetu zawiera hash treści, więc każda zmiana cloud-inita chciałaby
      # odtworzyć VM-kę. Konfiguracja bieżąca należy do Ansible, nie do cloud-inita.
      initialization[0].user_data_file_id,
    ]
  }
}

# Domyślnie zamknięte: wszystko przychodzące DROP, przepuszczone wyłącznie to,
# co jawnie opisują grupy bezpieczeństwa. Pierwsza z trzech warstw
# (hypervisor -> UFW w gościu -> fail2ban).
resource "proxmox_virtual_environment_firewall_options" "this" {
  node_name = proxmox_virtual_environment_vm.this.node_name
  vm_id     = proxmox_virtual_environment_vm.this.vm_id

  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

resource "proxmox_virtual_environment_firewall_rules" "this" {
  node_name = proxmox_virtual_environment_vm.this.node_name
  vm_id     = proxmox_virtual_environment_vm.this.vm_id

  rule {
    security_group = "base"
  }

  dynamic "rule" {
    for_each = var.firewall_sgs

    content {
      security_group = rule.value
    }
  }
}
