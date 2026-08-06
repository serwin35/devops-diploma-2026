.DEFAULT_GOAL := help
.PHONY: help secrets secrets-app bootstrap-aws bootstrap-host tf-plan tf-apply ansible-apply ansible-check status up fmt validate aws host infra plan configure check

# SOPS na macOS szuka klucza w ~/Library/Application Support/sops/age/, a na Linuksie
# w ~/.config/sops/age/. Wskazujemy ścieżkę XDG jawnie, żeby to samo repozytorium
# działało na laptopie i na agencie Jenkinsa bez rozjazdu.
export SOPS_AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt

SOPS_ENV := sops exec-env secrets.sops.yaml
TF       := terraform -chdir=terraform

# API Proxmoxa nie jest wystawione na internet - Terraform dochodzi do niego
# tunelem SSH. ControlPersist utrzymuje połączenie między wywołaniami.
PVE_TUNNEL := ssh -F ansible/ssh_config -O check wf-proxmox-1 2>/dev/null || \
	ssh -F ansible/ssh_config -fN -L 18006:localhost:8006 wf-proxmox-1

help: ## Lista dostępnych celów
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

bootstrap-aws: ## Krok zerowy AWS: buckety S3 i tożsamości IAM (stan lokalny, uruchamiany raz)
	$(SOPS_ENV) 'terraform -chdir=terraform/bootstrap init && terraform -chdir=terraform/bootstrap apply'
	@echo
	@echo "Klucze do przeniesienia przez 'make secrets':"
	@terraform -chdir=terraform/bootstrap output -json credentials

secrets: ## Edycja poświadczeń dostawców (Proxmox, Cloudflare, AWS)
	sops secrets.sops.yaml

secrets-app: ## Edycja sekretów wnętrza infrastruktury (hasła baz, Grafany, Jenkinsa...)
	sops ansible/group_vars/all/secrets.sops.yml

# Ansible odpalamy z jego katalogu: tylko wtedy znajduje ansible.cfg i tylko wtedy
# względne ścieżki do kluczy w ssh_config (../keys/...) wskazują na właściwe pliki.
bootstrap-host: ## Krok zerowy: hardening hosta Proxmoxa (root:22, jednorazowo po instalacji OVH)
	cd ansible && ansible-playbook bootstrap-host.yml

tf-plan: ## Terraform: podgląd zmian w infrastrukturze (nic nie zmienia)
	@$(PVE_TUNNEL)
	$(SOPS_ENV) '$(TF) plan'

tf-apply: ## Terraform: zastosowanie zmian (sieć SDN, storage, firewall, maszyny)
	@$(PVE_TUNNEL)
	$(SOPS_ENV) '$(TF) apply'

# LIMIT i TAGS zawężają zakres obu celów poniżej, np.:
#   make configure LIMIT=worker-1               # jedna maszyna, wszystkie role
#   make configure LIMIT=monitoring-1 TAGS=monitoring
#   make check LIMIT=k3s-server-1               # na sucho, jeden host
# LIMIT przyjmuje nazwy z inventory (monitoring-1), nie aliasy SSH (wf-...).
ANSIBLE_ARGS = $(if $(LIMIT),--limit $(LIMIT)) $(if $(TAGS),--tags $(TAGS))

ansible-apply: ## Ansible: zastosowanie playbooka (zawężanie: LIMIT=host TAGS=rola)
	$(SOPS_ENV) 'cd ansible && ansible-playbook playbook.yml $(ANSIBLE_ARGS)'

ansible-check: ## Ansible na sucho, z diffem (zawężanie: LIMIT=host TAGS=rola)
	$(SOPS_ENV) 'cd ansible && ansible-playbook playbook.yml --check --diff $(ANSIBLE_ARGS)'

# Jeden rzut oka na zdrowie całości: węzły i pody produkcji, kontenery dev,
# odpowiedzi HTTP obu środowisk. Wyłącznie odczyt.
status: ## Szybki przegląd zdrowia: klaster, kontenery, odpowiedzi HTTP
	@echo "== k3s: wezly =="
	@ssh -F ansible/ssh_config wf-k3s-server-1 'sudo k3s kubectl get nodes' 2>/dev/null
	@echo "\n== k3s: pody aplikacji =="
	@ssh -F ansible/ssh_config wf-k3s-server-1 'sudo k3s kubectl get pods -n wolffire' 2>/dev/null
	@echo "\n== dev: kontenery =="
	@ssh -F ansible/ssh_config wf-wolffire-dev-app-1 'sudo docker compose -f /opt/wolffire/compose.yml ps --format "table {{.Name}}\t{{.Status}}"' 2>/dev/null
	@echo "\n== HTTP =="
	@printf "prod  https://wolffire.dev      -> " ; curl -s -o /dev/null -w "%{http_code}\n" -L --max-time 10 https://wolffire.dev
	@printf "dev   https://dev.wolffire.dev  -> " ; curl -s -o /dev/null -w "%{http_code}\n" -L --max-time 10 https://dev.wolffire.dev

up: tf-apply ansible-apply ## Pełne wdrożenie od zera (Terraform, potem Ansible)

fmt: ## Formatowanie
	$(TF) fmt -recursive

validate: ## Walidacja składni
	$(TF) validate
	ansible-lint ansible/ || true

# Testy dymne infrastruktury. Wyłącznie odczyt: terraform w trybie `plan`,
# ansible w trybie `--check`, reszta to zapytania HTTP i `kubectl get`.
# Skrypt sam wchodzi do korzenia repozytorium, więc działa z dowolnego katalogu.
#
#   make test-infra                      # pełny przebieg
#   SMOKE_EXPECT_APP=1 make test-infra   # wymagaj działającej aplikacji na dev
#   SMOKE_FULL=1 make test-infra         # dodaj test idempotentności Ansible
.PHONY: test-infra
test-infra: ## Testy dymne infrastruktury (tylko odczyt, nic nie zmienia)
	@./scripts/smoke-test.sh

# Stare nazwy celów - zachowane jako aliasy, żeby nic nie zaskoczyło ręki
# przyzwyczajonej do poprzednich komend. Nowe nazwy mówią wprost, które
# narzędzie i który tryb (plan/apply) uruchamiają.
aws: bootstrap-aws
host: bootstrap-host
plan: tf-plan
infra: tf-apply
configure: ansible-apply
check: ansible-check
