<div align="center">

# 🖥️ Vast.ai Host Setup

### One command to list your GPU machine on Vast.ai and start earning crypto

[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian-orange?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![GPU](https://img.shields.io/badge/GPU-NVIDIA%20Required-76B900?logo=nvidia&logoColor=white)](https://nvidia.com)
[![License](https://img.shields.io/badge/License-MIT-blue)](LICENSE)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen)](https://github.com/Soumya001/vastai-host-setup)
[![Vast.ai](https://img.shields.io/badge/Platform-Vast.ai-purple)](https://vast.ai)

<br/>

> **Automates everything:** static IP, port forwarding guide, Kaalia daemon install, Docker config, NVIDIA setup, marketplace listing, self-test verification, hourly storage cleanup, and **auto price adjustment** — all from a single interactive script.

</div>

---

## ⚡ Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/Soumya001/vastai-host-setup/main/setup.sh -o setup.sh
sudo bash setup.sh
```

> Answer the prompts → configure router ports → machine goes live in **~10 minutes**.

---

## 🎯 What This Project Does

Most GPU owners lose money because setup is complex. This script handles **everything** needed to list a machine on [Vast.ai](https://vast.ai) — the GPU cloud marketplace where your idle hardware earns real money.

**Problems it solves:**
- 🔧 Kaalia installer crashes on Python 3.13+ → **auto-patched**
- 🌐 Public IP & ports not configured → **auto-detected & guided**
- 🔑 API key setup scattered → **single input, applied everywhere**
- ❓ Unknown CPU showing on dashboard → **Docker image corruption fix**
- 💾 Disk fills up after rentals → **hourly auto-cleanup with fstrim**
- ✅ Machine stays unverified → **self-test runs automatically**
- 💰 Competitors undercut your price → **hourly auto price watcher keeps you cheapest**

---

## 🖥️ Compatible Devices

| Device | Supported | Notes |
|--------|:---------:|-------|
| 🐧 **Linux + NVIDIA GPU** | ✅ **Yes** | Full support — best earnings |
| 🐧 Linux + AMD GPU | ⚠️ Partial | Limited workload support |
| 🪟 Windows | ❌ No | Kaalia daemon is Linux-only |
| 🍎 Mac | ❌ No | No CUDA support |

> 💡 **Manage from anywhere:** SSH into your Linux machine from Mac, Windows, or Linux.

---

## 📋 Requirements

| | Minimum |
|--|---------|
| 🐧 **OS** | Ubuntu 22.04 / 24.04 or Debian 12 |
| 🎮 **GPU** | NVIDIA RTX / Tesla / A-series with drivers installed |
| 🧠 **RAM** | **Must be ≥ GPU VRAM** *(RTX 5080 16GB needs 17GB+ RAM)* |
| 💾 **Storage** | 200 GB+ SSD recommended |
| 🌐 **Internet** | 100 Mbps+ (500 Mbps+ for verified badge) |
| 🔑 **Account** | [Vast.ai](https://vast.ai) account + API key |
| 🔀 **Router** | Access to add port forwarding rules |

---

## 🚀 Setup — Step by Step

### 1. Download & Run

```bash
curl -fsSL https://raw.githubusercontent.com/Soumya001/vastai-host-setup/main/setup.sh -o setup.sh
sudo bash setup.sh
```

### 2. Answer the Prompts

| Prompt | Auto-detected? | Notes |
|--------|:--------------:|-------|
| Vast.ai API key | ❌ | [console.vast.ai → Account](https://console.vast.ai/) |
| Hostname | ❌ | e.g. `gpu-rig-1` |
| Machine number | ❌ | Sequential per machine (1, 2, 3...) |
| Port range | ✅ Auto-calc | Can override if needed |
| Public IP | ✅ Auto-detect | Your router's WAN IP |
| LAN IP | ✅ Auto-detect | This machine's fixed internal IP |
| Gateway | ✅ Auto-detect | Router IP |
| Network interface | ✅ Auto-detect | NIC name |
| GPU price $/hr | ❌ | Check [vast.ai marketplace](https://vast.ai) |
| Speedtest server | Optional | Leave blank to auto-select |

### 3. Configure Router Port Forwarding

The script tells you **exactly which ports to forward**. Example for 4 machines:

```
┌──────────────────────────────────────────────────────────┐
│  Machine 1 → forward ports 20000–20499 → 192.168.0.X     │
│  Machine 2 → forward ports 20500–20999 → 192.168.0.Y     │
│  Machine 3 → forward ports 21000–21499 → 192.168.0.Z     │
│  Machine 4 → forward ports 21500–21999 → 192.168.0.W     │
└──────────────────────────────────────────────────────────┘
```

All machines can share **one public IP** — port ranges separate them.

---

## 🔧 What Gets Configured Automatically

| Step | What Happens |
|------|-------------|
| 🛠️ Pre-flight | Checks OS, NVIDIA drivers, Docker |
| 🌍 Static IP | Configures via netplan (survives reboots) |
| ⚙️ Kaalia Daemon | Downloads, patches Python 3.13+ fix, installs |
| 🐳 Docker | Sets nvidia runtime without breaking non-GPU containers |
| 🎮 NVIDIA Toolkit | Installs + verifies GPU accessible in Docker |
| 📖 dmidecode | Installs + sudoers (fixes "Unknown CPU" on dashboard) |
| 🏃 Services | Starts vastai + metrics, disables broken bouncer |
| 🔄 Auto-cleanup | Hourly timer: prune containers + build cache + fstrim |
| 💰 Price watcher | Hourly cron: checks market, auto-undercuts cheapest competitor |
| 🐕 Watchdog | Every 15 min: restarts Kaalia if down or containers stuck-failing |
| 📋 Listing | Lists machine on marketplace with your pricing |
| ✅ Self-test | Runs Vast.ai verification (GPU, RAM, ECC, NCCL tests) |

---

## 🛠️ Included Scripts

```
vastai-host-setup/
├── setup.sh              ← Full one-command setup (run this first)
├── push.sh               ← Push updates to GitHub
├── README.md
└── scripts/
    ├── status.sh         ← Live machine health check
    ├── cleanup_now.sh    ← Manual docker prune + fstrim
    ├── relist.sh         ← Refresh 6-month marketplace listing

    └── manager.sh        ← Watchdog + price adjuster in one (runs every 15 min)
```

```bash
# Health check
bash scripts/status.sh

# Clean storage after rental (safe — skips if rented)
sudo bash scripts/cleanup_now.sh

# Refresh listing (run every ~5 months)
bash scripts/relist.sh

# Run price watcher manually (also runs automatically every hour)
python3 scripts/price_watcher.sh

# Run watchdog manually (also runs automatically every 15 min)
bash scripts/watchdog.sh
```

---

## 💰 Auto Price Watcher

The `price_watcher.sh` script runs **every hour via cron** and automatically adjusts your prices to stay the cheapest on the market.

**How it works:**
1. 📊 Fetches current market prices for your GPU model from Vast.ai
2. 🏆 Finds the **cheapest competitor** (excluding your own machines)
3. 💲 Sets your price to **5% below theirs** so you're always #1 cheapest
4. 🛑 Skips machines that are **currently rented** — never interrupts an active rental
5. 🔒 Respects **floor prices** so you never rent at a loss

| GPU | Floor price (shown to renters) |
|-----|-------------------------------|
| RTX 5060 Ti | $0.080/hr minimum |
| RTX 5070 | $0.120/hr minimum |
| RTX 5080 | $0.173/hr minimum |

**Setup (one time):**
```bash
# Add to crontab — runs every hour automatically
(crontab -l 2>/dev/null; echo "0 * * * * /usr/bin/python3 /path/to/scripts/price_watcher.sh >> ~/vastai_price_watcher.log 2>&1") | crontab -
```

**Check logs:**
```bash
tail -50 ~/vastai_price_watcher.log
```

---

## 💾 Auto Storage Cleanup

After every rental, a **systemd timer fires hourly** and:
1. 🛑 Checks no rental containers (`C.*`) are running
2. 🗑️ Prunes stopped containers + all build cache
3. 💿 Runs `fstrim` on Docker loop filesystem → **reclaims hundreds of GB**

Keeps machines at **~4–9% disk usage** when idle instead of ballooning to 30–40%.

---

## ✅ Verification

Vast.ai verifies machines that pass the self-test:

| Test | Requirement |
|------|------------|
| ResNet18 GPU test | Must pass |
| ECC memory test | Must pass |
| NCCL distributed test | Must pass |
| Stress test (60s) | Must pass |
| **RAM ≥ GPU VRAM** | **Hard requirement — cannot bypass** |
| Internet ≥ 500 Mbps | For verified badge (still rents without) |

---

## 🔴 Common Issues & Fixes

| ❌ Problem | ✅ Fix |
|-----------|--------|
| Installer crashes (Python 3.13+) | Auto-patched by setup.sh |
| "Unknown CPU" on dashboard | Restart `vastai.service` |
| Speed showing 0 Mbps | Wait 10 min — Kaalia auto-reports |
| Self-test: **RAM < VRAM** | Add physical RAM — hardware requirement |
| Self-test: **No offers found** | `bash scripts/relist.sh` |
| Non-GPU containers fail | Ensure `default-runtime` NOT set to `nvidia` in daemon.json |
| `vastai_bouncer` fails | Auto-disabled by setup.sh |
| Storage fills up | Auto-cleanup timer handles it hourly |

---

## 🌐 Manage from Any Device

```bash
# Mac / Linux
ssh youruser@YOUR_PUBLIC_IP

# Windows — use Windows Terminal or PuTTY
ssh youruser@YOUR_PUBLIC_IP
```

Check your machines anytime at **[console.vast.ai/host/machines](https://console.vast.ai/host/machines)**

---

## ❤️ Support This Project

If this saved you hours of setup time, consider a small donation:

<div align="center">

| Currency | Address |
|----------|---------|
| ![BTC](https://img.shields.io/badge/Bitcoin-BTC-F7931A?logo=bitcoin&logoColor=white) | `bc1qevyu9pngzdq54v592whjf9tm5mcztv46zpu40p` |
| ![BCH](https://img.shields.io/badge/Bitcoin_Cash-BCH-8DC351?logo=bitcoincash&logoColor=white) | `qp2yjsakctklphd32f3ut75zc08ntcrnf5ryhfvj86` |

*Every satoshi helps keep this project maintained and updated!* 🙏

</div>

---

## 📄 License

[MIT License](LICENSE) — free to use, modify, and share.

---

<div align="center">

**Built from real-world experience setting up multiple GPU rigs on Vast.ai.**
<br/>
⭐ Star this repo if it helped you!

</div>
