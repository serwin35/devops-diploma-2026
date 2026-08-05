# SOPS - komendy

Dwa pliki z sekretami, dwie różne kategorie:

| Plik | Zawiera | Kto czyta |
|---|---|---|
| `secrets.sops.yaml` (korzeń repo) | Poświadczenia providerów: Proxmox, Cloudflare, AWS (state), AWS (backupy), token Composera | Terraform (`sops exec-env`), Makefile |
| `ansible/group_vars/all/secrets.sops.yml` | Sekrety aplikacyjne: hasła baz, `APP_KEY`, tokeny GHCR/Jenkins/Grafana, webhooki | Ansible (`vars_plugins_enabled = community.sops`, deszyfruje w locie - **bez osobnego kroku**) |

Reguły szyfrowania w [`.sops.yaml`](../../.sops.yaml): każdy plik pasujący do
`\.sops\.ya?ml$` szyfruje się na klucz(e) age wskazane w `key_groups`. **Tylko
wartości są szyfrowane** - nazwy kluczy zostają jawne, więc `git diff` mówi,
*który* sekret się zmienił, nie ujawniając czym jest.

> Klucz prywatny: `~/.config/sops/age/keys.txt` (macOS: symlink też w
> `~/Library/Application Support/sops/age/`). **Zweryfikowano na żywo**
> 2026-08-05: odszyfrowanie obu plików, `exec-env` z podstawieniem zmiennych.

---

## Edycja

```bash
sops secrets.sops.yaml                              # przez Makefile: make secrets
sops ansible/group_vars/all/secrets.sops.yml
```

Otwiera odszyfrowaną treść w `$EDITOR`, po zapisie i zamknięciu szyfruje z
powrotem. Jeśli plik nie istnieje, SOPS tworzy go od zera i szyfruje na klucze
z `.sops.yaml` pasujące do jego ścieżki.

## Podgląd bez edycji

```bash
sops --decrypt secrets.sops.yaml
sops --decrypt ansible/group_vars/all/secrets.sops.yml
```

## Pojedyncza wartość - `--set`

Bez otwierania edytora, dobre do skryptów i CI:

```bash
sops --set '["CLOUDFLARE_API_TOKEN"] "nowy-token"' secrets.sops.yaml
sops --set '["jenkins_admin_password"] "nowe-haslo"' ansible/group_vars/all/secrets.sops.yml
```

Ścieżka w nawiasach to selektor `jq`-podobny - dla zagnieżdżonych struktur
`["klucz"]["podklucz"]`.

## Odczyt jednej wartości - `--extract`

```bash
sops --decrypt --extract '["CLOUDFLARE_API_TOKEN"]' secrets.sops.yaml
```

Zwraca samą wartość, bez reszty pliku - wygodne do wstrzyknięcia w inny
skrypt bez `jq`/`yq`.

## `exec-env` - uruchomienie z sekretami w środowisku

Odszyfrowane pary `klucz: wartość` z pliku trafiają jako zmienne środowiskowe
procesu potomnego - nic nie ląduje na dysku w postaci jawnej.

```bash
sops exec-env secrets.sops.yaml 'terraform -chdir=terraform plan'
sops exec-env secrets.sops.yaml 'env | grep -c TOKEN'   # ile zmiennych z TOKEN w nazwie

# Podmiana nazwy zmiennej "w locie" - np. do wywolania aws-cli kluczem
# backupowym zamiast domyslnego klucza stanu Terraforma
sops exec-env secrets.sops.yaml \
  'AWS_ACCESS_KEY_ID=$BACKUP_AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$BACKUP_AWS_SECRET_ACCESS_KEY \
   aws s3 ls s3://wolffire-backups/ --region eu-north-1'
```

