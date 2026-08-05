Terraform - dowody
==================

- [X] Pliki
- [X] Reużywalność

Infrastruktura (8 maszyn wirtualnych, sieć SDN, firewall hypervisora, DNS
i tunele Cloudflare, buckety S3) jest w całości opisana w Terraformie. Stan
leży zdalnie w S3 (`terraform-states-wf`, zob. [state-s3.md](state-s3.md)).

## Dowody zebrane na żywo (2026-08-05)

```
$ sops exec-env secrets.sops.yaml 'terraform -chdir=terraform state list' | wc -l
125
```

Plan po `apply` (test drugiego rodzaju idempotentności - nie „No changes”,
tylko realny dryf wykryty na żywo):

```
$ sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan -no-color'
...
  # module.cloudflare_dns.module.settings.cloudflare_zone_setting.always_use_https will be created
  # module.cloudflare_dns.module.settings.cloudflare_zone_setting.min_tls_version will be created
  # module.cloudflare_dns.module.settings.cloudflare_zone_setting.security_header will be created
  # module.cloudflare_dns.module.settings.cloudflare_zone_setting.ssl will be created
  # module.cloudflare_dns.module.settings.cloudflare_zone_setting.tls_1_3 will be created

Plan: 5 to add, 0 to change, 0 to destroy.
```

Reużywalność modułu maszyny - jeden plik (`modules/base/proxmox/vm`), siedem
miejsc wywołania, osiem maszyn (jedno wywołanie używa `for_each` na dwóch
agentach k3s):

```
$ grep -rn 'source = "..*base/proxmox/vm"' terraform/modules/services/
terraform/modules/services/proxmox/wolffire/prod/main.tf:16:  source = "../../../../base/proxmox/vm"   # k3s-server-1
terraform/modules/services/proxmox/wolffire/prod/main.tf:40:  source = "../../../../base/proxmox/vm"   # k3s-agent (for_each: agent-1, agent-2)
terraform/modules/services/proxmox/wolffire/prod/main.tf:64:  source = "../../../../base/proxmox/vm"   # wolffire-prod-db-1
terraform/modules/services/proxmox/wolffire/dev/main.tf:8:   source = "../../../../base/proxmox/vm"    # wolffire-dev-app-1
terraform/modules/services/proxmox/bastion/main.tf:10:       source = "../../../base/proxmox/vm"       # bastion-1
terraform/modules/services/proxmox/observability/main.tf:5:  source = "../../../base/proxmox/vm"       # monitoring-1
terraform/modules/services/proxmox/cicd/main.tf:9:           source = "../../../base/proxmox/vm"       # cicd-1
```

`qm list` na hypervisorze potwierdza 8 działających maszyn (pełne wyjście w
[vm.md](vm.md)).

## Jak to jest zrobione

| Warstwa | Plik/katalog |
|---|---|
| Root modułu | [terraform/main.tf](../../terraform/main.tf), [locals.tf](../../terraform/locals.tf) - segmenty SDN i adresy IP jako jedno źródło prawdy |
| Klocek maszyny (reużywalny) | [terraform/modules/base/proxmox/vm/](../../terraform/modules/base/proxmox/vm/) |
| Klocki Cloudflare (reużywalne) | [terraform/modules/base/cloudflare/tunnel/](../../terraform/modules/base/cloudflare/tunnel/), [zero_trust_policy/](../../terraform/modules/base/cloudflare/zero_trust_policy/), [zone_settings/](../../terraform/modules/base/cloudflare/zone_settings/) |
| Złożenia usług | [terraform/modules/services/proxmox/{bastion,cicd,observability,wolffire/dev,wolffire/prod}/](../../terraform/modules/services/proxmox/) |
| Bootstrap SDN/firewall/storage | [terraform/modules/services/proxmox/bootstrap/](../../terraform/modules/services/proxmox/bootstrap/) |
| Backend stanu | [terraform/providers.tf](../../terraform/providers.tf) - `backend "s3"`, `use_lockfile = true` |
| Root oddzielny (chicken-egg) | [terraform/bootstrap/](../../terraform/bootstrap/) - bucket S3 + IAM, stan **lokalny**, uruchamiany raz (`make aws`) |

Reużywalność w praktyce: `modules/base/proxmox/vm` przyjmuje parametry (CPU,
RAM, dysk, sieć, cloud-init, firewall) i jest wywoływany 7×, dając 8 maszyn.
Każde złożenie usługowe (`bastion`, `cicd`, `observability`, `wolffire/dev`,
`wolffire/prod`) doczepia do maszyny właściwe grupy firewalla i (opcjonalnie)
tunel Cloudflare przez te same reużywalne klocki bazowe.

## Świadome decyzje / ograniczenia

- **Terraform kończy pracę, gdy istnieje maszyna z adresem IP i regułami
  firewalla** - reszta (Docker, k3s, Postgres, Jenkins…) należy do Ansible.
  Uzasadnienie: [ARCHITECTURE.md §5](../ARCHITECTURE.md#5-podział-terraform--ansible).
- **`terraform/bootstrap/` ma stan lokalny, nie S3** - to on tworzy bucket na
  stan całej reszty, więc nie może sam w nim mieszkać (problem kury i jajka).
  Plik `terraform.tfstate` w tym katalogu jest w `.gitignore`, bo zawiera
  klucze IAM jawnym tekstem.
- **Plan pokazuje 5 zasobów do dodania** (ustawienia strefy Cloudflare: SSL,
  TLS 1.3, min. wersja TLS, `always_use_https`, nagłówek bezpieczeństwa) - to
  realny, nieukryty dryf zastany podczas zbierania dowodów, nie efekt
  manipulacji. Wynika z kolejności prac nad domeną (zob.
  [domena-ssl.md](domena-ssl.md)); `apply` naprawia to jedną komendą.
- **`random_password` administratora Proxmoxa trafia do stanu jawnym
  tekstem** - dlatego bucket ze stanem ma szyfrowanie i wąskie IAM, opisane w
  [state-s3.md](state-s3.md).

## Zrzuty ekranu

![Plan Terraform pokazujący 0 zmian w warstwie maszyn/sieci i wykryty dryf ustawień strefy Cloudflare](../zrzuty/terraform-plan.png)

Related evidence: [vm.md](vm.md), [firewall.md](firewall.md), [state-s3.md](state-s3.md).
