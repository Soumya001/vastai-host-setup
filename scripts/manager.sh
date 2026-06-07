#!/usr/bin/env python3
# manager.sh — Single script: watchdog + price watcher
# Cron: */15 * * * * python3 /path/to/manager.sh
# - Every run (15 min): watchdog — restarts vastai.service if down or stuck
# - Every 4th run (60 min): price watcher — undercuts cheapest competitor

import os, sys, json, subprocess, math, datetime, time

LOG       = os.path.expanduser("~/vastai_manager.log")
STAMP     = os.path.expanduser("~/.vastai_price_last_run")
LOCK      = os.path.expanduser("~/.vastai_manager.lock")
PRICE_INT = 3600   # seconds between price updates (1 hour)
LOG_MAX   = 2000   # max log lines before rotation
VAST_FEE  = 1.331
UNDERCUT  = 0.95
MIN_DIFF  = 0.02
FLOOR     = {"RTX 5070": 0.090, "RTX 5060 Ti": 0.060, "RTX 5080": 0.130}
OUR_IDS   = {119138, 119163, 119168, 137402}

def log(msg):
    line = f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass

def rotate_log():
    try:
        if not os.path.exists(LOG):
            return
        lines = open(LOG).readlines()
        if len(lines) > LOG_MAX:
            with open(LOG, "w") as f:
                f.writelines(lines[-LOG_MAX:])
    except Exception:
        pass

def acquire_lock():
    """Return True if we got the lock, False if another instance is running."""
    try:
        if os.path.exists(LOCK):
            age = time.time() - os.path.getmtime(LOCK)
            if age < 840:  # 14 min — younger than one cron interval
                return False
            os.remove(LOCK)  # stale lock from a crashed run
        with open(LOCK, "w") as f:
            f.write(str(os.getpid()))
        return True
    except Exception:
        return True  # if lock check itself fails, proceed

def release_lock():
    try:
        os.remove(LOCK)
    except Exception:
        pass

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kw)

def find_vastai():
    for p in ["/var/lib/vastai_kaalia/data/vast",
              "/root/.local/bin/vastai", "/usr/local/bin/vastai",
              os.path.expanduser("~/.local/bin/vastai")]:
        if os.access(p, os.X_OK):
            return p
    return None

# ── WATCHDOG ─────────────────────────────────────────────────────────────────
def watchdog():
    svc = run(["systemctl", "is-active", "vastai.service"])
    if svc.stdout.strip() != "active":
        log("WATCHDOG: vastai.service DOWN — restarting")
        r = run(["sudo", "systemctl", "restart", "vastai.service"])
        if r.returncode != 0:
            log(f"WATCHDOG: restart command failed — {r.stderr.strip()[:100]}")
        time.sleep(4)
        ok = run(["systemctl", "is-active", "vastai.service"]).stdout.strip() == "active"
        log(f"WATCHDOG: {'restarted OK' if ok else 'FAILED to restart'}")
        return

    # Count container failures in last 15 min
    kaalia_log = "/var/lib/vastai_kaalia/kaalia.logX"
    if not os.path.exists(kaalia_log):
        log("WATCHDOG: OK (no kaalia log yet)")
        return

    since = (datetime.datetime.now() - datetime.timedelta(minutes=15)).strftime("%Y-%m-%d %H:%M")
    r = run(["awk", f'-v s=[{since}',
             '$0>=s && /docker inspect.*exit code 1/{c++} END{print c+0}',
             kaalia_log])
    try:
        failures = int(r.stdout.strip() or 0)
    except ValueError:
        failures = 0

    if failures >= 3:
        log(f"WATCHDOG: {failures} container failures in 15min — restarting vastai.service")
        r = run(["sudo", "systemctl", "restart", "vastai.service"])
        if r.returncode != 0:
            log(f"WATCHDOG: restart command failed — {r.stderr.strip()[:100]}")
        time.sleep(4)
        ok = run(["systemctl", "is-active", "vastai.service"]).stdout.strip() == "active"
        log(f"WATCHDOG: {'restarted OK' if ok else 'FAILED to restart'}")
    else:
        log(f"WATCHDOG: OK ({failures} failures)")

# ── PRICE WATCHER ─────────────────────────────────────────────────────────────
def get_market_min(vastai_bin, gpu):
    r = run([vastai_bin, "search", "offers", "--raw",
             f"gpu_name={gpu.replace(' ', '_')}"])
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

def price_watcher(vastai_bin):
    r = run([vastai_bin, "show", "machines", "--raw"])
    if r.returncode != 0:
        log(f"PRICE: show machines failed — {r.stderr.strip()[:100]}")
        return
    try:
        machines = json.loads(r.stdout).get("machines", [])
    except Exception as e:
        log(f"PRICE: JSON parse failed — {e}")
        return

    for m in machines:
        mid      = m.get("id")
        hostname = m.get("hostname", "?")
        gpu      = m.get("gpu_name", "")
        cur      = m.get("listed_gpu_cost", 0)
        renting  = m.get("current_rentals_running", 0)

        if renting:
            log(f"PRICE: {hostname} rented — skip")
            continue

        if gpu not in FLOOR:
            log(f"PRICE: {hostname} GPU '{gpu}' not in floor table — skip")
            continue

        mkt = get_market_min(vastai_bin, gpu)
        if mkt is None:
            log(f"PRICE: {hostname} ({gpu}) could not fetch market prices — skip")
            continue

        new  = max(math.floor(mkt * UNDERCUT / VAST_FEE * 1000) / 1000, FLOOR[gpu])
        diff = abs(new - cur) / max(cur, 0.001)

        log(f"PRICE: {hostname} ({gpu}) mkt=${mkt:.3f} cur=${cur:.3f} new=${new:.3f} diff={diff*100:.1f}%")
        if diff < MIN_DIFF:
            log(f"PRICE: {hostname} already optimal")
            continue

        r2 = run([vastai_bin, "list", "machine", str(mid),
                  "--price_gpu",     str(new),
                  "--price_min_bid", str(round(new * 0.8, 3)),
                  "--price_disk",    "0.15",
                  "--price_inetu",   "0.005",
                  "--price_inetd",   "0.005",
                  "--min_chunk",     "1",
                  "--duration",      "6 months"])
        if r2.returncode == 0:
            log(f"PRICE: {hostname} UPDATED ${cur:.3f} → ${new:.3f} (~${new*VAST_FEE:.3f} shown)")
        else:
            log(f"PRICE: {hostname} UPDATE FAILED — {r2.stderr.strip()[:120]}")

def should_run_price():
    try:
        last = float(open(STAMP).read().strip())
        return (time.time() - last) >= PRICE_INT
    except Exception:
        return True

def mark_price_run():
    try:
        with open(STAMP, "w") as f:
            f.write(str(time.time()))
    except Exception as e:
        log(f"PRICE: could not write stamp — {e}")

# ── MAIN ──────────────────────────────────────────────────────────────────────
if not acquire_lock():
    print(f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] already running — exit")
    sys.exit(0)

try:
    rotate_log()
    watchdog()

    vastai_bin = find_vastai()
    if not vastai_bin:
        log("PRICE: vastai CLI not found — skipping price update")
    elif should_run_price():
        price_watcher(vastai_bin)
        mark_price_run()
finally:
    release_lock()
