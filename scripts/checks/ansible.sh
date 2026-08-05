# SEKCJA 8: idempotentność Ansible.
#
# Playbook uruchomiony na skonfigurowanej już infrastrukturze nie powinien chcieć
# niczego zmieniać. `--check` to przebieg na sucho: Ansible raportuje, co BY
# zrobił, ale niczego nie zapisuje.
#
# Domyślnie wyłączone, bo przebieg po 9 maszynach trwa kilka minut - włącza go
# SMOKE_FULL=1.

# Sumuje changed= i failed= ze wszystkich linii PLAY RECAP.
_recap_sum() {
    grep -oE "$1=[0-9]+" "$2" | grep -oE '[0-9]+' | awk '{s += $1} END {print s + 0}'
}

# Błąd w trybie --check zwykle nie oznacza zepsutej maszyny, tylko zadanie,
# którego Ansible nie potrafi zasymulować, bo zależy od skutku poprzedniego
# (np. klucz SSH dla konta, które dopiero miałoby powstać). Skutek jest jednak
# istotny: przebieg urywa się w tym miejscu, więc idempotentność dalszej części
# playbooka pozostaje niesprawdzona.
_report_check_errors() {
    local log="$1" failed="$2"

    if [ "$failed" -gt 0 ]; then
        ko "Ansible: przebieg --check bez bledow" \
           "failed=$failed - przebieg urwal sie, dalsze role niesprawdzone (log: $log)"
    else
        ok "Ansible: przebieg --check bez bledow"
    fi
}

_report_changed_tasks() {
    local log="$1" changed="$2" tasks

    if [ "$changed" -eq 0 ]; then
        ok "Ansible: changed == 0 (playbook jest idempotentny)"
        return 0
    fi

    tasks="$(grep -E '^(TASK|changed:)' "$log" | grep -B1 '^changed:' \
        | grep -oE 'TASK \[[^]]+\]' | sort -u | head -10 | tr '\n' ' ')"
    ko "Ansible: changed == 0" "changed=$changed; zadania: ${tasks:-patrz $log}"
    return 1
}

check_ansible_idempotence() {
    section "8. Idempotentnosc Ansible (--check)"

    if [ "${SMOKE_FULL:-0}" != "1" ]; then
        skip "ansible-playbook --check" "pominiete; wlacz przez SMOKE_FULL=1 (trwa kilka minut)"
        return
    fi

    local log rc changed failed
    log="$(mktemp "${TMPDIR:-/tmp}/smoke-ansible.XXXXXX")"

    # Świadomie BEZ --diff: interesuje nas wyłącznie licznik changed, a --diff
    # wypisałby treść szablonów razem z podstawionymi sekretami (hasło Grafany,
    # token k3s) do pliku, który zostaje na dysku po nieudanym teście.
    with_timeout "$ANSIBLE_TIMEOUT" sops exec-env "$TF_SECRETS" \
        'cd ansible && ansible-playbook playbook.yml --check' \
        >"$log" 2>&1
    rc=$?

    if is_timeout "$rc"; then
        ko "Ansible: changed == 0" "przekroczono limit ${ANSIBLE_TIMEOUT}s (log: $log)"
        return
    fi

    changed="$(_recap_sum changed "$log")"
    failed="$(_recap_sum failed "$log")"

    _report_check_errors  "$log" "${failed:-0}"
    # Log kasujemy tylko wtedy, gdy nie ma czego w nim szukać.
    if _report_changed_tasks "$log" "${changed:-1}" && [ "${failed:-0}" -eq 0 ]; then
        rm -f "$log"
    fi
}
