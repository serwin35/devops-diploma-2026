# Prometheus, Grafana, Alertmanager i Loki stoją poza klastrem k3s celowo:
# monitoring, który pada razem z monitorowaną infrastrukturą, nie zaalarmuje
# o jej padnięciu. Sam software instaluje Ansible - tutaj powstaje tylko maszyna.
module "monitoring-1" {
  source = "../../../base/proxmox/vm"

  name      = "monitoring-1"
  node_name = var.node_name
  vm_id     = 121
  pool_id   = var.pool_id
  tags      = ["observability", "docker"]

  cpu  = 3
  ram  = 5120
  disk = 60

  datastore_id       = var.datastore_id
  image_file_id      = var.image_file_id
  cloud_init_file_id = var.cloud_init_file_id

  vnet_id      = "apps"
  private_ip   = "10.0.120.20"
  gateway      = "10.0.120.1"
  firewall_sgs = ["http", "metrics"]
}
