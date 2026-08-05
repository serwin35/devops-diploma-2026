# Bastion - jedyny punkt wejścia do infrastruktury i jedyna maszyna widoczna
# z internetu. Dostaje dodatkowy adres publiczny OVH przypięty wirtualnym MAC-iem,
# czyli drugą kartę sieciową wpiętą prosto w vmbr0 obok karty w segmencie dmz.
#
# Przez bastion przechodzi wszystko:
#   - SSH do pozostałych maszyn - grupa 'base' dopuszcza SSH wyłącznie z dmz
#   - ruch HTTP do paneli i aplikacji, tunelem Cloudflare (cloudflared łączy się
#     wychodząco, więc od strony świata nie ma tu otwartego portu 443)
module "bastion-1" {
  source = "../../../base/proxmox/vm"

  name      = "bastion-1"
  node_name = var.node_name
  vm_id     = 110
  pool_id   = var.pool_id
  tags      = ["bastion", "ssh", "edge"]

  # Maszyna nie robi nic poza terminowaniem tunelu i przekazywaniem połączeń,
  # więc dostaje absolutne minimum zasobów.
  cpu  = 1
  ram  = 1536
  disk = 20

  datastore_id       = var.datastore_id
  image_file_id      = var.image_file_id
  cloud_init_file_id = var.cloud_init_file_id

  vnet_id    = "dmz"
  private_ip = "10.0.110.10"
  gateway    = "10.0.110.1"

  # Dopóki adres nie zostanie zamówiony, oba pola są puste i maszyna stoi
  # wyłącznie w sieci prywatnej - moduł działa w obu wariantach.
  public_ip   = var.public_ip
  mac_address = var.mac_address

  # Adres publiczny IPv6 - darmowy, z bloku routowanego przez OVH.
  # Służy jako droga awaryjna, gdy tunel Cloudflare przestanie działać.
  public_ipv6  = var.ipv6_subnet == null ? null : "${cidrhost(var.ipv6_subnet.cidr, 16)}/80"
  ipv6_gateway = try(var.ipv6_subnet.gateway, null)

  firewall_sgs = (var.public_ip != null || var.ipv6_subnet != null) ? ["bastion", "metrics"] : ["metrics"]
}
