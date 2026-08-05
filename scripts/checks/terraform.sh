# SEKCJA 7: dryf infrastruktury.
#
# `-detailed-exitcode` rozróżnia trzy sytuacje, które zwykły `plan` skleja
# w jedną:
#   0 - stan w chmurze zgodny z kodem,
#   1 - błąd narzędzia (brak init, złe poświadczenia, błąd składni),
#   2 - są zmiany do wprowadzenia, czyli realny dryf.
#
# `-lock=false`, bo plan nie modyfikuje stanu, a założenie blokady w backendzie
# jest zapisem - test ma być w pełni tylko do odczytu.

# Wyciąga z planu listę zasobów do zmiany. Wypisujemy pierwsze pozycje, żeby
# z logu dało się odczytać CO się rozjechało bez ponownego uruchamiania planu.
_report_drift() {
    local plan_out="$1"
    local summary all count preview

    summary="$(grep -E '^Plan: ' "$plan_out" | tail -1)"
    all="$(grep -E '^  # ' "$plan_out" | sed 's/^  # //')"
    count="$(count_lines "$all")"
    preview="$(printf '%s\n' "$all" | head -6 | sed 's/ *$//' | tr '\n' '|' | sed 's/|/ | /g')"
    [ "${count:-0}" -gt 6 ] && preview="$preview(i $((count - 6)) wiecej)"

  # API Proxmoxa jest dostępne wyłącznie tunelem SSH (port 8006 zamknięty
  # od internetu) - test otwiera go sam, żeby być samowystarczalnym.
  ssh -F ansible/ssh_config -O check wf-proxmox-1 2>/dev/null \
    || ssh -F ansible/ssh_config -fN -L 18006:localhost:8006 wf-proxmox-1 2>/dev/null  # PVE tunel
    ko "terraform plan: brak dryfu" "${summary:-wykryto zmiany}"
    detail "$preview"
}

check_terraform() {
    section "7. Terraform - dryf infrastruktury"

    if [ "${SMOKE_SKIP_TF:-0}" = "1" ]; then
        skip "terraform plan -detailed-exitcode" "pominiete przez SMOKE_SKIP_TF=1"
        return
    fi

    local plan_out rc
    plan_out="$(mktemp "${TMPDIR:-/tmp}/smoke-tfplan.XXXXXX")"

    with_timeout "$TF_TIMEOUT" sops exec-env "$TF_SECRETS" \
        'terraform -chdir=terraform plan -detailed-exitcode -no-color -input=false -lock=false' \
        >"$plan_out" 2>&1
    rc=$?

    case "$rc" in
        0)
            ok "terraform plan: brak dryfu (stan zgodny z kodem)"
            ;;
        2)
            _report_drift "$plan_out"
            ;;
        *)
            if is_timeout "$rc"; then
                ko "terraform plan: brak dryfu" "przekroczono limit ${TF_TIMEOUT}s"
            else
                ko "terraform plan: brak dryfu" \
                   "plan zakonczyl sie bledem (kod $rc): $(tail -3 "$plan_out" | tr '\n' ' ')"
            fi
            ;;
    esac

    rm -f "$plan_out"
}
