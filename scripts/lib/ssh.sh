# Połączenia SSH do maszyn testowanych od środka.
#
# Cała topologia (port, ProxyJump przez bastion, klucze) siedzi w
# ansible/ssh_config - tutaj dokładamy tylko multipleksowanie i tryb wsadowy.
#
# Plik jest włączany (`.`), nie uruchamiany.

# BatchMode gwarantuje, że brak klucza kończy się błędem zamiast pytaniem
# o hasło w środku przebiegu testów.
#
# ControlMaster jest tu warunkiem dotrzymania limitu 10 s na test: bez niego
# każdy z ~25 testów zdalnych płaciłby za pełny handshake plus przeskok przez
# bastion. Z multipleksowaniem płaci za to tylko pierwszy test na maszynie.
#
# Gniazdo multipleksera musi zmieścić się w limicie ścieżki gniazda uniksowego
# (104 bajty na macOS). Sam skrót %C ma 40 znaków, a $TMPDIR na macOS to
# /var/folders/<...>/T/ - razem przekracza limit, dlatego katalog zakładamy
# jawnie w /tmp, a nie w $TMPDIR.
SSH_CONTROL_DIR="$(mktemp -d /tmp/smoke-ssh.XXXXXX)"

SSH_OPTS="-F $SSH_CONFIG -o BatchMode=yes -o ConnectTimeout=6"
SSH_OPTS="$SSH_OPTS -o ControlMaster=auto -o ControlPath=$SSH_CONTROL_DIR/cm-%C -o ControlPersist=120s"

# Zamyka sesje główne i sprząta gniazda. Wpięte w trap EXIT przez smoke-test.sh.
ssh_cleanup() {
    local host
    for host in $ALL_HOSTS; do
        ssh $SSH_OPTS -O exit "ansible@wf-$host" >/dev/null 2>&1
    done
    rm -rf "$SSH_CONTROL_DIR"
}

# Uruchamia polecenie na zdalnej maszynie i zwraca jego stdout.
#
# Świadomie bez -n: część testów podaje sekret przez stdin, żeby nie trafił
# do argumentów procesu widocznych w `ps` na maszynie docelowej.
ssh_do() {
    local host="$1"; shift
    with_timeout "$TEST_TIMEOUT" ssh $SSH_OPTS "ansible@wf-$host" "$@" 2>/dev/null
}

# Skrót na najczęstszy przypadek: pobranie zasobu HTTP z wnętrza maszyny.
ssh_http_code() {
    local host="$1" url="$2"
    ssh_do "$host" "curl -s -o /dev/null -w '%{http_code}' --max-time 6 '$url'"
}

ssh_http_body() {
    local host="$1" url="$2"
    ssh_do "$host" "curl -s --max-time 6 '$url'"
}
