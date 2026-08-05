# Parametry testowanej infrastruktury - JEDYNE miejsce, które trzeba ruszyć,
# gdy zmieni się adresacja, port albo dojdzie maszyna.
#
# Wartości muszą odpowiadać:
#   ansible/inventory.yml            - lista maszyn i adresy prywatne
#   ansible/group_vars/all/main.yml  - strefa publiczna, adresy segmentow
#   terraform/locals.tf              - schemat adresacji 10.0.<vnet>.<host>
#   ansible/roles/monitoring/defaults, roles/postgres/defaults, roles/redis/defaults
#
# Plik jest włączany (`.`), nie uruchamiany.

# ── Maszyny ──────────────────────────────────────────────────────────────────
#
# Kolejność jak w inventory: brzeg, segment apps, k3s, bazy.
ALL_HOSTS="proxmox-1 bastion-1 cicd-1 monitoring-1 wolffire-dev-app-1 k3s-server-1 k3s-agent-1 k3s-agent-2 wolffire-prod-db-1"

# ── Brzeg sieci ──────────────────────────────────────────────────────────────
BASTION_PUBLIC_IP="51.83.139.3"
PROXMOX_PUBLIC_IP="57.128.192.26"
SSH_PORT="22022"

# ── Cloudflare ───────────────────────────────────────────────────────────────
PUBLIC_ZONE="wolffire.dev"
# Panele za Zero Trust Access. Każdy musi odpowiadać przekierowaniem na Access.
PROTECTED_PANELS="grafana prometheus alerts jenkins proxmox"

# ── Monitoring (segment apps) ────────────────────────────────────────────────
MONITORING_IP="10.0.120.20"
MONITORING_DIR="/opt/monitoring"
PROMETHEUS_PORT="9090"
ALERTMANAGER_PORT="9093"
GRAFANA_PORT="3000"
LOKI_PORT="3100"
# Alloy stoi na każdej maszynie, więc etykieta `host` w Loki powinna mieć tyle
# wartości, ile jest maszyn w inventory.
LOKI_MIN_HOSTS=8

# ── Bazy (segment dbs) ───────────────────────────────────────────────────────
DB_IP="10.0.140.10"
POSTGRES_PORT="5432"
REDIS_PORT="6379"
POSTGRES_EXPORTER_PORT="9187"
REDIS_EXPORTER_PORT="9121"

# ── k3s ──────────────────────────────────────────────────────────────────────
K3S_EXPECTED_NODES=3

# ── Ścieżki w repozytorium ───────────────────────────────────────────────────
#
# REPO_ROOT ustawia smoke-test.sh przed włączeniem tego pliku.
SSH_CONFIG="$REPO_ROOT/ansible/ssh_config"
ANSIBLE_SECRETS="$REPO_ROOT/ansible/group_vars/all/secrets.sops.yml"
TF_SECRETS="$REPO_ROOT/secrets.sops.yaml"

# ── Limity czasu ─────────────────────────────────────────────────────────────
#
# Każdy pojedynczy test ma twardy limit 10 s. Duża liczba wywołań SSH nie jest
# przez to problemem, bo połączenia są multipleksowane (lib/ssh.sh): pierwszy
# test na danej maszynie zestawia sesję, kolejne ją współdzielą.
TEST_TIMEOUT=10
# Terraform i Ansible to z natury długie operacje - mają własne, jawne budżety.
TF_TIMEOUT=420
ANSIBLE_TIMEOUT=1200
