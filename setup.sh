#!/bin/bash
# =============================================================================
# Vast.ai Host Machine Setup Script
# Supports single and multi-GPU machines on Ubuntu 22.04/24.04
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*"; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }
ask()     { echo -e "${YELLOW}$*${RESET}"; }

banner() {
cat << 'EOF'
 ╔══════════════════════════════════════════════════════╗
 ║          Vast.ai Host Setup — by MasterTech          ║
 ║   Single & Multi-GPU | Ubuntu 22.04/24.04 Ready      ║
 ╚══════════════════════════════════════════════════════╝
EOF
}

# ── Pre-flight checks ─────────────────────────────────────────────────────────
preflight() {
  step "Pre-flight checks"

  [[ $EUID -ne 0 ]] && error "Run as root: sudo bash setup.sh"

  # OS check
  . /etc/os-release
  case "$ID" in
    ubuntu|debian|linuxmint|pop)
      success "OS: $PRETTY_NAME"
      ;;
    *)
      warn "Detected OS: $ID — this script is tested on Ubuntu/Debian."
      warn "It may still work but is not officially supported."
      read -rp "Continue anyway? [y/N]: " ans
      [[ "${ans,,}" == "y" ]] || exit 1
      ;;
  esac

  # NVIDIA GPU check
  if ! command -v nvidia-smi &>/dev/null; then
    warn "nvidia-smi not found — install NVIDIA drivers first"
    warn "Run: ubuntu-drivers autoinstall && reboot"
    read -rp "Continue anyway? [y/N]: " ans
    [[ "${ans,,}" == "y" ]] || exit 1
  else
    GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)
    GPU_NAMES=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | paste -sd', ')
    success "GPU(s): $GPU_COUNT × $GPU_NAMES"
  fi

  # Docker check
  if ! command -v docker &>/dev/null; then
    warn "Docker not found — installing..."
    apt-get update -qq
    apt-get install -y ca-certificates curl gnupg -qq
    install -m 0755 -d /etc/apt/keyrings
    # Use correct repo for distro (ubuntu vs debian)
    . /etc/os-release
    DOCKER_DISTRO="${ID}"
    [[ "$ID" == "linuxmint" || "$ID" == "pop" ]] && DOCKER_DISTRO="ubuntu"
    curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/${DOCKER_DISTRO} ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin -qq
    systemctl enable --now docker
  fi
  success "Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')"
}

