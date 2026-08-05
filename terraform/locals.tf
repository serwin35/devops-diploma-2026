locals {
  # Segmenty sieciowe SDN. Liczba przypisana segmentowi jest trzecim oktetem jego
  # podsieci, dzięki czemu adresacja wynika z jednej wartości i nie da się jej rozjechać.
  # W strefie Simple nie jest tagiem VLAN - mosty są izolowane bez tagowania.
  vnets = {
    dmz  = 110 # bastion - jedyny punkt wejścia, tunel Cloudflare
    apps = 120 # CI/CD, monitoring, środowisko dev
    k3s  = 130 # węzły klastra k3s (prod aplikacji)
    dbs  = 140 # Postgres + Redis dla proda
  }

  node_name = keys(var.proxmox_node_names)[0]

  # Adresy maszyn, do których kieruje ruch tunel Cloudflare i które odpytuje
  # Prometheus. Wyprowadzone z numerów segmentów, żeby nie powtarzać ich
  # w kilku miejscach. Te same adresy są ustawiane w modułach usługowych -
  # zmiana w jednym miejscu wymaga zmiany w drugim.
  vm_ips = {
    bastion    = "10.0.${local.vnets.dmz}.10"
    cicd       = "10.0.${local.vnets.apps}.10"
    monitoring = "10.0.${local.vnets.apps}.20"
    dev        = "10.0.${local.vnets.apps}.30"
    prod       = "10.0.${local.vnets.k3s}.10"
    db         = "10.0.${local.vnets.dbs}.10"
  }
}
