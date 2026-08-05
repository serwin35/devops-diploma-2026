# Środowisko prod: klaster k3s na warstwę bezstanową aplikacji + osobna maszyna
# na dane. Postgres i Redis stoją POZA klastrem świadomie - stateful workload na
# local-path-provisionerze przy jednym fizycznym hoście to proszenie się o kłopoty.
#
# Trzy węzły zamiast jednego, żeby dało się pokazać `kubectl drain` i przełożenie
# podów - to różnica między "poprawnym" a "dobrym" wykonaniem kryterium Kubernetes.

locals {
  k3s_agents = {
    "k3s-agent-1" = { vm_id = 131, host = 11 }
    "k3s-agent-2" = { vm_id = 132, host = 12 }
  }
}

module "k3s-server-1" {
  source = "../../../../base/proxmox/vm"

  name      = "k3s-server-1"
  node_name = var.node_name
  vm_id     = 130
  pool_id   = var.pool_id
  tags      = ["k3s", "k3s_server", "prod"]

  cpu  = 2
  ram  = 3072
  disk = 40

  datastore_id       = var.datastore_id
  image_file_id      = var.image_file_id
  cloud_init_file_id = var.cloud_init_file_id

  vnet_id    = "k3s"
  private_ip = "10.0.130.10"
  gateway    = "10.0.130.1"
  # http: przez ten węzeł wchodzi Traefik, czyli tunel Cloudflare do aplikacji.
  firewall_sgs = ["http", "metrics", "k3s-api", "k3s-internal"]
}

module "k3s-agent" {
  source   = "../../../../base/proxmox/vm"
  for_each = local.k3s_agents

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  pool_id   = var.pool_id
  tags      = ["k3s", "k3s_agent", "prod"]

  cpu  = 2
  ram  = 2560
  disk = 40

  datastore_id       = var.datastore_id
  image_file_id      = var.image_file_id
  cloud_init_file_id = var.cloud_init_file_id

  vnet_id      = "k3s"
  private_ip   = "10.0.130.${each.value.host}"
  gateway      = "10.0.130.1"
  firewall_sgs = ["metrics", "k3s-internal"]
}

module "wolffire-prod-db-1" {
  source = "../../../../base/proxmox/vm"

  name      = "wolffire-prod-db-1"
  node_name = var.node_name
  vm_id     = 140
  pool_id   = var.pool_id
  tags      = ["db", "postgres", "redis", "prod"]

  cpu  = 2
  ram  = 3072
  disk = 50

  datastore_id       = var.datastore_id
  image_file_id      = var.image_file_id
  cloud_init_file_id = var.cloud_init_file_id

  vnet_id      = "dbs"
  private_ip   = "10.0.140.10"
  gateway      = "10.0.140.1"
  firewall_sgs = ["metrics", "prod-postgres", "prod-redis"]
}
