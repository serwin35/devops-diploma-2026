#!/usr/bin/env bash
#
# Testy dymne infrastruktury wolffire.dev - WYŁĄCZNIE ODCZYT.
#
# Skrypt niczego nie zmienia: żadnego apply, żadnego restartu usługi, żadnego
# zapisu na maszynach. Terraform uruchamiany jest w trybie `plan -lock=false`,
# Ansible w trybie `--check`. Reszta to zapytania HTTP, `kubectl get`
# i próby nawiązania połączenia TCP.
#
# Uruchomienie:
#   ./scripts/smoke-test.sh              # wszystkie sekcje
#   make test-infra                      # to samo, przez Makefile
#   ./scripts/smoke-test.sh net panels   # wybrane sekcje
#
# Sekcje: net panels monitoring k3s db fw tf ansible
#
# Zmienne środowiskowe:
#   SMOKE_EXPECT_APP=1  aplikacja jest już wdrożona - dev.wolffire.dev musi
#                       zwrócić 200, a cel Prometheusa `wolffire` musi być UP.
#                       Bez tej flagi 502 i martwy cel są akceptowane.
#   SMOKE_FULL=1        dodatkowo uruchamia test idempotentności Ansible
#                       (kilka minut, dlatego domyślnie wyłączony).
#   SMOKE_SKIP_TF=1     pomija test dryfu Terraforma.
#   SOPS_AGE_KEY_FILE   klucz age do odszyfrowania sekretów
#                       (domyślnie ~/.config/sops/age/keys.txt).
#
# Kod wyjścia: 0 gdy wszystko przeszło, 1 gdy cokolwiek padło.
#
# Układ plików:
#   scripts/smoke-test.sh     - ten plik: wejście, dobór sekcji, podsumowanie
#   scripts/lib/config.sh     - adresy, porty i limity czasu (jedyne miejsce
#                               do aktualizacji, gdy zmieni się infrastruktura)
#   scripts/lib/report.sh     - kolory, liczniki, ok/ko/skip, podsumowanie
#   scripts/lib/run.sh        - limit czasu, próba TCP, narzędzia tekstowe
#   scripts/lib/ssh.sh        - multipleksowane połączenia do maszyn
#   scripts/lib/secrets.sh    - odczyt poświadczeń z SOPS
#   scripts/checks/*.sh       - po jednym pliku na sekcję testów

# Celowo bez `set -e` - skrypt ma dojść do końca i policzyć WSZYSTKIE błędy,
# a nie zatrzymać się na pierwszym. Błędy obsługujemy jawnie, per test.
set -u
set -o pipefail

# ── Ścieżki ──────────────────────────────────────────────────────────────────
#
# Skrypt działa z dowolnego katalogu, ale wszystkie ścieżki względne (ansible/,
# terraform/, secrets.sops.yaml) liczone są od korzenia repozytorium.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# ── Biblioteka ───────────────────────────────────────────────────────────────
#
# Kolejność ma znaczenie: config definiuje ścieżki i limity używane przez
# resztę, report - kolory potrzebne przy komunikatach błędów.
. "$SCRIPT_DIR/lib/config.sh"
. "$SCRIPT_DIR/lib/report.sh"
. "$SCRIPT_DIR/lib/run.sh"
. "$SCRIPT_DIR/lib/ssh.sh"
. "$SCRIPT_DIR/lib/secrets.sh"

trap ssh_cleanup EXIT

# ── Sekcje ───────────────────────────────────────────────────────────────────
for _check_file in "$SCRIPT_DIR"/checks/*.sh; do
    . "$_check_file"
done
unset _check_file

# Kolejność jak w warstwach infrastruktury: od sieci, przez usługi, po kod,
# który to wszystko opisuje.
SECTIONS_DEFAULT="net panels monitoring k3s db fw tf ansible"

run_section() {
    case "$1" in
        net|network)    check_network ;;
        panels)         check_panels ;;
        monitoring|mon) check_monitoring ;;
        k3s)            check_k3s ;;
        db|databases)   check_databases ;;
        fw|firewall)    check_firewall ;;
        tf|terraform)   check_terraform ;;
        ansible)        check_ansible_idempotence ;;
        *)
            printf '%sNieznana sekcja: %s%s\n' "$C_RED" "$1" "$C_RESET" >&2
            printf 'Dostępne: %s\n' "$SECTIONS_DEFAULT" >&2
            exit 2
            ;;
    esac
}

usage() {
    sed -n '3,27p' "$0" | sed 's/^#\{1,\} \{0,1\}//'
    exit 0
}

header() {
    printf '%s%sTesty dymne infrastruktury - %s%s\n' "$C_BOLD" "$C_BLUE" "$PUBLIC_ZONE" "$C_RESET"
    printf '%stryb: TYLKO ODCZYT | %s | SMOKE_EXPECT_APP=%s SMOKE_FULL=%s%s\n' \
        "$C_DIM" "$(date '+%Y-%m-%d %H:%M:%S')" \
        "${SMOKE_EXPECT_APP:-0}" "${SMOKE_FULL:-0}" "$C_RESET"
}

main() {
    case "${1:-}" in
        -h|--help|help) usage ;;
    esac

    require_tools
    header

    local section_name
    for section_name in ${*:-$SECTIONS_DEFAULT}; do
        run_section "$section_name"
    done

    summary
}

main "$@"
