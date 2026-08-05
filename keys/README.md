# Klucze SSH

Do repozytorium trafiają **wyłącznie klucze publiczne** - prywatne są w `.gitignore`.

| Klucz | Używa | Dosięga |
|---|---|---|
| `terraform_ed25519` | Terraform (provider `bpg/proxmox`) | **tylko host Proxmoxa** - wgranie snippetów cloud-init i obrazu |
| `ansible_ed25519` | Ansible | host Proxmoxa + wszystkie maszyny wirtualne (przez ProxyJump) |
| `humans/*.pub` | ludzie | to samo, co Ansible - ręczne wejście na maszynę |

Rozdział tożsamości maszynowych nie jest kosmetyczny: Terraform nie ma po co
wchodzić na maszyny gości, więc jego klucz nie jest tam wsiewany.

## Logowanie ręcznie

Cloud-init wsiewa do użytkownika `ansible` na każdej maszynie **oba** klucze:
maszynowy i osobisty z `humans/`. Nie trzeba czekać na Ansible, żeby wejść -
i nie da się zablokować dostępu psując playbook.

```bash
ssh wf-proxmox-1              # host
ssh wf-k3s-server-1           # VM-ka, automatycznie przez ProxyJump wf-bastion-1
ssh mserwinowski@wf-bastion-1 # konto imienne - %r w ProxyJump przenosi je dalej
```

Działa z dowolnego katalogu dzięki wpisowi Include w ~/.ssh/config, który wciąga
`ansible/ssh_config` z całą topologią. Prefiks wf- jest konieczny, bo w innych
konfiguracjach istnieją hosty o nazwach `proxmox-1` i `bastion-1`. Nazwy hostów
mają również sufiks `-1` (`wf-bastion-1`, `wf-cicd-1`, `wf-k3s-agent-1`...) -
odpowiadają nazwom maszyn w Terraformie i inventory Ansible.

Docelowo rola `login` założy na maszynach imienne konta z `humans/` - wtedy
`ansible` zostanie wyłącznie kontem maszynowym. Do tego czasu jedno konto
obsługuje oba zastosowania.

## Brak passphrase

Oba klucze są bez hasła, bo używają ich procesy nieinteraktywne (`terraform apply`,
`ansible-playbook`, docelowo joby Jenkinsa). Ochrona opiera się na tym, że klucze
nigdy nie opuszczają stacji roboczej: nie ma ich w gicie, a na agenta CI trafiają
jako credential, nie jako plik w repozytorium.

## Odtworzenie od zera

```bash
ssh-keygen -t ed25519 -f keys/terraform_ed25519 -N "" -C "terraform@wolffire-diploma"
ssh-keygen -t ed25519 -f keys/ansible_ed25519   -N "" -C "ansible@wolffire-diploma"
chmod 600 keys/*_ed25519
```

Po wygenerowaniu nowej pary trzeba podmienić `ssh_public_keys` w `terraform/terraform.tfvars`
i przepuścić `make host`, który rozkłada klucze na hoście.

## Gdzie są używane

- `terraform/providers.tf` - blok `ssh { private_key = ... }` providera proxmox
- `ansible/ssh_config` - dyrektywa `IdentityFile`
- `terraform/terraform.tfvars` - `ssh_public_keys` wsiewane przez cloud-init do VM-ek
- `ansible/bootstrap-host.yml` - zakładanie użytkowników na hoście Proxmoxa
