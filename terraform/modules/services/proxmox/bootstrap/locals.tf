locals {
  cloud_init = templatefile("${path.module}/cloud-init.yml.tftpl", {
    ansible_user    = var.ansible_user
    ssh_public_keys = var.ssh_public_keys
    ssh_port        = var.ssh_port
  })

  # Aliasy adresowe: jeden na segment + zbiorczy "internal" na całą przestrzeń 10.0.0.0/16
  # (obejmuje także bramy vnetów, czyli adresy samego hosta - to nimi chodzi Ansible i cloudflared).
  aliases = merge(
    { for name, tag in var.vnets : name => "10.0.${tag}.0/24" },
    {
      internal = "10.0.0.0/16"
      cicd     = var.cicd_ip
      # Bez /32: Proxmox przechowuje adres pojedynczego hosta bez maski i przy
      # każdym odświeżeniu zwracałby inną wartość niż zapisana - konfiguracja
      # przestałaby być idempotentna.
      monitoring = var.monitoring_ip
    }
  )

  # Grupy bezpieczeństwa firewalla Proxmoxa. Polityka wejściowa to DROP, więc
  # to jedyne ścieżki, którymi cokolwiek wchodzi do maszyny.
  security_groups = {
    # Doczepiana do każdej VM-ki bez wyjątku. SSH przyjmowane wyłącznie z bastionu
    # oraz z samego hypervisora - ten drugi wyjątek jest potrzebny na etapie
    # provisioningu, zanim bastion w ogóle istnieje.
    base = [
      {
        name     = "ICMP wewnatrz infrastruktury"
        protocol = "icmp"
        source   = "internal"
      },
      {
        # proto icmp w PVE oznacza WYŁĄCZNIE IPv4. NDP (odpowiednik ARP w IPv6)
        # jest ICMPv6 - bez tej reguły sąsiedztwo v6 między hostem a maszyną
        # nie powstaje i cały ruch IPv6 jest martwy mimo poprawnej adresacji.
        name     = "ICMPv6 - NDP wewnatrz infrastruktury"
        protocol = "ipv6-icmp"
      },
      {
        name     = "SSH z bastionu"
        protocol = "tcp"
        port     = var.ssh_port
        source   = "dmz"
      },
      {
        name     = "SSH z hypervisora (bootstrap)"
        protocol = "tcp"
        port     = var.ssh_port
        source   = "+hypervisor"
      },
    ]

    # Ruch HTTP przychodzi wyłącznie z bastionu - to on terminuje tunel Cloudflare
    # i przekazuje połączenia do usług wewnętrznych.
    http = [
      {
        name     = "HTTP z bastionu"
        protocol = "tcp"
        port     = 80
        source   = "dmz"
      },
      {
        name     = "HTTPS z bastionu"
        protocol = "tcp"
        port     = 443
        source   = "dmz"
      },
      # Zakres musi obejmować porty paneli monitoringu. Wcześniejsza wersja
      # kończyła się na 9000, przez co Prometheus (9090) i Alertmanager (9093)
      # były odrzucane przez firewall hypervisora - mimo poprawnej reguły UFW
      # w maszynie. Objawiało się to błędem 502 z Cloudflare.
      {
        name     = "Porty aplikacyjne i paneli z bastionu"
        protocol = "tcp"
        port     = "3000:9999"
        source   = "dmz"
      },
      {
        # Alloy na każdej maszynie wysyła logi do Loki. Bez tej reguły firewall
        # hypervisora ubija push z segmentów innych niż dmz i Loki widzi tylko
        # maszyny lokalne - objaw: 2 z 9 hostów w etykietach.
        name     = "Loki push z calej infrastruktury"
        protocol = "tcp"
        port     = 3100
        source   = "internal"
      },
      {
        # Prometheus odpytuje /metrics aplikacji przez port HTTP.
        name     = "HTTP dla scrape z monitoringu"
        protocol = "tcp"
        port     = 80
        source   = "monitoring"
      },
    ]

    # Eksportery odpytuje wyłącznie Prometheus - nie cały segment apps.
    metrics = [
      {
        name     = "node_exporter"
        protocol = "tcp"
        port     = 9100
        source   = "monitoring"
      },
      {
        # 8081, nie 8080 - na maszynie CI/CD port 8080 należy do Jenkinsa.
        name     = "cAdvisor"
        protocol = "tcp"
        port     = 8081
        source   = "monitoring"
      },
      {
        name     = "metryki demona Dockera"
        protocol = "tcp"
        port     = 9323
        source   = "monitoring"
      },
      {
        name     = "php-fpm exporter aplikacji"
        protocol = "tcp"
        port     = 9253
        source   = "monitoring"
      },
      {
        name     = "postgres_exporter"
        protocol = "tcp"
        port     = 9187
        source   = "monitoring"
      },
      {
        name     = "redis_exporter"
        protocol = "tcp"
        port     = 9121
        source   = "monitoring"
      },
    ]

    # Jedyna maszyna przyjmująca połączenia z internetu. Wpuszczamy wyłącznie SSH -
    # ruch HTTP i tak wchodzi tunelem, który cloudflared zestawia wychodząco,
    # więc port 443 od strony świata nie jest do niczego potrzebny.
    #
    # Ochrona: logowanie wyłącznie kluczem, niestandardowy port, fail2ban.
    bastion = [
      {
        name     = "SSH z internetu"
        protocol = "tcp"
        port     = var.ssh_port
      },
    ]

    k3s-api = [
      {
        name     = "API serwera k3s"
        protocol = "tcp"
        port     = 6443
        source   = "internal"
      },
    ]

    # Węzły klastra rozmawiają ze sobą po wielu portach (flannel VXLAN, kubelet,
    # metrics-server). Zamiast wyliczać je wszystkie, otwieramy segment k3s na siebie.
    k3s-internal = [
      {
        name   = "Ruch wewnatrz klastra k3s"
        source = "k3s"
      },
    ]

    prod-postgres = [
      {
        name     = "Postgres z klastra k3s"
        protocol = "tcp"
        port     = 5432
        source   = "k3s"
      },
      {
        # pg_dump w jobie backupowym Jenkinsa. Pojedynczy adres, nie cały
        # segment apps - dostęp do bazy dostaje tylko maszyna CI/CD.
        name     = "Postgres dla kopii zapasowych z CI/CD"
        protocol = "tcp"
        port     = 5432
        source   = "cicd"
      },
    ]

    prod-redis = [
      {
        name     = "Redis z klastra k3s"
        protocol = "tcp"
        port     = 6379
        source   = "k3s"
      },
    ]

    # Jedyna grupa opisująca ruch z internetu - i tylko z adresów administratora.
    # Docelowo, gdy stanie tunel, UI Proxmoxa znika stąd całkowicie.
    host-admin = [
      {
        name     = "SSH administratora"
        protocol = "tcp"
        port     = var.ssh_port
        source   = "+admins"
      },
      # UI Proxmoxa NIE jest już wystawione na internet - wchodzi się przez
      # tunel proxmox.wolffire.dev za Zero Trust Access. Reguła zostaje tylko
      # dla ruchu wewnętrznego (cloudflared na hoście i tak celuje w localhost,
      # ale konsola noVNC potrafi wracać przez adres publiczny hosta).
      {
        name     = "UI Proxmoxa z sieci wewnetrznej"
        protocol = "tcp"
        port     = 8006
        source   = "internal"
      },
      # ICMPv6 MUSI przechodzić. W IPv6 nie ma ARP - jego rolę pełni NDP, które
      # jest ICMPv6 (typy 133-136). Zablokowanie go odcina host od routera OVH
      # i rozbija całą adresację IPv6 wraz z proxy NDP dla maszyn.
      # RFC 4890 wprost odradza filtrowanie ICMPv6.
      {
        # Prometheus zbiera metryki także z samego hypervisora.
        name     = "node_exporter hypervisora"
        protocol = "tcp"
        port     = 9100
        source   = "monitoring"
      },
      {
        name     = "ICMPv6 - NDP i odkrywanie MTU"
        protocol = "ipv6-icmp"
      },
      {
        name     = "ICMP"
        protocol = "icmp"
      },
    ]
  }
}