# ── Collect inputs ─────────────────────────────────────────────────────────────
collect_inputs() {
  step "Configuration inputs"
  echo ""

  # API Key
  ask "Enter your Vast.ai API key (from console.vast.ai → Account → API key):"
  read -rp "  API Key: " VAST_API_KEY
  [[ -z "$VAST_API_KEY" ]] && error "API key required"

  # Machine name
  ask "\nEnter a hostname for this machine (e.g. mt-1, gpu-rig-1):"
  read -rp "  Hostname: " MACHINE_NAME
  [[ -z "$MACHINE_NAME" ]] && error "Hostname required"

  # Machine number for port range calculation
  ask "\nEnter machine number (1, 2, 3, 4...) — auto-calculates unique port range:"
  ask "  Machine 1→20000-20499  2→20500-20999  3→21000-21499  4→21500-21999"
  read -rp "  Machine #: " MACHINE_NUM
  [[ -z "$MACHINE_NUM" || ! "$MACHINE_NUM" =~ ^[0-9]+$ ]] && error "Must be a number"

  AUTO_PORT_START=$(( 19500 + (MACHINE_NUM * 500) ))
  AUTO_PORT_END=$(( AUTO_PORT_START + 499 ))

  ask "\nPort range (auto-calculated: ${AUTO_PORT_START}–${AUTO_PORT_END}) — press ENTER to accept or type custom start:"
  read -rp "  Port range start [${AUTO_PORT_START}]: " CUSTOM_PORT_START
  if [[ -n "$CUSTOM_PORT_START" && "$CUSTOM_PORT_START" =~ ^[0-9]+$ ]]; then
    PORT_START="$CUSTOM_PORT_START"
    PORT_END=$(( PORT_START + 499 ))
    info "Custom port range: ${PORT_START}–${PORT_END}"
  else
    PORT_START="$AUTO_PORT_START"
    PORT_END="$AUTO_PORT_END"
    info "Auto port range: ${PORT_START}–${PORT_END}"
  fi
  info "→ Forward these ports on your router to this machine's LAN IP"

  # Public IP
  ask "\nEnter your public/WAN IP address (shared by all machines behind router):"
  DETECTED_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "")
  [[ -n "$DETECTED_IP" ]] && info "Detected public IP: $DETECTED_IP"
  read -rp "  Public IP [${DETECTED_IP}]: " PUBLIC_IP
  PUBLIC_IP="${PUBLIC_IP:-$DETECTED_IP}"
  [[ -z "$PUBLIC_IP" ]] && error "Public IP required"

  # Network interface
  DEFAULT_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
  ask "\nNetwork interface for this machine:"
  ip link show 2>/dev/null | grep -E '^[0-9]+:' | awk -F': ' '{print "  " $2}' | grep -v lo || true
  read -rp "  Interface [${DEFAULT_IFACE}]: " NETWORK_IFACE
  NETWORK_IFACE="${NETWORK_IFACE:-$DEFAULT_IFACE}"

  # LAN IP
  DETECTED_LAN=$(ip -4 addr show "$NETWORK_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1)
  ask "\nThis machine's static LAN IP (will be configured via netplan):"
  read -rp "  LAN IP [${DETECTED_LAN}]: " LAN_IP
  LAN_IP="${LAN_IP:-$DETECTED_LAN}"
  [[ -z "$LAN_IP" ]] && error "LAN IP required"

  # Gateway
  DETECTED_GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
  ask "\nRouter/gateway IP:"
  read -rp "  Gateway [${DETECTED_GW}]: " GATEWAY
  GATEWAY="${GATEWAY:-$DETECTED_GW}"

  # Subnet (extract from current IP or ask)
  DETECTED_CIDR=$(ip -4 addr show "$NETWORK_IFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+/\d+' | head -1 | cut -d'/' -f2)
  DETECTED_CIDR="${DETECTED_CIDR:-24}"
  ask "\nSubnet prefix (usually 24 for /24 = 255.255.255.0):"
  read -rp "  Prefix [${DETECTED_CIDR}]: " SUBNET_PREFIX
  SUBNET_PREFIX="${SUBNET_PREFIX:-$DETECTED_CIDR}"

  # GPU pricing
  ask "\nGPU rental price in \$/hr (check vast.ai marketplace for competitive prices):"
  read -rp "  Base price/GPU/hr [\$0.20]: " GPU_PRICE
  GPU_PRICE="${GPU_PRICE:-0.20}"

  ask "\nMinimum bid price/GPU/hr (usually 80% of base):"
  MIN_BID=$(python3 -c "print(round(float('${GPU_PRICE}') * 0.8, 3))" 2>/dev/null || echo "0.16")
  read -rp "  Min bid [${MIN_BID}]: " MIN_BID_PRICE
  MIN_BID_PRICE="${MIN_BID_PRICE:-$MIN_BID}"

  # Speedtest server
  ask "\nSpeedtest server ID — find yours at speedtest.net/servers or leave blank to skip."
  ask "  Examples: 22709 (OneBroadband Kolkata), 1452 (Airtel India), 5114 (Comcast US)"
  read -rp "  Server ID [auto]: " SPEEDTEST_SERVER
  SPEEDTEST_SERVER="${SPEEDTEST_SERVER:-}"

  echo ""
  echo -e "${BOLD}─── Configuration Summary ───────────────────────────────${RESET}"
  echo -e "  Hostname      : ${GREEN}$MACHINE_NAME${RESET}"
  echo -e "  Machine #     : ${GREEN}$MACHINE_NUM${RESET}"
  echo -e "  Port range    : ${GREEN}${PORT_START}–${PORT_END}${RESET}  ← forward on router"
  echo -e "  Public IP     : ${GREEN}$PUBLIC_IP${RESET}"
  echo -e "  LAN IP        : ${GREEN}${LAN_IP}/${SUBNET_PREFIX}${RESET}"
  echo -e "  Gateway       : ${GREEN}$GATEWAY${RESET}"
  echo -e "  Interface     : ${GREEN}$NETWORK_IFACE${RESET}"
  echo -e "  GPU price     : ${GREEN}\$${GPU_PRICE}/hr${RESET}  (min bid \$${MIN_BID_PRICE})"
  echo -e "  Speedtest srv : ${GREEN}${SPEEDTEST_SERVER:-auto-detect}${RESET}"
  echo -e "  Vast API key  : ${GREEN}${VAST_API_KEY:0:12}…${RESET}"
  echo -e "${BOLD}─────────────────────────────────────────────────────────${RESET}"
  echo ""
  read -rp "Proceed with setup? [Y/n]: " confirm
  [[ "${confirm,,}" == "n" ]] && exit 0
}

# ── Static IP via Netplan ─────────────────────────────────────────────────────
setup_static_ip() {
  step "Static IP configuration (netplan)"

  NETPLAN_FILE="/etc/netplan/99-vastai-static.yaml"
  cat > "$NETPLAN_FILE" << YAML
network:
  version: 2
  ethernets:
    ${NETWORK_IFACE}:
      dhcp4: false
      addresses:
        - ${LAN_IP}/${SUBNET_PREFIX}
      routes:
        - to: default
          via: ${GATEWAY}
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
YAML

  chmod 600 "$NETPLAN_FILE"
  netplan generate 2>/dev/null && netplan apply 2>/dev/null || warn "netplan apply failed — check config manually"
  success "Static IP set: ${LAN_IP}/${SUBNET_PREFIX} via $GATEWAY"
}

# ── Hostname ──────────────────────────────────────────────────────────────────
setup_hostname() {
  step "Hostname"
  hostnamectl set-hostname "$MACHINE_NAME"
  grep -q "$MACHINE_NAME" /etc/hosts || echo "127.0.1.1  $MACHINE_NAME" >> /etc/hosts
  success "Hostname: $MACHINE_NAME"
}

# ── Vast.ai Kaalia daemon ─────────────────────────────────────────────────────
setup_kaalia() {
  step "Vast.ai Kaalia daemon"

  if systemctl is-active --quiet vastai.service 2>/dev/null; then
    info "Kaalia already running — skipping install, updating config only"
  else
    info "Downloading and running official Vast.ai setup..."
    curl -fsSL https://vast.ai/install -o /tmp/vast_install.sh
    bash /tmp/vast_install.sh
  fi

  # Set API key
  echo "$VAST_API_KEY" > /var/lib/vastai_kaalia/api_key
  chmod 600 /var/lib/vastai_kaalia/api_key
  success "API key configured"

  # Set public IP in Vast.ai
  curl -s -X PUT \
    -H "Authorization: Bearer ${VAST_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"public_ipaddr\": \"${PUBLIC_IP}\"}" \
    "https://console.vast.ai/api/v0/users/self/" > /dev/null 2>&1 || true
  success "Public IP set: $PUBLIC_IP"
}

# ── Docker configuration ──────────────────────────────────────────────────────
setup_docker() {
  step "Docker daemon configuration"

  DAEMON_JSON="/etc/docker/daemon.json"
  KAALIA_SHIM="/var/lib/vastai_kaalia/latest/kaalia_docker_shim"

  # Back up existing config
  [[ -f "$DAEMON_JSON" ]] && cp "$DAEMON_JSON" "${DAEMON_JSON}.backup"

  # Write clean config — nvidia in runtimes but NOT as default-runtime
  # (setting default-runtime:nvidia breaks non-GPU containers)
  SHIM_PATH="${KAALIA_SHIM}"
  [[ ! -f "$KAALIA_SHIM" ]] && SHIM_PATH="nvidia-container-runtime"

  cat > "$DAEMON_JSON" << JSON
{
  "registry-mirrors": [
    "https://registry-1.docker.io",
    "https://docker1.vast.ai",
    "https://docker2.vast.ai"
  ],
  "runtimes": {
    "nvidia": {
      "args": [],
      "path": "${SHIM_PATH}"
    }
  }
}
JSON

  systemctl restart docker
  success "Docker daemon configured (nvidia runtime registered, not set as default)"
}

# ── NVIDIA container toolkit ──────────────────────────────────────────────────
setup_nvidia_toolkit() {
  step "NVIDIA container toolkit"

  if ! dpkg -l | grep -q nvidia-container-toolkit 2>/dev/null; then
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
      gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    apt-get update -qq
    apt-get install -y nvidia-container-toolkit
    nvidia-ctk runtime configure --runtime=docker
  fi
  success "NVIDIA container toolkit ready"
}

# ── dmidecode sudoers ─────────────────────────────────────────────────────────
setup_sudoers() {
  step "Sudoers for dmidecode (CPU info)"

  # Ensure dmidecode is installed
  command -v dmidecode &>/dev/null || apt-get install -y dmidecode -qq

  SUDOERS_FILE="/etc/sudoers.d/vastai_dmidecode"
  echo "vastai_kaalia ALL=(ALL) NOPASSWD: /usr/sbin/dmidecode" > "$SUDOERS_FILE"
  chown root:root "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  success "dmidecode installed and sudoers configured"
}

# ── Speedtest mirror ──────────────────────────────────────────────────────────
setup_speedtest() {
  step "Speedtest server configuration"

  MIRRORS_FILE="/var/lib/vastai_kaalia/data/speedtest_mirrors"
  if [[ -n "$SPEEDTEST_SERVER" ]]; then
    echo "$SPEEDTEST_SERVER" > "$MIRRORS_FILE"
    chown vastai_kaalia:docker "$MIRRORS_FILE" 2>/dev/null || true
    success "Speedtest server: $SPEEDTEST_SERVER"
  else
    info "No speedtest server set — Kaalia will auto-select nearest server"
  fi
}

# ── Protected instances directory ─────────────────────────────────────────────
setup_protected_instances() {
  step "Protected instances directory"

  DIR="/var/lib/vastai_kaalia/data/protected_instances"
  mkdir -p "$DIR"
  chown vastai_kaalia:docker "$DIR" 2>/dev/null || true
  success "Protected instances directory ready"
}

# ── Auto-cleanup service ──────────────────────────────────────────────────────
setup_cleanup_service() {
  step "Auto-cleanup systemd service"

  cat > /usr/local/bin/vastai_docker_cleanup.sh << 'SCRIPT'
#!/bin/bash
# Skip if any Vast.ai rental containers (C.*) are running
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^C\.'; then
  exit 0
fi
docker container prune -f 2>/dev/null
docker builder prune --all -f 2>/dev/null
fstrim /var/lib/docker 2>/dev/null
SCRIPT
  chmod +x /usr/local/bin/vastai_docker_cleanup.sh

  cat > /etc/systemd/system/vastai_docker_cleanup.service << 'SVC'
[Unit]
Description=Vast.ai Docker Cleanup
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vastai_docker_cleanup.sh
SVC

  cat > /etc/systemd/system/vastai_docker_cleanup.timer << 'TMR'
[Unit]
Description=Vast.ai Docker Cleanup (runs hourly when no rentals active)

[Timer]
OnBootSec=10min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
TMR

  systemctl daemon-reload
  systemctl enable --now vastai_docker_cleanup.timer
  success "Auto-cleanup timer enabled (runs hourly, skips during active rentals)"
}

# ── Install vastai CLI ────────────────────────────────────────────────────────
setup_vastai_cli() {
  step "Vast.ai CLI"

  if ! command -v pip3 &>/dev/null; then
    apt-get install -y python3-pip -qq
  fi

  pip3 install vastai --break-system-packages -q 2>/dev/null || pip3 install vastai -q 2>/dev/null || true

  # Find binary — check root's local bin first, then system paths
  VASTAI_BIN=""
  for p in /root/.local/bin/vastai /usr/local/bin/vastai /usr/bin/vastai; do
    [[ -x "$p" ]] && VASTAI_BIN="$p" && break
  done
  # Fall back to PATH
  [[ -z "$VASTAI_BIN" ]] && VASTAI_BIN=$(command -v vastai 2>/dev/null || echo "")
  [[ -z "$VASTAI_BIN" ]] && warn "vastai CLI not found in PATH — may need to re-run or add ~/.local/bin to PATH" && return

  $VASTAI_BIN set api-key "$VAST_API_KEY" 2>/dev/null || true

  # Export for use in later functions
  export VASTAI_BIN
  success "vastai CLI: $VASTAI_BIN ($($VASTAI_BIN --version 2>/dev/null || echo 'installed'))"
}

# ── Restart services ──────────────────────────────────────────────────────────
restart_services() {
  step "Restarting Vast.ai services"

  # Fix launch_metrics_pusher.sh permissions (missing +x causes vast_metrics exit 203)
  LAUNCH_METRICS="/var/lib/vastai_kaalia/latest/launch_metrics_pusher.sh"
  [[ -f "$LAUNCH_METRICS" ]] && chmod +x "$LAUNCH_METRICS"

  # Fix speedtest_mirrors ownership (Permission denied if not owned by vastai_kaalia)
  MIRRORS_FILE="/var/lib/vastai_kaalia/data/speedtest_mirrors"
  [[ -f "$MIRRORS_FILE" ]] && chown vastai_kaalia:docker "$MIRRORS_FILE" 2>/dev/null || true

  # Fix corrupted vastai/test:common image (causes "Unknown CPU" on dashboard)
  if docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q 'vastai/test:common'; then
    info "Refreshing vastai/test:common image (prevents Unknown CPU issue)..."
    docker rmi vastai/test:common 2>/dev/null || true
    docker pull vastai/test:common 2>/dev/null || true
  fi

  systemctl daemon-reload
  systemctl restart vastai.service 2>/dev/null || true
  systemctl restart vast_metrics.service 2>/dev/null || true

  # Disable bouncer — launch_bouncer.sh often missing, causes service failure
  systemctl stop vastai_bouncer.service 2>/dev/null || true
  systemctl disable vastai_bouncer.service 2>/dev/null || true

  sleep 8
  systemctl is-active --quiet vastai.service && success "vastai.service running" \
    || warn "vastai.service not running — check: journalctl -u vastai.service"
  systemctl is-active --quiet vast_metrics.service && success "vast_metrics.service running" \
    || warn "vast_metrics.service not running — check: journalctl -u vast_metrics.service"
}

# ── Push speed and machine info to Vast.ai ───────────────────────────────────
push_machine_info() {
  step "Pushing machine info and speed to Vast.ai"

  SEND_MACH="/var/lib/vastai_kaalia/send_mach_info.py"
  if [[ -f "$SEND_MACH" ]]; then
    sudo -u vastai_kaalia python3 "$SEND_MACH" \
      --speedtest \
      --server "https://elb-internal-nocache.vast.ai" \
      2>&1 | grep -E 'Data sent|error|bandwidth' || true
    success "Machine info and speed pushed to Vast.ai"
  else
    warn "send_mach_info.py not found — skipping speed push"
  fi
}

# ── List machine on marketplace ───────────────────────────────────────────────
list_machine() {
  step "Listing machine on Vast.ai marketplace"

  # Get machine ID
  MACHINE_ID=$(cat /var/lib/vastai_kaalia/machine_id 2>/dev/null || echo "")
  if [[ -z "$MACHINE_ID" ]]; then
    warn "Machine ID not found — Kaalia may still be registering. Skipping marketplace listing."
    return
  fi

  VASTAI_BIN="${VASTAI_BIN:-$(command -v vastai 2>/dev/null || echo /root/.local/bin/vastai)}"

  # End date: 90 days from now
  END_DATE=$(python3 -c "import time; print(int(time.time() + 90*86400))")

  $VASTAI_BIN list machine "$MACHINE_ID" \
    --price_gpu "$GPU_PRICE" \
    --price_min_bid "$MIN_BID_PRICE" \
    --price_disk 0.01 \
    --price_inetu 0.005 \
    --price_inetd 0.005 \
    --end_date "$END_DATE" 2>&1 || warn "Listing failed — run manually after Kaalia fully starts"

  success "Machine $MACHINE_ID listed at \$${GPU_PRICE}/GPU/hr (expires in 90 days)"
}

# ── Self test ─────────────────────────────────────────────────────────────────
run_self_test() {
  step "Self-test (Vast.ai verification)"

  MACHINE_ID=$(cat /var/lib/vastai_kaalia/machine_id 2>/dev/null || echo "")
  [[ -z "$MACHINE_ID" ]] && warn "Machine ID not found — skipping self-test" && return

  VASTAI_BIN="${VASTAI_BIN:-$(command -v vastai 2>/dev/null || echo /root/.local/bin/vastai)}"

  read -rp "Run self-test now? This takes ~3 minutes and verifies the machine on Vast.ai [Y/n]: " run_test
  [[ "${run_test,,}" == "n" ]] && info "Skipped — run later: $VASTAI_BIN self-test machine --ignore-requirements $MACHINE_ID" && return

  $VASTAI_BIN self-test machine --ignore-requirements "$MACHINE_ID" 2>&1
}

# ── Router port forwarding info ───────────────────────────────────────────────
# Called once before install (with estimated ports) and once after (with actual ports)
show_router_guide() {
  local title="${1:-Estimated}"

  # Try to detect actual Kaalia listening ports after install
  # Kaalia uses ports in the 20000–65000 range; filter out system ports
  ACTUAL_PORTS=$(ss -tlnp 2>/dev/null \
    | grep -oP '(?:0\.0\.0\.0|::):\K[0-9]+' \
    | awk '$1 > 1024 && $1 != 5900' \
    | grep -v '^22$' | grep -v '^53$' | grep -v '^2375$' \
    | sort -un | tr '\n' ' ' 2>/dev/null || echo "")

  if [[ -n "$ACTUAL_PORTS" && "$title" == "Actual"* ]]; then
    PORT_DISPLAY="$ACTUAL_PORTS"
    info "Detected Kaalia ports: $ACTUAL_PORTS"
  else
    PORT_DISPLAY="${PORT_START}–${PORT_END} (estimated — confirm after Kaalia starts)"
  fi

  step "Router Port Forwarding — ${title} ports"
  echo ""
  echo -e "  ${YELLOW}⚠  Configure these rules on your router BEFORE testing:${RESET}"
  echo ""
  echo -e "  ┌────────────────────────────────────────────────────────────┐"
  echo -e "  │  External Port(s)           →  This Machine    Protocol    │"
  echo -e "  ├────────────────────────────────────────────────────────────┤"
  echo -e "  │  ${PORT_DISPLAY}  →  ${LAN_IP}   TCP+UDP    │"
  echo -e "  │  22 (or custom SSH port)    →  ${LAN_IP}   TCP        │"
  echo -e "  └────────────────────────────────────────────────────────────┘"
  echo ""
  echo -e "  ${CYAN}Multi-machine port ranges (one per machine):${RESET}"
  echo -e "  Machine 1 → 20000–20499  |  Machine 2 → 20500–20999"
  echo -e "  Machine 3 → 21000–21499  |  Machine 4 → 21500–21999"
  echo ""
  echo -e "  ${CYAN}To confirm actual Kaalia ports after setup:${RESET}"
  echo -e "    ss -tlnp | grep -v '127\\.' | grep LISTEN"
  echo ""
  read -rp "  Press ENTER once you have configured port forwarding..." _
}

# ── Final summary ─────────────────────────────────────────────────────────────
print_summary() {
  MACHINE_ID=$(cat /var/lib/vastai_kaalia/machine_id 2>/dev/null || echo "pending")
  VASTAI_BIN="${VASTAI_BIN:-$(command -v vastai 2>/dev/null || echo /root/.local/bin/vastai)}"

  # Detect actual listening ports from Kaalia (ports >1024, not 2375/Docker API, not SSH)
  ACTUAL_PORTS=$(ss -tlnp 2>/dev/null \
    | grep -oP '(?:0\.0\.0\.0|::):\K[0-9]+' \
    | awk '$1 > 1024 && $1 != 2375 && $1 != 5900' \
    | grep -v '^22$' | grep -v '^53$' \
    | sort -un | tr '\n' ' ' 2>/dev/null || echo "${PORT_START}–${PORT_END}")

  # Check verification status from Vast.ai API
  VERIFIED="unknown"
  if [[ -n "$MACHINE_ID" && "$MACHINE_ID" != "pending" ]]; then
    VERIFIED=$(curl -s "https://console.vast.ai/api/v0/machines/?api_key=${VAST_API_KEY}" 2>/dev/null \
      | python3 -c "
import json,sys
data=json.load(sys.stdin)
for m in data.get('machines',[]):
    if str(m.get('id')) == '${MACHINE_ID}':
        print(m.get('verification','unknown'))
" 2>/dev/null || echo "unknown")
  fi

  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║                   Setup Complete!                        ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  Machine ID    : ${CYAN}$MACHINE_ID${RESET}"
  echo -e "  Hostname      : ${CYAN}$MACHINE_NAME${RESET}"
  echo -e "  LAN IP        : ${CYAN}${LAN_IP}/${SUBNET_PREFIX}${RESET}"
  echo -e "  Public IP     : ${CYAN}$PUBLIC_IP${RESET}"
  echo -e "  Kaalia ports  : ${CYAN}${ACTUAL_PORTS}${RESET}  ← forward these on router"
  echo -e "  GPU price     : ${CYAN}\$${GPU_PRICE}/hr${RESET}"
  echo -e "  Listing ends  : ${CYAN}90 days from now${RESET} (run scripts/relist.sh to renew)"
  echo ""
  echo -e "  Services:"
  svc_ok() { systemctl is-active --quiet "$1" 2>/dev/null && echo -e "${GREEN}running${RESET}" || echo -e "${RED}stopped${RESET}"; }
  echo -e "    vastai.service              : $(svc_ok vastai.service)"
  echo -e "    vast_metrics.service        : $(svc_ok vast_metrics.service)"
  echo -e "    vastai_docker_cleanup.timer : $(svc_ok vastai_docker_cleanup.timer)"
  echo ""
  if [[ "$VERIFIED" == "verified" ]]; then
    echo -e "  Verification  : ${GREEN}✔ VERIFIED${RESET}"
  else
    echo -e "  Verification  : ${YELLOW}⚠ UNVERIFIED${RESET}"
    echo -e "    → Run self-test: $VASTAI_BIN self-test machine --ignore-requirements $MACHINE_ID"
    echo -e "    → Requires: RAM ≥ GPU VRAM, port forwarding working"
    echo -e "    → Internet ≥500 Mbps needed for verified badge (still rents without it)"
  fi
  echo ""
  echo -e "  Disk cleanup  : ${GREEN}Auto-cleanup timer active${RESET} — runs hourly after rentals"
  echo -e "    → Prunes stopped containers + build cache + fstrim (reclaims docker loop space)"
  echo -e "    → Manual: sudo bash scripts/cleanup_now.sh"
  echo ""
  echo -e "  Useful commands:"
  echo -e "    ${CYAN}vastai show machines${RESET}                              — live status"
  echo -e "    ${CYAN}journalctl -u vastai.service -f${RESET}                   — kaalia logs"
  echo -e "    ${CYAN}bash scripts/status.sh${RESET}                            — quick health check"
  echo -e "    ${CYAN}bash scripts/relist.sh${RESET}                            — refresh 90-day listing"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  clear
  banner
  echo ""
  preflight
  collect_inputs
  # Show estimated ports first so user can start configuring router while setup runs
  show_router_guide "Estimated — configure now"
  setup_hostname
  setup_static_ip
  setup_kaalia
  setup_nvidia_toolkit
  setup_docker
  setup_sudoers
  setup_speedtest
  setup_protected_instances
  setup_cleanup_service
  setup_vastai_cli
  restart_services
  push_machine_info
  # Show actual ports detected from Kaalia — confirm/update router rules if different
  show_router_guide "Actual — verify router matches"
  list_machine
  run_self_test
  print_summary
}

main "$@"
