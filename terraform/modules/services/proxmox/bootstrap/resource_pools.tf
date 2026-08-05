resource "proxmox_virtual_environment_pool" "this" {
  for_each = var.resource_pools
  pool_id  = each.value
}
