#!/bin/bash
# Relist all machines on Vast.ai marketplace (refreshes 90-day end date)
# Run this every ~80 days to keep listings active

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

VASTAI_BIN=$(find /root/.local/bin /home -name vastai -type f 2>/dev/null | head -1 || echo "vastai")
END_DATE=$(python3 -c "import time; print(int(time.time() + 90*86400))")

echo -e "${YELLOW}Relisting all machines with fresh 90-day end date...${RESET}"

$VASTAI_BIN show machines 2>/dev/null | grep -oP '^\s+\d+\s+\K[0-9]+' | while read -r MID; do
  GPU_PRICE=$($VASTAI_BIN show machine "$MID" 2>/dev/null | grep -oP 'gpuD_\$/h.*?\K[0-9.]+' | head -1 || echo "0.20")
  echo -n "  Machine $MID (\$${GPU_PRICE}/hr): "
  $VASTAI_BIN list machine "$MID" \
    --price_gpu "$GPU_PRICE" \
    --price_disk 0.01 \
    --price_inetu 0.005 \
    --price_inetd 0.005 \
    --end_date "$END_DATE" 2>&1 | grep -oP 'created/updated.*' || echo "done"
done

echo -e "${GREEN}Done. Listings expire in 90 days.${RESET}"
