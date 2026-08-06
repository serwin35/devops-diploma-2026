# Warstwa hypervisora: storage ZFS, sieć SDN z NAT-em, cloud-init, firewall, pule.
# Musi istnieć, zanim powstanie pierwsza maszyna.
module "proxmox_bootstrap" {
  source = "./modules/services/proxmox/bootstrap"

  node_name       = local.node_name
  users           = var.proxmox_users
  resource_pools  = var.proxmox_resource_pools
  vnets           = local.vnets
  ssh_port        = var.ssh_port
  admin_ips       = var.admin_ips
  monitoring_ip   = local.vm_ips.monitoring
  cicd_ip         = local.vm_ips.cicd
  ssh_public_keys = var.ssh_public_keys
  ansible_user    = var.ansible_user

  # Publiczne IPv6 dla segmentu dmz - darmowa droga awaryjna do bastionu,
  # niezależna od tunelu Cloudflare i od adresu IPv4.
  ipv6_prefix = var.ipv6_prefix
  ipv6_vnets  = ["dmz"]
}

locals {
  # Wspólne wejście każdego modułu usługowego - żeby nie powtarzać go czterokrotnie.
  vm_defaults = {
    node_name          = local.node_name
    datastore_id       = module.proxmox_bootstrap.datastore_id
    image_file_id      = module.proxmox_bootstrap.image_file_id
    cloud_init_file_id = module.proxmox_bootstrap.cloud_init_file_id
  }
}

# Bastion powstaje jako pierwszy z maszyn - przez niego przechodzi ruch do reszty.
module "bastion" {
  source = "./modules/services/proxmox/bastion"

  node_name          = local.vm_defaults.node_name
  datastore_id       = local.vm_defaults.datastore_id
  image_file_id      = local.vm_defaults.image_file_id
  cloud_init_file_id = local.vm_defaults.cloud_init_file_id
  pool_id            = module.proxmox_bootstrap.pool_ids["internal"]

  public_ip   = var.bastion_public_ip
  mac_address = var.bastion_mac_address
  ipv6_subnet = try(module.proxmox_bootstrap.ipv6_subnets["dmz"], null)
}

module "cicd" {
  source = "./modules/services/proxmox/cicd"

  node_name          = local.vm_defaults.node_name
  datastore_id       = local.vm_defaults.datastore_id
  image_file_id      = local.vm_defaults.image_file_id
  cloud_init_file_id = local.vm_defaults.cloud_init_file_id
  pool_id            = module.proxmox_bootstrap.pool_ids["internal"]
}

module "observability" {
  source = "./modules/services/proxmox/observability"

  node_name          = local.vm_defaults.node_name
  datastore_id       = local.vm_defaults.datastore_id
  image_file_id      = local.vm_defaults.image_file_id
  cloud_init_file_id = local.vm_defaults.cloud_init_file_id
  pool_id            = module.proxmox_bootstrap.pool_ids["internal"]
}

module "wolffire_dev" {
  source = "./modules/services/proxmox/wolffire/dev"

  node_name          = local.vm_defaults.node_name
  datastore_id       = local.vm_defaults.datastore_id
  image_file_id      = local.vm_defaults.image_file_id
  cloud_init_file_id = local.vm_defaults.cloud_init_file_id
  pool_id            = module.proxmox_bootstrap.pool_ids["dev"]
}

module "wolffire_prod" {
  source = "./modules/services/proxmox/wolffire/prod"

  node_name          = local.vm_defaults.node_name
  datastore_id       = local.vm_defaults.datastore_id
  image_file_id      = local.vm_defaults.image_file_id
  cloud_init_file_id = local.vm_defaults.cloud_init_file_id
  pool_id            = module.proxmox_bootstrap.pool_ids["prod"]

  # Domena publiczna aplikacji - origin dopuszczony w CORS bucketa plików.
  zone = var.zone
}

# ── Cloudflare: tunele per maszyna ───────────────────────────────────────────
#
# Jeden tunel na MASZYNĘ, nie jeden na całą infrastrukturę. cloudflared działa
# na maszynie z usługą i celuje w localhost, więc:
#   - ruch nie przechodzi między segmentami,
#   - firewall nie potrzebuje reguł dla portów paneli,
#   - awaria jednej maszyny nie odcina paneli na pozostałych.
#
# Wersja z pojedynczym tunelem na bastionie wymagała trasy do wszystkich
# segmentów i szerokiego zakresu portów otwartego z dmz.

