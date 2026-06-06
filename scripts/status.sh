#!/bin/bash
# Quick status check for all Vast.ai services and machine health

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

svc_status() {
  systemctl is-active --quiet "$1" 2>/dev/null \
    && echo -e "${GREEN}running${RESET}" \
    || echo -e "${RED}stopped${RESET}"
}

echo -e "${BOLD}═══ Vast.ai Machine Status ═══════════════════════════${RESET}"
echo ""

echo -e "${CYAN}Services:${RESET}"
echo -e "  vastai.service              : $(svc_status vastai.service)"
echo -e "  vast_metrics.service        : $(svc_status vast_metrics.service)"
echo -e "  vastai_docker_cleanup.timer : $(svc_status vastai_docker_cleanup.timer)"
echo ""

echo -e "${CYAN}Disk:${RESET}"
df -h / /var/lib/docker 2>/dev/null | awk 'NR==1{print "  "$0} NR>1{print "  "$0}'
echo ""

echo -e "${CYAN}Docker:${RESET}"
docker system df 2>/dev/null | awk 'NR==1{print "  "$0} NR>1{print "  "$0}'
echo ""

echo -e "${CYAN}Active containers:${RESET}"
CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null)
if [[ -z "$CONTAINERS" ]]; then
  echo -e "  ${YELLOW}None (machine free)${RESET}"
else
  echo "$CONTAINERS" | while read -r c; do
    [[ "$c" == C.* ]] && echo -e "  ${GREEN}[RENTED]${RESET} $c" || echo -e "  $c"
  done
fi
echo ""

echo -e "${CYAN}GPU:${RESET}"
nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total \
  --format=csv,noheader 2>/dev/null | while IFS=',' read -r idx name temp util memused memtotal; do
  echo -e "  GPU $idx: $name | ${temp}°C | util:${util} | mem: ${memused}/${memtotal}"
done
echo ""

echo -e "${CYAN}Machine ID:${RESET}"
echo -e "  $(cat /var/lib/vastai_kaalia/machine_id 2>/dev/null || echo 'not registered')"
