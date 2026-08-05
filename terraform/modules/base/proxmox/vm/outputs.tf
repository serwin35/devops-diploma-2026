output "name" {
  value       = proxmox_virtual_environment_vm.this.name
  description = "Nazwa VM-ki"
}

output "vm_id" {
  value       = proxmox_virtual_environment_vm.this.vm_id
  description = "Numer VM-ki"
}

output "private_ip" {
  value       = var.private_ip
  description = "Adres w sieci prywatnej"
}

output "tags" {
  value       = proxmox_virtual_environment_vm.this.tags
  description = "Tagi - grupy dla inventory Ansible"
}
