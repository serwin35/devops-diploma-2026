# SEKCJA 2: panele widziane z internetu.
#
# Testujemy z zewnątrz, bez żadnego tunelu i VPN-a - dokładnie tak, jak zobaczy
# to przypadkowy skaner portów.

# 302 z nagłówkiem Location wskazującym na *.cloudflareaccess.com dowodzi dwóch
# rzeczy naraz:
#   - tunel z maszyny do Cloudflare żyje       (inaczej byłoby 502),
#   - przed usługą stoi Zero Trust Access      (inaczej byłoby 200 i panel
#                                               na widoku publicznym).
# Dlatego jedna asercja pokrywa i dostępność, i kontrolę dostępu.
_check_protected_panel() {
    local name="$1"
    local url="https://$name.$PUBLIC_ZONE"
    local response code location

    response="$(with_timeout "$TEST_TIMEOUT" curl -sS -o /dev/null \
        -w '%{http_code} %{redirect_url}' --max-time $((TEST_TIMEOUT - 2)) "$url" 2>/dev/null)"
    code="${response%% *}"
    location="${response#* }"

    if [ "$code" != "302" ]; then
        ko "$url -> 302 na Cloudflare Access" "otrzymano HTTP ${code:-brak odpowiedzi}"
    elif ! contains "$location" "cloudflareaccess.com"; then
        ko "$url -> 302 na Cloudflare Access" "przekierowanie poza Access: ${location:0:80}"
    else
        ok "$url -> 302 na Cloudflare Access (tunel zyje, Access chroni)"
    fi
}

# Środowisko dev jest celowo publiczne (protected = false w Terraformie), więc
# spodziewamy się 200. Przed wdrożeniem aplikacji cloudflared nie ma do czego
# proxować i zwraca 502 - to stan przejściowy, nie awaria, dlatego domyślnie
# jest raportowany, ale nie przewraca testu.
#
# -L jest tu konieczne: Laravel odpowiada na / przekierowaniem (302 na
# /dashboard, a niezalogowanemu dalej na /login), więc bez śledzenia przekierowań
# poprawnie działająca aplikacja dawałaby 302 i fałszywy błąd. Adres dev nie stoi
# za Zero Trust, więc -L nie może wpaść na stronę logowania Cloudflare
# i zamaskować awarii.
_check_dev_app() {
    local url="https://dev.$PUBLIC_ZONE"
    local response code final

    response="$(with_timeout "$TEST_TIMEOUT" curl -sSL -o /dev/null --max-redirs 5 \
        -w '%{http_code} %{url_effective}' --max-time $((TEST_TIMEOUT - 2)) "$url" 2>/dev/null)"
    code="${response%% *}"
    final="${response#* }"

    case "$code" in
        200)
            ok "$url -> HTTP 200 (aplikacja odpowiada, koncowy adres: $final)"
            ;;
        502)
            if [ "${SMOKE_EXPECT_APP:-0}" = "1" ]; then
                ko "$url -> HTTP 502" "SMOKE_EXPECT_APP=1, a origin nie odpowiada - aplikacja nie dziala"
            else
                ok "$url -> HTTP 502" "aplikacja jeszcze niewdrozona; ustaw SMOKE_EXPECT_APP=1, aby wymagac 200"
            fi
            ;;
        *)
            ko "$url -> HTTP 200 lub 502" "otrzymano HTTP ${code:-brak odpowiedzi}"
            ;;
    esac
}

check_panels() {
    section "2. Panele przez internet (tunel + Zero Trust Access)"

    local name
    for name in $PROTECTED_PANELS; do
        _check_protected_panel "$name"
    done

    _check_dev_app
}
