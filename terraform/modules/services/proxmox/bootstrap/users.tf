resource "proxmox_virtual_environment_group" "this" {
  group_id = "admin"
  comment  = "All privileges group"

  lifecycle {
    ignore_changes = [
      acl
    ]
  }
}

resource "proxmox_virtual_environment_acl" "this" {
  group_id  = proxmox_virtual_environment_group.this.group_id
  role_id   = "Administrator"
  path      = "/"
  propagate = true
}

# Hasło początkowe generuje Terraform - nie jest nigdzie wpisywane ani przekazywane.
# Odczyt jednorazowo przez `terraform output -raw proxmox_initial_password`,
# potem do zmiany w panelu. Dzięki temu w tfvars nie ma żadnego sekretu.
resource "random_password" "initial" {
  length           = 24
  special          = true
  override_special = "!#$%&*+-=?_"
}

resource "proxmox_virtual_environment_user" "this" {
  for_each = var.users

  user_id  = "${each.value}@pve"
  password = random_password.initial.result

  groups = [
    proxmox_virtual_environment_group.this.group_id
  ]

  lifecycle {
    # Po zmianie hasła w panelu Terraform nie ma go cofać przy każdym apply.
    ignore_changes = [password]
  }
}
