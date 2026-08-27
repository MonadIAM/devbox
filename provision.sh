#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "run as root: sudo bash $0" >&2
        exit 1
    fi
}

load_env() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        set -a
        . "$SCRIPT_DIR/.env"
        set +a
    fi
}

require_env() {
    for name in "$@"; do
        if [ -z "$(printenv "$name")" ]; then
            echo "$name is not set (missing wsl/.env, see .env.example)" >&2
            exit 1
        fi
    done
}

require_target_user() {
    TARGET_USER="$LINUX_USERNAME"
    if ! id "$TARGET_USER" >/dev/null 2>&1; then
        echo "user $TARGET_USER does not exist" >&2
        exit 1
    fi
}

linux_arch() {
    case "$(dpkg --print-architecture)" in
        amd64)
            printf '%s\n' amd64
            ;;
        arm64)
            printf '%s\n' arm64
            ;;
        *)
            echo "unsupported architecture: $(dpkg --print-architecture)" >&2
            exit 1
            ;;
    esac
}

install_base_packages() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -qq
    apt-get install -y -qq --no-install-recommends \
        ca-certificates curl wget gnupg lsb-release apt-transport-https \
        software-properties-common build-essential git jq unzip openssh-server \
        htop iproute2 dnsutils make openssl
}

install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        ubuntu_codename="$(. /etc/os-release && printf '%s\n' "$VERSION_CODENAME")"
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${ubuntu_codename} stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update -y -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    systemctl enable --now docker
    usermod -aG docker "$TARGET_USER"
}

install_k3d() {
    current_version=""
    if command -v k3d >/dev/null 2>&1; then
        current_version="$(k3d version | awk '/k3d version/ {print $3}')"
    fi
    if [ "$current_version" = "$K3D_VERSION" ]; then
        return
    fi

    arch="$(linux_arch)"
    tmp_file="$(mktemp)"
    curl -fsSL -o "$tmp_file" "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${arch}"
    install -o root -g root -m 0755 "$tmp_file" /usr/local/bin/k3d
    rm -f "$tmp_file"
}

install_kubectl() {
    current_version=""
    if command -v kubectl >/dev/null 2>&1; then
        current_version="$(kubectl version --client=true --output=yaml | awk '/gitVersion:/ {print $2; exit}')"
    fi
    if [ "$current_version" = "$KUBECTL_VERSION" ]; then
        return
    fi

    arch="$(linux_arch)"
    tmp_file="$(mktemp)"
    curl -fsSL -o "$tmp_file" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
    install -o root -g root -m 0755 "$tmp_file" /usr/local/bin/kubectl
    rm -f "$tmp_file"
}

install_helm() {
    current_version=""
    if command -v helm >/dev/null 2>&1; then
        current_version="$(helm version --template '{{.Version}}')"
    fi
    if [ "$current_version" = "$HELM_VERSION" ]; then
        return
    fi

    arch="$(linux_arch)"
    tmp_dir="$(mktemp -d)"
    curl -fsSL -o "$tmp_dir/helm.tgz" "https://get.helm.sh/helm-${HELM_VERSION}-linux-${arch}.tar.gz"
    tar -xzf "$tmp_dir/helm.tgz" -C "$tmp_dir"
    install -o root -g root -m 0755 "$tmp_dir/linux-${arch}/helm" /usr/local/bin/helm
    rm -rf "$tmp_dir"
}

apply_sysctl_tuning() {
    cat > /etc/sysctl.d/99-monadiam-k3d.conf <<-SYSCTL_EOF
	fs.inotify.max_user_watches=524288
	fs.inotify.max_user_instances=512
	vm.max_map_count=262144
	net.ipv4.ip_forward=1
	SYSCTL_EOF
    sysctl --system >/dev/null
}

configure_ipv4_precedence() {
    if ! grep -Eq '^[[:space:]]*precedence[[:space:]]+::ffff:0:0/96[[:space:]]+100' /etc/gai.conf; then
        printf '\nprecedence ::ffff:0:0/96  100\n' >> /etc/gai.conf
    fi
}

configure_sshd() {
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-monadiam.conf <<-SSHD_EOF
	Port ${SSH_PORT}
	PasswordAuthentication yes
	PubkeyAuthentication yes
	PermitRootLogin no
	SSHD_EOF
    install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_USER" "/home/$TARGET_USER/.ssh"
    touch "/home/$TARGET_USER/.ssh/authorized_keys"
    chmod 0600 "/home/$TARGET_USER/.ssh/authorized_keys"
    chown "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.ssh/authorized_keys"
    systemctl enable --now ssh
}

main() {
    require_root
    load_env
    require_env LINUX_USERNAME SSH_PORT K3D_VERSION HELM_VERSION KUBECTL_VERSION
    require_target_user

    echo "[1/7] apt"
    install_base_packages

    echo "[2/7] docker"
    install_docker

    echo "[3/7] k3d, kubectl, helm"
    install_k3d
    install_kubectl
    install_helm

    echo "[4/7] sysctl"
    apply_sysctl_tuning

    echo "[5/7] IPv4 precedence"
    configure_ipv4_precedence

    echo "[6/7] sshd on port $SSH_PORT"
    configure_sshd

    echo "[7/7] done"
}

main "$@"
