# Dostęp do zaszyfrowanych poświadczeń.
#
# Sekrety odszyfrowujemy RAZ, przed testem, i przekazujemy dalej przez stdin -
# nigdy w argumentach polecenia, bo te są widoczne w `ps` na maszynie docelowej.
#
# Plik jest włączany (`.`), nie uruchamiany.

# SOPS na macOS szuka klucza w ~/Library/Application Support/sops/age/, a na
# Linuksie w ~/.config/sops/age/. Wskazujemy ścieżkę XDG jawnie, żeby to samo
# repozytorium działało na laptopie i na agencie Jenkinsa bez rozjazdu.
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

# Wyciąga pojedynczy klucz z ansible/group_vars/all/secrets.sops.yml.
# Pusty wynik = nie udało się odszyfrować; wołający ma to obsłużyć jako `skip`,
# a nie jako błąd infrastruktury.
secret_get() {
    sops --decrypt --extract "[\"$1\"]" "$ANSIBLE_SECRETS" 2>/dev/null
}
