# Środowisko dev: pojedyncza maszyna z całym stackiem w Docker Compose
# (nginx + PHP-FPM + Postgres + Redis + Horizon). Własna baza w compose, bo dev
# nie ma prawa dotykać bazy produkcyjnej.
#
# To środowisko dowodzi kryterium "Docker: obrazy, kontenery, sieci, wolumeny" -
# w k3s te cztery rzeczy znikają za abstrakcjami Kubernetesa.
module "wolffire-dev-app-1" {
  source = "../../../../base/proxmox/vm"

  name      = "wolffire-dev-app-1"
  node_name = var.node_name
  vm_id     = 122
  pool_id   = var.pool_id
  tags      = ["app", "dev", "docker", "laravel"]

  cpu  = 3
  ram  = 2560
  disk = 40

  datastore_id       = var.datastore_id
  image_file_id      = var.image_file_id
  cloud_init_file_id = var.cloud_init_file_id

  vnet_id      = "apps"
  private_ip   = "10.0.120.30"
  gateway      = "10.0.120.1"
  firewall_sgs = ["http", "metrics"]
}
