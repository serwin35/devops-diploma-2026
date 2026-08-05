# Maszyna CI/CD obsługuje dwa niezależne narzędzia:
#
#   - self-hosted runner GitHub Actions - buduje i wdraża aplikację. Musi stać
#     wewnątrz sieci, bo runnery hostowane przez GitHuba nie mają jak dosięgnąć
#     maszyn bez publicznych adresów.
#   - Jenkins - kopie zapasowe zasobów Proxmoxa do S3 i zadania cykliczne.
#     Konfigurowany w całości przez JCasC, agenty jako efemeryczne kontenery.
module "cicd-1" {
  source = "../../../base/proxmox/vm"

  name      = "cicd-1"
  node_name = var.node_name
  vm_id     = 120
  pool_id   = var.pool_id
  tags      = ["cicd", "docker"]

  cpu  = 3
  ram  = 5120
  disk = 60

  datastore_id       = var.datastore_id
  image_file_id      = var.image_file_id
  cloud_init_file_id = var.cloud_init_file_id

  vnet_id      = "apps"
  private_ip   = "10.0.120.10"
  gateway      = "10.0.120.1"
  firewall_sgs = ["http", "metrics"]
}
