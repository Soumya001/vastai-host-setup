#!/bin/bash
# Manually trigger docker cleanup + fstrim (safe — skips if rental active)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^C\.'; then
  echo -e "${YELLOW}Active rental detected — skipping cleanup to avoid disruption.${RESET}"
  docker ps --format '  {{.Names}}  ({{.Status}})' | grep '^  C\.'
  exit 0
fi

echo "Cleaning stopped containers..."
docker container prune -f 2>/dev/null

echo "Clearing build cache..."
docker builder prune --all -f 2>/dev/null

echo "Running fstrim on docker loop..."
fstrim /var/lib/docker 2>/dev/null

echo ""
echo -e "${GREEN}Cleanup complete.${RESET}"
df -h / /var/lib/docker 2>/dev/null | awk 'NR==1{print "  "$0} NR>1{print "  "$0}'
