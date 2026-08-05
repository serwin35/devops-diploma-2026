# Raportowanie wyników: kolory, liczniki, formatowanie linii testu.
#
# Każdy test kończy się dokładnie jednym wywołaniem ok / ko / skip. To one
# prowadzą liczniki, więc żaden test nie może wypisywać wyniku samodzielnie.
#
# Plik jest włączany (`.`), nie uruchamiany.

# ── Kolory ───────────────────────────────────────────────────────────────────
#
# Wyłączane automatycznie, gdy wyjście nie jest terminalem (log Jenkinsa)
# albo gdy ustawiono NO_COLOR.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_BLUE=$'\033[36m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
else
    C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_DIM=''
fi

# ── Liczniki ─────────────────────────────────────────────────────────────────
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
# Lista błędów powtórzona na końcu - przy 36 testach nikt nie przewija logu
# w górę, żeby znaleźć te trzy linie, które mają znaczenie.
FAILURES=()

# ── Wypisywanie ──────────────────────────────────────────────────────────────
section() {
    printf '\n%s%s== %s ==%s\n' "$C_BOLD" "$C_BLUE" "$1" "$C_RESET"
}

# Drugi argument (opcjonalny) to szczegół wypisywany w drugiej linii, wcięty
# i przygaszony - kontekst dla czytającego, nie treść testu.
detail() {
    [ -n "${1:-}" ] || return 0
    printf '      %s%s%s\n' "$C_DIM" "$1" "$C_RESET"
}

ok() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"
    detail "${2:-}"
    return 0
}

ko() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILURES+=("$1${2:+ -- $2}")
    printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$1"
    detail "${2:-}"
    return 0
}

skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    printf '  %s○%s %s\n' "$C_YELLOW" "$C_RESET" "$1"
    detail "${2:-}"
    return 0
}

# ── Podsumowanie ─────────────────────────────────────────────────────────────
#
# Zwraca 1, gdy cokolwiek padło - to jego kod wyjścia staje się kodem wyjścia
# całego skryptu.
summary() {
    local total=$((PASS_COUNT + FAIL_COUNT))
    printf '\n%s%s== Podsumowanie ==%s\n' "$C_BOLD" "$C_BLUE" "$C_RESET"
    printf '  %sOK:%s %-4d %sBLAD:%s %-4d %sPOMINIETE:%s %-4d (testow wykonanych: %d)\n' \
        "$C_GREEN" "$C_RESET" "$PASS_COUNT" \
        "$C_RED" "$C_RESET" "$FAIL_COUNT" \
        "$C_YELLOW" "$C_RESET" "$SKIP_COUNT" "$total"

    if [ "$FAIL_COUNT" -gt 0 ]; then
        printf '\n  %sWykryte problemy:%s\n' "$C_RED" "$C_RESET"
        local i=1 failure
        for failure in "${FAILURES[@]}"; do
            printf '   %2d. %s\n' "$i" "$failure"
            i=$((i + 1))
        done
        printf '\n%sTESTY NIE PRZESZLY%s\n' "$C_RED" "$C_RESET"
        return 1
    fi

    printf '\n%sWSZYSTKO OK%s\n' "$C_GREEN" "$C_RESET"
    return 0
}