module "cloudflare_cicd" {
  source = "./modules/base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-cicd"
  origin_host    = local.vm_ips.cicd
  allowed_emails = var.access_emails

  services = {
    jenkins = { port = 8080 }
  }
}

module "cloudflare_monitoring" {
  source = "./modules/base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-monitoring"
  origin_host    = local.vm_ips.monitoring
  allowed_emails = var.access_emails

  services = {
    grafana    = { port = 3000 }
    prometheus = { port = 9090 }
    alerts     = { port = 9093 }
  }
}

# Jedyny tunel bez origin_host: cloudflared stoi na samym hypervisorze,
# więc celuje w domyślny localhost.
module "cloudflare_proxmox" {
  source = "./modules/base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-proxmox"
  allowed_emails = var.access_emails

  services = {
    proxmox = {
      port   = 8006
      scheme = "https"
      # Hypervisor ma certyfikat podpisany przez własne CA Proxmoxa.
      insecure_origin = true
    }
  }
}

module "cloudflare_prod" {
  source = "./modules/base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-prod"
  origin_host    = local.vm_ips.prod
  allowed_emails = var.access_emails

  services = {
    # Domena apex - produkcja. Publiczna, kontrola dostępu należy do aplikacji.
    prod = { port = 80, protected = false, apex = true }
  }

  # Rekordy domeny produkcyjnej niepochodzące z tunelu dopisuje się tutaj -
  # przy usłudze, do której należą. Przykład (weryfikacja Google Search
  # Console; name = null oznacza apex, czyli samą wolffire.dev):
  #
  #   extra_records = {
  #     google_site_verification = {
  #       type    = "TXT"
  #       content = "google-site-verification=<token>"
  #       comment = "Weryfikacja wlasnosci domeny w Google Search Console"
  #     }
  #   }
}

module "cloudflare_dev" {
  source = "./modules/base/cloudflare/tunnel"

  account_name   = var.cloudflare_account_name
  zone           = var.zone
  tunnel_name    = "wf-dev"
  origin_host    = local.vm_ips.dev
  allowed_emails = var.access_emails

  services = {
    # Środowisko deweloperskie jest publiczne - kontrola dostępu należy
    # do samej aplikacji, nie do warstwy sieciowej.
    dev = { port = 80, protected = false }
  }
}

# ── Cloudflare: strefa DNS ───────────────────────────────────────────────────
#
# Rekordy NIE pochodzące z tuneli: poczta (MX, SPF, DKIM, DMARC) i ustawienia
# strefy. Rekordy tunelowe tworzą moduły wyżej - ich treść to identyfikator
# tunelu, znany dopiero po apply, więc nie da się ich tu zadeklarować.
module "cloudflare_dns" {
  source = "./modules/services/cloudflare/dns"

  zone         = var.zone
  account_name = var.cloudflare_account_name

  # Domena NIE obsługuje poczty. Rekordy OVH (MX, SPF include:mx.ovh.com)
  # były pozostałością po poprzednim życiu domeny - żadna skrzynka na nich
  # nie działała. Zamiast po prostu je usunąć, strefa deklaruje jawnie
  # "brak poczty", co odbiera spamerom możliwość podszywania się pod domenę:
  #
  #   - null MX (RFC 7505): "0 ." mówi nadawcom, że domena nie przyjmuje
  #     listów - serwery przestają próbować zamiast czekać na timeouty,
  #   - SPF "v=spf1 -all": żaden serwer nie ma prawa wysyłać z tej domeny,
  #   - DMARC p=reject (niżej): list, który mimo to powstanie, ma być
  #     odrzucony, nie oznaczony.
  #
  # Alerty e-mail projektu wychodzą przez AWS SNS (nadawca AWS), więc nie
  # potrzebują żadnego z tych rekordów.
  dmarc_policy = "reject"

  records = {
    mx_null = {
      name     = null
      type     = "MX"
      content  = "."
      priority = 0
      comment  = "Null MX (RFC 7505) - domena nie przyjmuje poczty"
    }
    spf = {
      name    = null
      type    = "TXT"
      content = "v=spf1 -all"
      comment = "SPF - zaden serwer nie wysyla poczty z tej domeny"
    }
  }
}
