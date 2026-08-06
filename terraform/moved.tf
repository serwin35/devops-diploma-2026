# Tunele przeniosły się z roota do katalogów usługowych - każda maszyna trzyma
# swój tunel przy sobie, tak jak prod trzyma swój storage S3. Bloki mówią
# Terraformowi, że to ten sam obiekt pod nowym adresem - bez nich apply
# zburzyłby i postawił tunele od nowa, unieważniając tokeny cloudflared.
#
# Do usunięcia po jednym apply (projekt ma jeden stan).

moved {
  from = module.cloudflare_proxmox
  to   = module.proxmox_bootstrap.module.tunnel
}

moved {
  from = module.cloudflare_cicd
  to   = module.cicd.module.tunnel
}

moved {
  from = module.cloudflare_monitoring
  to   = module.observability.module.tunnel
}

moved {
  from = module.cloudflare_dev
  to   = module.wolffire_dev.module.tunnel
}

moved {
  from = module.cloudflare_prod
  to   = module.wolffire_prod.module.tunnel
}
