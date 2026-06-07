#!/bin/bash
# watchdog.sh — Auto-recovers stuck vastai.service (runs every 15 min via cron)
LOG="$HOME/vastai_watchdog.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Restart if service is down
if ! systemctl is-active --quiet vastai.service; then
    log "DOWN — restarting"; sudo systemctl restart vastai.service; sleep 3
    systemctl is-active --quiet vastai.service && log "restarted OK" || log "FAILED to restart"
    exit 0
fi

# Restart if 3+ container failures in last 15 min (stuck state)
SINCE=$(date -d "15 minutes ago" '+%Y-%m-%d %H:%M' 2>/dev/null)
FAILS=$(awk -v s="[$SINCE" '$0>=s && /docker inspect.*exit code 1/{c++} END{print c+0}' \
    /var/lib/vastai_kaalia/kaalia.logX 2>/dev/null)
if [[ "$FAILS" -ge 3 ]]; then
    log "STUCK — $FAILS failures in 15min, restarting"
    sudo systemctl restart vastai.service; sleep 3
    systemctl is-active --quiet vastai.service && log "restarted OK" || log "FAILED to restart"
else
    log "OK ($FAILS failures)"
fi