**Świadomy szczegół tego repo:** `secrets.sops.yaml` trzyma DWA komplety
poświadczeń AWS - `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` dla użytkownika
IAM stanu Terraforma (prawo tylko do `terraform-states-wf`) i
`BACKUP_AWS_ACCESS_KEY_ID`/`BACKUP_AWS_SECRET_ACCESS_KEY` dla użytkownika
Jenkinsa (prawo tylko do `wolffire-backups`). Domyślne `aws s3 ls
s3://wolffire-backups/` z pierwszym kompletem kończy się `AccessDenied` -
to zamierzone rozdzielenie uprawnień (`terraform/bootstrap/iam.tf`), nie błąd
konfiguracji.

## Rotacja klucza age

Gdy klucz prywatny wycieknie albo trzeba go po prostu wymienić:

```bash
# 1. Nowa para kluczy
age-keygen -o ~/.config/sops/age/keys-new.txt

# 2. Dopisz NOWY klucz publiczny do .sops.yaml obok starego (nie zamieniaj od razu)
#    - edytuj sekcję `keys:` i `key_groups:`, dodaj drugi wpis z aliasem &nowy

# 3. Przepisz istniejące pliki na NOWY zestaw odbiorców, bez ich odszyfrowywania recznie
sops updatekeys secrets.sops.yaml
sops updatekeys ansible/group_vars/all/secrets.sops.yml

# 4. Po potwierdzeniu, ze nowy klucz dziala - usun stary z .sops.yaml i powtorz updatekeys
sops updatekeys secrets.sops.yaml
sops updatekeys ansible/group_vars/all/secrets.sops.yml

# 5. Podmien plik klucza uzywany na co dzien
mv ~/.config/sops/age/keys-new.txt ~/.config/sops/age/keys.txt
```

`sops updatekeys` re-szyfruje klucz danych (data key) dla nowego zestawu
odbiorców age - nie dotyka wartości sekretów, więc nie trzeba znać starych
haseł, żeby dodać/usunąć odbiorcę.

## Dodanie odbiorcy (kolejnej osoby)

```bash
# 1. Osoba generuje wlasna pare kluczy i przekazuje TYLKO publiczny
age-keygen -o ~/.config/sops/age/keys.txt   # u niej, na jej maszynie

# 2. Dopisz jej klucz publiczny do .sops.yaml, key_groups (drugi wpis pod &mateusz)
# 3. Zastosuj na wszystkich plikach .sops.yaml/.sops.yml w repo
sops updatekeys secrets.sops.yaml
sops updatekeys ansible/group_vars/all/secrets.sops.yml
```

Od tej pory obie osoby deszyfrują pliki swoim własnym kluczem prywatnym -
żaden sekret nie jest przesyłany między nimi.

## Częste problemy

| Objaw | Przyczyna | Rozwiązanie |
|---|---|---|
| `Failed to get the data key required to decrypt the SOPS file` | Brak klucza age albo klucz nie pasuje do żadnego odbiorcy w pliku | Sprawdź `echo $SOPS_AGE_KEY_FILE` i czy plik istnieje pod tą ścieżką |
| `AccessDenied` przy `aws s3 ls s3://wolffire-backups/` z domyślnym `exec-env` | Użyty klucz stanu Terraforma, nie klucz backupowy | Podstaw `BACKUP_AWS_ACCESS_KEY_ID`/`BACKUP_AWS_SECRET_ACCESS_KEY` (patrz wyżej) |
| Ansible nie widzi sekretów, zmienna pusta | `vars_plugins_enabled` nie zawiera `community.sops`, albo brak klucza age na tej maszynie | Sprawdź `ansible/ansible.cfg` -> `vars_plugins_enabled`; `echo $SOPS_AGE_KEY_FILE` |
| Po `sops <plik>` w edytorze nic się nie zmieniło, ale git widzi diff | SOPS re-szyfruje przy KAŻDYM zapisie (inny IV) - normalne, nawet bez zmiany treści | Nieszkodliwe; jeśli przeszkadza, nie zapisuj bez realnej zmiany |
| macOS: klucz działa w terminalu, ale nie w np. VS Code | Zmienna `SOPS_AGE_KEY_FILE` ustawiona tylko w `~/.zshrc`, GUI jej nie widzi | Ustaw ją explicite w `Makefile`/skrypcie (już zrobione - patrz nagłówek `Makefile`) |
