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

  # Adresy maszyn potrzebne WARSTWIE hypervisora (reguły firewalla grup
  # bezpieczeństwa). Te same adresy są ustawiane w modułach usługowych -
  # zmiana w jednym miejscu wymaga zmiany w drugim. Adresy origin tuneli
  # zniknęły stąd - każdy tunel bierze IP z modułu VM-ki obok siebie.
  vm_ips = {
    cicd       = "10.0.${local.vnets.apps}.10"
    monitoring = "10.0.${local.vnets.apps}.20"
  }
}
