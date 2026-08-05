# Uruchamianie poleceń z limitem czasu i drobne narzędzia tekstowe.
#
# Plik jest włączany (`.`), nie uruchamiany.

# ── Limit czasu bez zaleznosci od coreutils ──────────────────────────────────
#
# macOS nie ma `timeout` - to część GNU coreutils. Zamiast wymagać
# `brew install coreutils` używamy perla, obecnego w systemie bazowym macOS
# i Debiana: `alarm` ustawia budzik, `exec` podmienia proces na właściwe
# polecenie, więc strumienie i kod wyjścia przechodzą bez pośrednika.
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_BIN="gtimeout"
else
    TIMEOUT_BIN=""
fi

with_timeout() {
    local secs="$1"; shift
    if [ -n "$TIMEOUT_BIN" ]; then
        "$TIMEOUT_BIN" "$secs" "$@"
    else
        perl -e 'my $t = shift; alarm $t; exec @ARGV or exit 127' "$secs" "$@"
    fi
}

# Czy kod wyjścia oznacza przekroczenie limitu czasu?
# 124 zwraca coreutils, 142 (128 + SIGALRM) - wariant perlowy.
is_timeout() {
    [ "$1" -eq 124 ] || [ "$1" -eq 142 ]
}

# ── Próba połączenia TCP ─────────────────────────────────────────────────────
#
# Zamiast `nc` (różne flagi na macOS i Linuksie, czasem w ogóle nieobecny)
# używamy /dev/tcp wbudowanego w basha. Zwraca 0, gdy połączenie doszło.
tcp_probe() {
    local host="$1" port="$2" secs="${3:-$TEST_TIMEOUT}"
    with_timeout "$secs" bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1
}

# ── Narzędzia tekstowe ───────────────────────────────────────────────────────
#
# Liczy niepuste linie w zmiennej. `printf '%s\n'` dokleja brakujący znak końca
# linii, `sed` usuwa puste - bez tego pusty ciąg liczyłby się jako jedna linia.
count_lines() {
    printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

# Czy ciąg zawiera podciąg? Bez `grep`, bo to najczęstsza operacja w testach.
contains() {
    case "$1" in
        *"$2"*) return 0 ;;
        *)      return 1 ;;
    esac
}

# ── Warunki wstępne ──────────────────────────────────────────────────────────
require_tools() {
    local missing="" tool
    for tool in ssh curl jq sops; do
        command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
        printf '%sBrak wymaganych narzędzi:%s%s\n' "$C_RED" "$C_RESET" "$missing" >&2
        exit 2
    fi
    if [ ! -f "$SSH_CONFIG" ]; then
        printf '%sBrak %s - uruchom skrypt w repozytorium projektu.%s\n' \
            "$C_RED" "$SSH_CONFIG" "$C_RESET" >&2
        exit 2
    fi
}
