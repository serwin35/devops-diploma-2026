# Instalator OVH zostawia pool ZFS niezarejestrowany w Proxmoxie - widoczny jest
# tylko katalog "local" na /var/lib/vz. Bez tego dyski VM-ek powstawałyby jako
# pliki qcow2 zamiast ZVOL-i, czyli bez thin provisioningu i bez snapshotów.
resource "proxmox_virtual_environment_storage_zfspool" "vmdata" {
  id       = "vmdata"
  zfs_pool = var.zfs_pool
  nodes    = [var.node_name]
  content  = ["images", "rootdir"]
}

# Osobny katalog na artefakty Terraforma (obraz cloud-image + snippety cloud-init).
# "local" w domyślnej konfiguracji nie ma włączonej treści "snippets", a provider
# nie potrafi modyfikować istniejącego storage'u - więc zakładamy własny.
resource "proxmox_virtual_environment_storage_directory" "tfdata" {
  id      = "tfdata"
  path    = "/var/lib/vz/tf"
  nodes   = [var.node_name]
  content = ["snippets", "iso"]
}
