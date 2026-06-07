#!/usr/bin/env python3
# manager.sh — Single script: watchdog + price watcher
# Cron: */15 * * * * python3 /path/to/manager.sh
# - Every run (15 min): watchdog — restarts vastai.service if down or stuck
# - Every 4th run (60 min): price watcher — undercuts cheapest competitor

import os, sys, json, subprocess, math, datetime, time

LOG       = os.path.expanduser("~/vastai_manager.log")
STAMP     = os.path.expanduser("~/.vastai_price_last_run")
PRICE_INT = 3600   # seconds between price updates (1 hour)
VAST_FEE  = 1.331
UNDERCUT  = 0.95
MIN_DIFF  = 0.02
FLOOR     = {"RTX 5070": 0.090, "RTX 5060 Ti": 0.060, "RTX 5080": 0.130}
OUR_IDS   = {119138, 119163, 119168, 137402}

def log(msg):
    line = f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG, "a") as f: f.write(line + "\n")
    except Exception: pass

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=30, **kw)

def find_vastai():
    for p in ["/var/lib/vastai_kaalia/data/vast",
              "/root/.local/bin/vastai", "/usr/local/bin/vastai",
              os.path.expanduser("~/.local/bin/vastai")]:
        if os.access(p, os.X_OK): return p
    return None

# ── WATCHDOG ─────────────────────────────────────────────────────────────────
def watchdog():
    svc = run(["systemctl", "is-active", "vastai.service"])
    if svc.stdout.strip() != "active":
        log("WATCHDOG: vastai.service DOWN — restarting")
        run(["sudo", "systemctl", "restart", "vastai.service"])
        time.sleep(4)
        ok = run(["systemctl", "is-active", "vastai.service"]).stdout.strip() == "active"
        log(f"WATCHDOG: {'restarted OK' if ok else 'FAILED to restart'}")
        return

    # Count container failures in last 15 min
    kaalia_log = "/var/lib/vastai_kaalia/kaalia.logX"
    if os.path.exists(kaalia_log):
        since = (datetime.datetime.now() - datetime.timedelta(minutes=15)).strftime("%Y-%m-%d %H:%M")
        r = run(["awk", f'-v s=[{since}',
                 '$0>=s && /docker inspect.*exit code 1/{{c++}} END{{print c+0}}',
                 kaalia_log])
        failures = int(r.stdout.strip() or 0)
        if failures >= 3:
            log(f"WATCHDOG: {failures} container failures in 15min — restarting vastai.service")
            run(["sudo", "systemctl", "restart", "vastai.service"])
            time.sleep(4)
            ok = run(["systemctl", "is-active", "vastai.service"]).stdout.strip() == "active"
            log(f"WATCHDOG: {'restarted OK' if ok else 'FAILED to restart'}")
        else:
            log(f"WATCHDOG: OK ({failures} failures)")

# ── PRICE WATCHER ─────────────────────────────────────────────────────────────
def price_watcher(vastai_bin):
    r = run([vastai_bin, "show", "machines", "--raw"])
    if r.returncode != 0: return
    try: machines = json.loads(r.stdout).get("machines", [])
    except Exception: return

    for m in machines:
        mid, hostname, gpu = m.get("id"), m.get("hostname","?"), m.get("gpu_name","")
        cur, renting = m.get("listed_gpu_cost", 0), m.get("current_rentals_running", 0)
        if renting: log(f"PRICE: {hostname} rented — skip"); continue
        if gpu not in FLOOR: continue

        r2 = run([vastai_bin, "search", "offers", "--raw",
                  f"gpu_name={gpu.replace(' ','_')}"])
        try:
            prices = [o.get("dph_base",999) for o in json.loads(r2.stdout)
                      if isinstance(json.loads(r2.stdout), list) and
                      o.get("machine_id") not in OUR_IDS and o.get("dph_base",0) > 0]
        except Exception: continue
        if not prices: continue

        mkt = min(prices)
        new = max(math.floor(mkt * UNDERCUT / VAST_FEE * 1000)/1000, FLOOR[gpu])
        diff = abs(new - cur) / max(cur, 0.001)

        log(f"PRICE: {hostname} ({gpu}) mkt=${mkt:.3f} cur=${cur:.3f} new=${new:.3f} diff={diff*100:.1f}%")
        if diff < MIN_DIFF: log(f"PRICE: {hostname} already optimal"); continue

        r3 = run([vastai_bin, "list", "machine", str(mid),
                  "--price_gpu", str(new), "--price_min_bid", str(round(new*.8,3)),
                  "--price_disk","0.15","--price_inetu","0.005","--price_inetd","0.005",
                  "--min_chunk","1","--duration","6 months"])
        log(f"PRICE: {hostname} {'UPDATED' if r3.returncode==0 else 'FAILED'} → ${new:.3f}")

def should_run_price():
    try:
        last = float(open(STAMP).read())
        return (time.time() - last) >= PRICE_INT
    except Exception: return True

def mark_price_run():
    with open(STAMP, "w") as f: f.write(str(time.time()))

# ── MAIN ──────────────────────────────────────────────────────────────────────
watchdog()

vastai_bin = find_vastai()
if vastai_bin and should_run_price():
    price_watcher(vastai_bin)
    mark_price_run()
