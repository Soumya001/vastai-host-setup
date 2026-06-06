#!/bin/bash
# Relist all machines on Vast.ai marketplace (refreshes 6-month duration)
# Run this every ~5 months to keep listings active

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

# Prefer Kaalia's own CLI, fall back to pip-installed vastai
VASTAI_BIN=""
for p in /var/lib/vastai_kaalia/data/vast /root/.local/bin/vastai /usr/local/bin/vastai; do
  [[ -x "$p" ]] && VASTAI_BIN="$p" && break
done
[[ -z "$VASTAI_BIN" ]] && VASTAI_BIN=$(command -v vastai 2>/dev/null || echo "")
[[ -z "$VASTAI_BIN" ]] && echo -e "${RED}vastai CLI not found${RESET}" && exit 1

echo -e "${YELLOW}Relisting all machines with 6-month duration...${RESET}"

$VASTAI_BIN show machines 2>/dev/null | grep -oP '^\s+\d+\s+\K[0-9]+' | while read -r MID; do
  GPU_PRICE=$($VASTAI_BIN show machine "$MID" 2>/dev/null | grep -oP 'gpuD_\$/h.*?\K[0-9.]+' | head -1 || echo "0.20")
  echo -n "  Machine $MID (\$${GPU_PRICE}/hr): "
  $VASTAI_BIN list machine "$MID" \
    --price_gpu "$GPU_PRICE" \
    --price_min_bid "$(python3 -c "print(round(float('$GPU_PRICE')*0.8,3))" 2>/dev/null || echo 0.16)" \
    --price_disk 0.15 \
    --price_inetu 0.005 \
    --price_inetd 0.005 \
    --min_chunk 1 \
    --duration "6 months" 2>&1 | grep -oP 'created/updated.*' || echo "done"
done

echo -e "${GREEN}Done. Listings active for 6 months.${RESET}"
