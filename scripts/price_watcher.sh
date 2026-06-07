#!/usr/bin/env python3
# price_watcher.sh — Auto-adjusts machine prices to stay cheapest on market
# Runs hourly via cron. Skips machines that are currently rented.

import json, subprocess, math, datetime, os, sys

VAST_FEE = 1.331   # Vast.ai adds ~33.1% on top of listed price
UNDERCUT  = 0.95   # Target 5% below cheapest competitor
MIN_DIFF  = 0.02   # Only update if price changes by more than 2%
LOG       = os.path.expanduser("~/vastai_price_watcher.log")

# Floor prices (listed) — never go below these regardless of competition
FLOOR = {
    "RTX 5070":    0.090,   # shows ~$0.120 to renters
    "RTX 5060 Ti": 0.060,   # shows ~$0.080 to renters
    "RTX 5080":    0.130,   # shows ~$0.173 to renters
}
OUR_IDS = {119138, 119163, 119168, 137402}

def log(msg):
    line = f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def find_vastai():
    for p in ["/var/lib/vastai_kaalia/data/vast", "/root/.local/bin/vastai",
              "/usr/local/bin/vastai", os.path.expanduser("~/.local/bin/vastai")]:
        if os.access(p, os.X_OK):
            return p
    return None

def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kwargs)

def get_market_min(vastai_bin, gpu_name):
    r = run([vastai_bin, "search", "offers", "--raw",
             f"gpu_name={gpu_name.replace(' ', '_')}"])
    if r.returncode != 0:
        return None
    try:
        offers = json.loads(r.stdout)
        if not isinstance(offers, list):
            return None
        prices = [o.get("dph_base", 999) for o in offers
                  if o.get("machine_id") not in OUR_IDS and o.get("dph_base", 0) > 0]
        return min(prices) if prices else None
    except Exception:
        return None

def main():
    log("--- price watcher run ---")

    vastai_bin = find_vastai()
    if not vastai_bin:
        log("ERROR: vastai CLI not found")
        sys.exit(1)

    r = run([vastai_bin, "show", "machines", "--raw"])
    if r.returncode != 0:
        log(f"ERROR: show machines failed — {r.stderr.strip()[:100]}")
        sys.exit(1)

    try:
        data = json.loads(r.stdout)
        machines = data.get("machines", [])
    except Exception as e:
        log(f"ERROR: JSON parse failed — {e}")
        sys.exit(1)

    for m in machines:
        mid        = m.get("id")
        hostname   = m.get("hostname", "?")
        gpu_name   = m.get("gpu_name", "")
        cur_listed = m.get("listed_gpu_cost", 0)
        renting    = m.get("current_rentals_running", 0)

        if renting > 0:
            log(f"{hostname}: currently rented — skipping")
            continue

        if gpu_name not in FLOOR:
            log(f"{hostname}: GPU '{gpu_name}' not tracked — skipping")
            continue

        market_min = get_market_min(vastai_bin, gpu_name)
        if market_min is None:
            log(f"{hostname}: could not fetch market prices — skipping")
            continue

        target = math.floor((market_min * UNDERCUT / VAST_FEE) * 1000) / 1000
        new    = max(target, FLOOR[gpu_name])
        diff   = abs(new - cur_listed) / max(cur_listed, 0.001)

        log(f"{hostname} ({gpu_name}): cheapest_competitor=${market_min:.3f} shown | "
            f"cur=${cur_listed:.3f} → new=${new:.3f} listed (~${new*VAST_FEE:.3f} shown) | "
            f"change={diff*100:.1f}%")

        if diff < MIN_DIFF:
            log(f"{hostname}: already optimal")
            continue

        min_bid = round(new * 0.8, 3)
        r2 = run([vastai_bin, "list", "machine", str(mid),
                  "--price_gpu",     str(new),
                  "--price_min_bid", str(min_bid),
                  "--price_disk",    "0.15",
                  "--price_inetu",   "0.005",
                  "--price_inetd",   "0.005",
                  "--min_chunk",     "1",
                  "--duration",      "6 months"])

        if r2.returncode == 0:
            log(f"{hostname}: UPDATED ${cur_listed:.3f} → ${new:.3f} listed (~${new*VAST_FEE:.3f} shown)")
        else:
            log(f"{hostname}: UPDATE FAILED — {r2.stderr.strip()[:120]}")

    log("--- done ---")

if __name__ == "__main__":
    main()
