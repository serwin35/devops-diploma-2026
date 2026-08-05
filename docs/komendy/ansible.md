# Ansible - komendy

Uruchamiaj z katalogu `ansible/` - tylko stąd `ansible.cfg` znajduje
`inventory.yml`, `roles/` i `ssh_config` po ścieżkach względnych.

> Wersja: ansible-core (patrz `ansible/requirements.yml` dla kolekcji),
> 9 hostów w inventory, 12 ról. **Zweryfikowano na żywo** 2026-08-05:
> `ansible all -m ping` (9/9 `pong`), `--check --diff` na `monitoring-1`
> (`ok=78 changed=0 failed=0`).

---

## Gotowość (bez sekretów)

```bash
cd ansible
ansible all -m ping                               # czy wszystko odpowiada po SSH
ansible-playbook playbook.yml --syntax-check       # tylko parsowanie YAML
ansible-playbook playbook.yml --list-hosts         # jakie hosty obejmie przebieg
ansible-inventory --graph                          # struktura grup
```

`ansible all -m ping` nie potrzebuje sekretów SOPS - działa nawet bez
`SOPS_AGE_KEY_FILE`. Dobre jako pierwszy test po zmianach w `ssh_config` albo
`inventory.yml`.

## Pełny playbook

```bash
cd ansible
sops exec-env ../secrets.sops.yaml 'ansible-playbook playbook.yml'

# albo z korzenia repo
make configure
```

**Playbook wymaga `sops exec-env`, nawet w `--check`.** Rola `cloudflared`
czyta token tunelu z outputu Terraforma w S3 (`cloud.terraform.terraform_output`)
- bez poświadczeń AWS w środowisku task pada na
`Error: No valid credential sources found`, zanim dojdzie do reszty ról.

## Uruchomienia wybiórcze

```bash
cd ansible
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1'

sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --tags docker'

sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --check --diff'
```

| Flaga | Co robi | Kiedy użyć |
|---|---|---|
| `--limit <host\|grupa>` | Ogranicza przebieg do wskazanych hostów | Test zmiany na jednej maszynie zamiast całej floty |
| `--tags <tag>` | Uruchamia tylko zadania z danym tagiem (patrz `tags:` w rolach) | Szybka iteracja nad jedną rolą, np. `--tags cloudflared` |
| `--check` | Tryb suchy - nic nie zapisuje na dysku | Test idempotentności przed obroną |
| `--diff` | Pokazuje różnicę treści plików szablonowych | Razem z `--check` - widać *co* by się zmieniło, nie tylko *czy* |

`--check --diff` na gotowej infrastrukturze powinno dać `changed=0 failed=0`.
Zadania oznaczone `check_mode: false` w rolach (np. czekanie na gotowość usługi)
i tak się wykonują - to świadomy wyjątek, bo to czysty odczyt, a bez niego
`until`/`register` nie miałyby na czym pracować i przebieg by się wywalił.

## Ad hoc

```bash
cd ansible
ansible monitoring-1 -m shell -a 'docker ps'
ansible all -m shell -a 'systemctl is-active docker prometheus-node-exporter fail2ban' -o
ansible all -m setup -a 'filter=ansible_memtotal_mb'
```

Moduł `shell`/`command` do jednorazowego sprawdzenia stanu; do zmiany
konfiguracji zawsze idzie rola, nigdy ad hoc - inaczej zmiana zniknie przy
następnym `ansible-playbook`.

## Inventory

```bash
cd ansible
ansible-inventory --graph              # drzewo grup
ansible-inventory --list               # pełny JSON z hostvars
ansible-inventory --host monitoring-1  # zmienne jednego hosta
```

Grupy w tym repo (`ansible/inventory.yml`): `proxmox`, `bastion`, `cicd`,
`observability`, `k3s_server`, `k3s_agent` (razem `k3s`), `postgres`, `redis`,
`docker`, `dev`, `prod`. Jeden host bywa w kilku grupach naraz -
`wolffire-prod-db-1` jest jednocześnie w `postgres`, `redis` i `prod`.

## Wektory debugowania

```bash
cd ansible
sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 -vvv'   # pełny log modułów

ANSIBLE_STDOUT_CALLBACK=yaml sops exec-env ../secrets.sops.yaml \
  'ansible-playbook playbook.yml --limit monitoring-1 --check --diff'
```

| Poziom | Co pokazuje |
|---|---|
| (bez flagi) | Nazwy zadań i wynik (`ok`/`changed`/`failed`) |
| `-v` | Zwrotka modułu (`msg`, zmienione pliki) |
| `-vvv` | Połączenie SSH, przekazywane argumenty modułu, sposób wykonania |
| `-vvvv` | Ładowanie wtyczek połączenia - ostatnia deska ratunku |

`ANSIBLE_STDOUT_CALLBACK=yaml` zamienia gęsty JSON w czytelny YAML - dużo
łatwiej wychwycić różnicę w `--diff` niż w domyślnym formacie.

## Częste problemy

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `No valid credential sources found` w trakcie playbooka | Playbook uruchomiony bez `sops exec-env` (rola `cloudflared` potrzebuje AWS) | Owiń w `sops exec-env ../secrets.sops.yaml '...'` |
| `UNREACHABLE! ... Permission denied (publickey)` | Zły klucz albo maszyna nie ma jeszcze wsianych kluczy z cloud-init | Sprawdź `ansible/ssh_config` -> `IdentityFile`; `ssh -F ansible/ssh_config wf-<host> -v` |
| `changed` przy każdym przebiegu na tym samym zadaniu | Zadanie nie ma poprawnego `changed_when` (np. polecenie zawsze zwraca sukces) | Patrz komentarze w rolach `wolffire`/`wolffire_prod` - wzorzec `changed_when` liczony z wejść, nie z tekstu wyjścia |
| `ansible-lint` zgłasza błędy w rolach z `CLAUDE.md` | To pliki metadanych Claude, nie YAML - lint i tak je pomija po rozszerzeniu | Ignoruj, chyba że błąd wskazuje realny plik `.yml` |
| Task wisi na `until`/`retries` | Usługa faktycznie nie wstała (nie tylko wolno startuje) | Sprawdź bezpośrednio na maszynie: `systemctl status <usługa>`, `journalctl -u <usługa> -n 50` |
